import SwiftUI
import SwiftData

@main
struct ScanHonestApp: App {
    @StateObject private var storeKitManager  = StoreKitManager()
    @StateObject private var scanLimitManager = ScanLimitManager()

    // NetworkMonitor and iCloudMonitor are singletons — NOT @StateObject.
    // Making them @StateObject caused ERROR 1: "iCloudMonitor.shared" was
    // ambiguous because the property name "iCloudMonitor" shadowed the type
    // name "iCloudMonitor", creating a circular reference at init time.
    // They are accessed via .shared and started in onAppear instead.

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([ScannedDocument.self, DocumentFolder.self])
        // CloudKit automatic sync — falls back to local if unavailable
        let config: ModelConfiguration
        do {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Simulator / no iCloud login — local only
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(storeKitManager)
                .environmentObject(scanLimitManager)
                .onAppear {
                    // Start singletons after app is fully initialized
                    NetworkMonitor.shared.startMonitoring()
                    iCloudMonitor.shared.startMonitoring()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .subscriptionStatusDidChange)
                ) { _ in
                    // @Published on StoreKitManager already drives UI — no action needed
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
