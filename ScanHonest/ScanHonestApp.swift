import SwiftUI
import SwiftData
import PDFKit

@main
struct ScanHonestApp: App {
    @StateObject private var storeKitManager  = StoreKitManager()
    @StateObject private var scanLimitManager = ScanLimitManager()
    @StateObject private var nearbyShare      = NearbyShareManager.shared
    @StateObject private var lockService      = LockService.shared

    // CRIT-02 FIX: never use try! for ModelContainer.
    // On schema migration failure try! crashes every user's install at launch.
    // We now try iCloud-backed config first; if that fails (e.g. entitlements not
    // provisioned on a new dev device) we fall back to local-only with a log message
    // — no crash in either case.
    let sharedModelContainer: ModelContainer

    init() {
        // UI test support: reset/configure state via launch arguments
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let domain = Bundle.main.bundleIdentifier!
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        if ProcessInfo.processInfo.arguments.contains("--skipOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
        if ProcessInfo.processInfo.arguments.contains("--showOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        if ProcessInfo.processInfo.arguments.contains("--isPro") {
            // @AppStorage("isPro") var storedIsPro reads key "isPro" — match it.
            UserDefaults.standard.set(true, forKey: "isPro")
        }

        // Initialise StoreKit / ScanLimit before the container so they are ready
        // when the first SwiftUI body runs.
        let skm  = StoreKitManager()
        let slm  = ScanLimitManager()
        let ns   = NearbyShareManager.shared
        let ls   = LockService.shared
        _storeKitManager  = StateObject(wrappedValue: skm)
        _scanLimitManager = StateObject(wrappedValue: slm)
        _nearbyShare      = StateObject(wrappedValue: ns)
        _lockService      = StateObject(wrappedValue: ls)

        let schema = Schema([ScannedDocument.self, DocumentFolder.self])

        // Try iCloud-backed store first. If that fails (container not yet
        // registered in ASC, device not signed into iCloud, or schema change)
        // fall back to a plain local SQLite store.
        // Neither path uses try! — a ModelContainer failure is always caught
        // and handled gracefully so the app never crashes at launch.
        if let container = ScanHonestApp.makeContainer(schema: schema, iCloud: true) ??
                           ScanHonestApp.makeContainer(schema: schema, iCloud: false) {
            sharedModelContainer = container
        } else {
            // Absolute last resort: in-memory store.
            // This path is only reached if the on-device SQLite directory is
            // unwritable (full sandbox / corrupted container) — an unrecoverable
            // state where even a crash gives the user no better outcome.
            sharedModelContainer = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            print("[ScanHonest] CRITICAL: all persistent store options failed — using in-memory store")
        }
    }

    // MARK: - ModelContainer factory

    /// Attempts to create a ModelContainer with or without CloudKit.
    /// Returns nil on any failure — never throws, never crashes.
    private static func makeContainer(schema: Schema, iCloud: Bool) -> ModelContainer? {
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: iCloud ? .automatic : .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            print("[ScanHonest] ModelContainer ready (iCloud: \(iCloud))")
            return container
        } catch {
            print("[ScanHonest] ModelContainer failed (iCloud: \(iCloud)): \(error.localizedDescription)")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .privacyShielded()                          // app-switcher blur (outermost)
                .biometricLocked(by: lockService)           // biometric gate (below blur)
                .environmentObject(storeKitManager)
                .environmentObject(scanLimitManager)
                .sheet(
                    isPresented: Binding(
                        get: {
                            nearbyShare.incomingRequest != nil ||
                            (nearbyShare.isAdvertising && nearbyShare.phase != .idle)
                        },
                        set: { if !$0 { nearbyShare.disconnect() } }
                    )
                ) {
                    IncomingTransferPrompt(manager: nearbyShare)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(24)
                }
                .onAppear {
                    // UITest seeding: inject a synthetic document so tests can reach
                    // DocumentDetailView without requiring camera or photo picker.
                    if ProcessInfo.processInfo.arguments.contains("--seedTestDocument") {
                        ScanHonestApp.seedTestDocument(into: sharedModelContainer)
                    }
                    NetworkMonitor.shared.startMonitoring()
                    iCloudMonitor.shared.startMonitoring()
                    // DO NOT call nearbyShare.startAdvertising() here.
                    // Starting MCNearbyServiceAdvertiser at launch immediately
                    // triggers the iOS "Local Network" permission popup before
                    // the user has done anything Nearby-related.
                    // Advertising is started lazily the first time the user taps
                    // "Nearby Share" in the share sheet — see CustomShareSheet.nearbyRow.
                }
                .onReceive(NotificationCenter.default.publisher(for: .nearbyShareReceived)) { note in
                    guard let document = note.object as? ScannedDocument else { return }
                    sharedModelContainer.mainContext.insert(document)
                    if !storeKitManager.isPro { scanLimitManager.recordScan() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .subscriptionStatusDidChange)) { _ in
                    // Keep widget in sync whenever the subscription status changes
                    WidgetDataWriter.shared.flush(
                        scansUsed:  scanLimitManager.scansUsedThisMonth,
                        scansLimit: ScanLimitManager.freeMonthlyLimit,
                        isPro:      storeKitManager.isPro,
                        recentDocs: []
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .ddDuplicate)) { note in
                    guard let doc = note.object as? ScannedDocument else { return }
                    sharedModelContainer.mainContext.insert(doc)
                }
                // CRIT-05 FIX: handle delete notification from DocumentDetailView
                // so the SwiftData record is removed as well as the file on disk.
                .onReceive(NotificationCenter.default.publisher(for: .ddDelete)) { note in
                    guard let doc = note.object as? ScannedDocument else { return }
                    sharedModelContainer.mainContext.delete(doc)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - UITest document seed

    /// Creates one synthetic ScannedDocument (a 1-page PDF with white content)
    /// so UITests that need DocumentDetailView can find a document in the grid.
    /// Only called when the app is launched with --seedTestDocument.
    @MainActor
    static func seedTestDocument(into container: ModelContainer) {
        let ctx = container.mainContext

        // Always wipe stale documents from previous test runs.
        // Only UserDefaults is cleared by --uitesting; the SwiftData SQLite store
        // persists across runs. Stale records may point to missing or wrong files,
        // causing prepareURLs to throw fileMissing → share sheet never dismisses.
        let existing = (try? ctx.fetch(FetchDescriptor<ScannedDocument>())) ?? []
        for doc in existing { ctx.delete(doc) }

        // Write a minimal PDF directly — bypass StorageManager encryption so the
        // seed always succeeds even when Keychain is unavailable in UITest sandbox.
        let fm      = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let seedDir = docsDir.appendingPathComponent("ScanHonest", isDirectory: true)
        try? fm.createDirectory(at: seedDir, withIntermediateDirectories: true)
        let fileURL = seedDir.appendingPathComponent("UITestDoc.pdf")

        let pdfDoc = PDFDocument()
        pdfDoc.insert(PDFPage(), at: 0)
        guard pdfDoc.write(to: fileURL) else { return }

        let fileSize = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int)
                           .flatMap { Int64($0) } ?? 1024

        let doc = ScannedDocument(
            name: "Test Document",
            pageCount: 1,
            fileSizeBytes: fileSize,
            fileURL: fileURL,
            thumbnailData: nil
        )
        ctx.insert(doc)
        try? ctx.save()
        print("[UITest] Seeded test document at \(fileURL.path)")
    }
}
