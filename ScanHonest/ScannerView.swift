import SwiftUI
import VisionKit
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

    @State private var scannedImages: [UIImage] = []
    @State private var showReview = false
    // CHANGE 3: permission denied state
    @State private var showPermissionDenied = false

    var body: some View {
        ZStack {
#if targetEnvironment(simulator)
            SimulatorPlaceholderView(isPresented: $isPresented)
#else
            if VNDocumentCameraViewController.isSupported {
                DocumentCameraView(
                    scannedImages: $scannedImages,
                    isPresented: $isPresented
                ) { images in
                    scannedImages = images
                    showReview = true
                }
                .ignoresSafeArea()
            } else {
                UnsupportedDeviceView(isPresented: $isPresented)
            }
#endif
        }
        .fullScreenCover(isPresented: $showReview) {
            ScanReviewView(
                images: scannedImages,
                isPresented: $showReview,
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
            break                           // VNDocumentCameraViewController will ask
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
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isPresented = false
    }
}

// MARK: - DocumentCameraView (UIViewControllerRepresentable)

struct DocumentCameraView: UIViewControllerRepresentable {
    @Binding var scannedImages: [UIImage]
    @Binding var isPresented: Bool
    let onScan: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            parent.onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.isPresented = false
        }
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
