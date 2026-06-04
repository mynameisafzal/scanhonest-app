import SwiftUI
import PDFKit
import SwiftData
import AVFoundation

// MARK: - ScannerView
// CHANGE 3: Added camera permission check on appear.
// If denied, shows actionable alert with "Open Settings" instead of broken camera.

struct ScannerView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var scanLimitManager: ScanLimitManager
    @EnvironmentObject var storeKitManager: StoreKitManager
    @Environment(\.modelContext) private var modelContext

    // Wraps captured images with a stable identity so fullScreenCover(item:)
    // only evaluates its content closure AFTER the item is non-nil — eliminating
    // the race where fullScreenCover(isPresented:) could snapshot an empty array.
    private struct CapturedScan: Identifiable {
        let id = UUID()
        let images: [UIImage]
    }

    @State private var capturedScan: CapturedScan?
    // CHANGE 3: permission denied state
    @State private var showPermissionDenied = false

    // Reads the same key that SettingsView writes so the choice is respected here.
    @AppStorage("autoCaptureEnabled") private var autoCaptureEnabled = false

    var body: some View {
        ZStack {
#if targetEnvironment(simulator)
            SimulatorPlaceholderView(isPresented: $isPresented)
#else
            // Both modes use our custom scanner — the only difference is
            // isAutoCapture: true fires the shutter automatically after stable
            // detection; false requires the user to tap the green button.
            // Both share the same green button, flash toggle, and filter cycle.
            ManualDocumentScannerView(
                isPresented:   $isPresented,
                onScan:        { images in capturedScan = CapturedScan(images: images) },
                isAutoCapture: autoCaptureEnabled
            )
            .ignoresSafeArea()
#endif
        }
        // fullScreenCover(item:) guarantees the closure runs only after capturedScan
        // is non-nil, so ScanReviewView always receives the real images array.
        .fullScreenCover(item: $capturedScan) { scan in
            ScanReviewView(
                images: scan.images,
                isPresented: Binding(
                    get: { capturedScan != nil },
                    set: { if !$0 { capturedScan = nil } }
                ),
                onSave: { document in saveDocument(document) }
            )
            .environmentObject(storeKitManager)
            .environmentObject(scanLimitManager)
        }
        // CHANGE 3: Check permission on appear — show alert if denied
        .onAppear { checkCameraPermission() }
        .alert("Camera Access Required", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                isPresented = false
            }
        } message: {
            Text("ScanHonest needs camera access to scan documents. Tap Open Settings to enable it.")
        }
    }

    // CHANGE 3: Check AVCaptureDevice authorization status
    private func checkCameraPermission() {
#if !targetEnvironment(simulator)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break                           // all good — camera will show normally
        case .notDetermined:
            break                           // AVCaptureSession will prompt the user
        case .denied, .restricted:
            showPermissionDenied = true     // guide user to Settings
        @unknown default:
            break
        }
#endif
    }

    private func saveDocument(_ document: ScannedDocument) {
        modelContext.insert(document)
        if !storeKitManager.isPro {
            scanLimitManager.recordScan()
        }

        // Flush widget data so the home-screen widget reflects the new scan immediately.
        // Fetch the 3 most-recent documents after insert for the widget "Recent" list.
        Task { @MainActor in
            let descriptor = FetchDescriptor<ScannedDocument>(
                sortBy: [SortDescriptor(\.dateModified, order: .reverse)]
            )
            let recent = (try? modelContext.fetch(descriptor))?.prefix(3) ?? []
            WidgetDataWriter.shared.flush(
                scansUsed:  scanLimitManager.scansUsedThisMonth,
                scansLimit: ScanLimitManager.freeMonthlyLimit,
                isPro:      storeKitManager.isPro,
                recentDocs: recent.map { ($0.name, $0.dateModified) }
            )
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isPresented = false
    }
}

// MARK: - Simulator Placeholder

struct SimulatorPlaceholderView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundColor(Color("AccentGreen"))
                VStack(spacing: 8) {
                    Text("Camera not available")
                        .font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
                    Text("Test scanning on a real iPhone.\nUse Import to test the review flow.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                Button("Close") { isPresented = false }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("PrimaryGreen"))
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Color("AccentSoft")).cornerRadius(24)
            }
            .padding(32)
        }
    }
}

// MARK: - Unsupported Device View

struct UnsupportedDeviceView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color("Warn"))
                Text("Scanning not supported\non this device")
                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Document scanning requires iOS 13 or later and a compatible camera.")
                    .font(.system(size: 14)).foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Close") { isPresented = false }
                    .font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 32).padding(.vertical, 12)
                    .background(Color.white.opacity(0.15)).cornerRadius(24)
                    .padding(.top, 8)
            }
            .padding(32)
        }
    }
}

// MARK: - Previews

#Preview("Scanner – Simulator") {
    ScannerView(isPresented: .constant(true))
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}

#Preview("Simulator Placeholder") {
    SimulatorPlaceholderView(isPresented: .constant(true))
}

#Preview("Unsupported Device") {
    UnsupportedDeviceView(isPresented: .constant(true))
}
