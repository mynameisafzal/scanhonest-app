import SwiftUI
import PDFKit
import SwiftData
import LocalAuthentication

// MARK: - DocumentDetailView

struct DocumentDetailView: View {
    let document: ScannedDocument
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager

    @State private var showCustomShare  = false
    @State private var showNearbyShare  = false
    @State private var showOCRPanel     = false
    @State private var showLockAlert    = false
    @State private var showPaywall      = false
    @State private var paywallTrigger: PaywallView.PaywallTrigger = .ocr
    @State private var isEditingName    = false
    @State private var editedName       = ""
    @State private var showMoreMenu     = false
    @State private var currentPageIndex = 0
    @State private var showPageCount    = true
    @State private var showFolderPicker = false   // Move to Folder

    // Feedback (Toast + Snackbar)
    @State private var feedback: FeedbackItem? = nil
    // Holds the duplicated document so Snackbar "Review" can navigate to it
    @State private var pendingDuplicate: ScannedDocument? = nil
    // Holds the deleted document + URL so Snackbar "Undo" can restore it
    @State private var deletedDocumentURL: URL? = nil
    @State private var deletedDocument: ScannedDocument? = nil
    @State private var feedbackDismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            Color("Background").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Custom nav header ──────────────────────────────────
                HStack(alignment: .center, spacing: 0) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Canvas { context, size in
                                let s = min(size.width, size.height) / 24
                                var p = Path()
                                p.move(to:    CGPoint(x: 15*s, y:  5*s))
                                p.addLine(to: CGPoint(x:  8*s, y: 12*s))
                                p.addLine(to: CGPoint(x: 15*s, y: 19*s))
                                context.stroke(p, with: .color(Color("PrimaryGreen")),
                                               style: StrokeStyle(lineWidth: 2*s, lineCap: .round, lineJoin: .round))
                            }
                            .frame(width: 18, height: 18)
                            Text("Library")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color("PrimaryGreen"))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    // Title — tappable to rename directly
                    Button {
                        editedName = document.name
                        isEditingName = true
                    } label: {
                        Text(document.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color("TextPrimary"))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 180)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    Button { showMoreMenu = true } label: {
                        Canvas { context, size in
                            let s = size.width / 24
                            for cx in [5.0, 12.0, 19.0] {
                                let r = 1.6 * s
                                context.fill(
                                    Path(ellipseIn: CGRect(x: CGFloat(cx)*s - r, y: size.height/2 - r,
                                                           width: r*2, height: r*2)),
                                    with: .color(Color("TextPrimary")))
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6).padding(.horizontal, 16).frame(height: 44)

                if let url = document.fileURL {
                    PDFViewerRepresentable(url: url, currentPage: $currentPageIndex) { flashPagePill() }
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundColor(Color("TextMuted").opacity(0.4))
                        Text("Preview unavailable").font(.system(size: 16)).foregroundColor(Color("TextMuted"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                }
            }

            if showPageCount {
                Text("Page \(currentPageIndex + 1) / \(document.pageCount)")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.black.opacity(0.6)).cornerRadius(20)
                    .padding(.bottom, 88)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showPageCount)
            }

            DocActionBar(
                isPro:      storeKitManager.isPro,
                isLocked:   document.isPasswordProtected,
                hasOCRText: document.ocrText != nil,
                onShare: { showCustomShare = true },
                onOCR: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if storeKitManager.isPro {
                        showOCRPanel = true
                    } else {
                        paywallTrigger = .ocr
                        showPaywall    = true
                    }
                },
                onLock: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if storeKitManager.isPro { lockDocument() }
                    else { paywallTrigger = .protect; showPaywall = true }
                }
            )
            .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .alert("Rename Document", isPresented: $isEditingName) {
            TextField("Document name", text: $editedName).autocorrectionDisabled(true)
            Button("Save") { applyRename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("", isPresented: $showMoreMenu, titleVisibility: .hidden) {
            Button("Rename")         { editedName = document.name; isEditingName = true }
            Button(storeKitManager.isPro ? "Move to Folder" : "Move to Folder  ✦ Pro") {
                if storeKitManager.isPro {
                    showFolderPicker = true
                } else {
                    paywallTrigger = .folders
                    showPaywall    = true
                }
            }
            Button("Duplicate") { duplicateDocument() }
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(
                document: document,
                isPro: storeKitManager.isPro
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showCustomShare) {
            // FIX #4: use NativeShareSheetView (Design 10B) instead of
            // CustomShareSheet (legacy grid icons). NativeShareSheetView
            // was written but never wired into the presentation.
            NativeShareSheetView(
                document: document,
                isPro:    storeKitManager.isPro,
                onNearbyShare: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showNearbyShare = true
                    }
                }
            )
            .presentationDetents([.fraction(0.80)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showNearbyShare) {
            NearbyShareView(document: document).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOCRPanel) {
            OCRPanel(document: document)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Document Protected", isPresented: $showLockAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("This document is now protected with Face ID / Touch ID.") }
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(triggerContext: paywallTrigger) }
        .onAppear { flashPagePill() }
        .feedbackOverlay($feedback, onSnackbarAction: handleSnackbarAction)
    }

    private func flashPagePill() {
        withAnimation { showPageCount = true }
        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showPageCount = false }
        }
    }
    private func applyRename() {
        let s = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        document.name = s
    }

    // MARK: - Duplicate → Snackbar "Duplicate created · Review"
    private func duplicateDocument() {
        guard let url = document.fileURL else { return }
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).pdf")
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int)
            .flatMap { Int64($0) } ?? document.fileSizeBytes
        let dup = ScannedDocument(
            name: "\(document.name) copy",
            pageCount: document.pageCount,
            fileSizeBytes: sz,
            fileURL: dest,
            thumbnailData: document.thumbnailData
        )
        pendingDuplicate = dup
        NotificationCenter.default.post(name: .ddDuplicate, object: dup)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFeedback(.snackbar(message: "Duplicate created", action: "Review",
                               id: UUID()), autoDismiss: 3.5)
    }

    // MARK: - Delete → Snackbar "Document deleted · Undo"
    private func confirmDelete() {
        // Snapshot before deleting so Undo can restore
        deletedDocumentURL = document.fileURL
        deletedDocument    = document
        // Soft-delete: remove from SwiftData but keep file on disk temporarily
        NotificationCenter.default.post(name: .ddDelete, object: document)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        showFeedback(.snackbar(message: "Document deleted", action: "Undo",
                               id: UUID()), autoDismiss: 4.0)
        // Dismiss DocumentDetailView after a short delay so the snackbar
        // is visible before navigation changes
        Task { @MainActor [self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            dismiss()
        }
    }

    // Called when the Undo/Review button in the snackbar is tapped
    private func handleSnackbarAction() {
        if let item = feedback {
            switch item {
            case .snackbar(let msg, _, _):
                if msg == "Document deleted" {
                    undoDelete()
                } else if msg == "Duplicate created" {
                    reviewDuplicate()
                }
            default: break
            }
        }
    }

    private func undoDelete() {
        guard let doc = deletedDocument else { return }
        // Re-insert document via ddDuplicate notification so LibraryView adds it back
        NotificationCenter.default.post(name: .ddDuplicate, object: doc)
        deletedDocument    = nil
        deletedDocumentURL = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFeedback(.toast(message: "Restored", icon: "arrow.uturn.backward"), autoDismiss: 1.5)
    }

    private func reviewDuplicate() {
        // The duplicate was already posted to LibraryView via ddDuplicate.
        // Nothing else needed — user is already in the library context.
        pendingDuplicate = nil
    }

    // MARK: - Feedback helper
    private func showFeedback(_ item: FeedbackItem, autoDismiss: Double) {
        feedbackDismissTask?.cancel()
        withAnimation { feedback = item }
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismiss * 1_000_000_000))
            withAnimation { feedback = nil }
        }
    }

    private func deleteDocument() {
        if let url = document.fileURL { StorageManager.shared.deleteDocument(at: url) }
        NotificationCenter.default.post(name: .ddDelete, object: document)
        dismiss()
    }
    private func lockDocument() {
        let ctx = LAContext(); var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            document.isPasswordProtected = true; showLockAlert = true; return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                            localizedReason: "Protect \"\(document.name)\"") { ok, _ in
            guard ok else { return }
            Task { @MainActor [self] in
                document.isPasswordProtected = true
                showLockAlert = true
            }
        }
    }
}

// MARK: - Toast + Snackbar (Design 12 · Feedback)

/// Compact dark pill — no action, auto-dismisses.
/// Use for: "Copied to clipboard", "Scan saved", "Link copied"
struct DocumentToastView: View {
    let message: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(red: 0.13, green: 0.13, blue: 0.14))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        )
    }
}

/// Dark card with label + single action button.
/// Use for: "Duplicate created · Review", "Document deleted · Undo"
struct SnackbarView: View {
    let message: String
    let actionLabel: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(actionLabel, action: onAction)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(red: 0.45, green: 0.80, blue: 0.62)) // AccentGreen on dark
                .padding(.leading, 16)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.13, green: 0.13, blue: 0.14))
                .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - FeedbackOverlay
//
// Single overlay view that manages both Toast and Snackbar presentation.
// Attach to any view with .feedbackOverlay(feedback: $feedbackState).

enum FeedbackItem: Equatable {
    case toast(message: String, icon: String?)
    case snackbar(message: String, action: String, id: UUID)

    static func == (lhs: FeedbackItem, rhs: FeedbackItem) -> Bool {
        switch (lhs, rhs) {
        case (.toast(let a, _), .toast(let b, _)):       return a == b
        case (.snackbar(_, _, let a), .snackbar(_, _, let b)): return a == b
        default: return false
        }
    }
}

struct FeedbackOverlayModifier: ViewModifier {
    @Binding var item: FeedbackItem?
    var onSnackbarAction: (() -> Void)?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let item {
                feedbackView(for: item)
                    .padding(.bottom, 100) // above DocActionBar
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .opacity.animation(.easeOut(duration: 0.2))
                    ))
                    .zIndex(999)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: item)
    }

    @ViewBuilder
    private func feedbackView(for item: FeedbackItem) -> some View {
        switch item {
        case .toast(let msg, let icon):
            DocumentToastView(message: msg, icon: icon)

        case .snackbar(let msg, let action, _):
            SnackbarView(message: msg, actionLabel: action) {
                withAnimation { self.item = nil }
                onSnackbarAction?()
            }
        }
    }
}

extension View {
    func feedbackOverlay(
        _ item: Binding<FeedbackItem?>,
        onSnackbarAction: (() -> Void)? = nil
    ) -> some View {
        modifier(FeedbackOverlayModifier(item: item, onSnackbarAction: onSnackbarAction))
    }
}

extension Notification.Name {
    static let ddDuplicate = Notification.Name("ddDuplicate")
    static let ddDelete    = Notification.Name("ddDelete")
    static let scannerShouldRestartSession = Notification.Name("scannerShouldRestartSession")
}

// MARK: - OCRPanel

struct OCRPanel: View {
    let document: ScannedDocument

    @Environment(\.dismiss) private var dismiss
    @State private var recognizedText = ""
    @State private var isProcessing   = false
    @State private var errorMessage:  String?
    @State private var showCopiedToast = false   // FIX: visible copy confirmation

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    if isProcessing && recognizedText.isEmpty {
                        Spacer()
                        VStack(spacing: 14) {
                            ProgressView().scaleEffect(1.2).tint(Color("PrimaryGreen"))
                            Text("Reading document...")
                                .font(.system(size: 14)).foregroundColor(Color("TextMuted"))
                        }
                        Spacer()
                    } else if recognizedText.isEmpty && errorMessage == nil {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 48, weight: .ultraLight))
                                .foregroundColor(Color("TextMuted").opacity(0.5))
                            Text("No text found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                            Text("Tap \"Scan Text\" to extract text using OCR")
                                .font(.system(size: 13))
                                .foregroundColor(Color("TextMuted").opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        TextEditor(text: $recognizedText)
                            .font(.system(size: 15))
                            .foregroundColor(Color("TextPrimary"))
                            .scrollContentBackground(.hidden)
                            .background(Color("Background"))
                            .padding(16)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13)).foregroundColor(.red)
                            .padding(.horizontal, 20).padding(.bottom, 12)
                    }

                    // Bottom action row
                    HStack(spacing: 12) {
                        // COPY button — copies text and shows green toast
                        Button {
                            guard !recognizedText.isEmpty else { return }
                            UIPasteboard.general.string = recognizedText
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showCopiedToast = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                withAnimation { showCopiedToast = false }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Copy")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(recognizedText.isEmpty
                                ? Color("Hairline") : Color("PrimaryGreen"))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .disabled(recognizedText.isEmpty || isProcessing)
                        .buttonStyle(.plain)

                        // SCAN TEXT button — re-runs Vision OCR
                        // PURPOSE: re-run if first scan returned empty/garbled text,
                        // or after user applies a filter that improves contrast.
                        Button {
                            runOCR()
                        } label: {
                            HStack(spacing: 6) {
                                if isProcessing {
                                    ProgressView().scaleEffect(0.75).tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                Text("Scan Text")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(isProcessing ? Color("AccentGreen").opacity(0.6) : Color("AccentGreen"))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                        .disabled(isProcessing)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .padding(.top, 8)
                }
                .background(Color("Background").ignoresSafeArea())

                // “Copied!” toast — slides up from bottom, auto-dismisses after 1.5s
                if showCopiedToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("Copied!")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color("PrimaryGreen"))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .padding(.bottom, 80)  // above the button row
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal:   .opacity
                        ))
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("OCR Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Color("TextMuted"))
                }
            }
            .onAppear {
                recognizedText = document.ocrText ?? ""
                if recognizedText.isEmpty { runOCR() }
            }
        }
    }

    private func runOCR() {
        guard !isProcessing else { return }
        guard let url = document.fileURL else {
            errorMessage = "Document file is unavailable."; return
        }
        isProcessing = true; errorMessage = nil
        Task { @MainActor in
            do {
                let images = try renderImages(from: url)
                let text   = try await OCRProcessor.shared.extractText(fromPDFPages: images)
                recognizedText    = text
                document.ocrText  = text
                document.dateModified = Date()
                if text.isEmpty { errorMessage = "No text was found in this document." }
            } catch {
                errorMessage = "OCR failed: \(error.localizedDescription)"
            }
            isProcessing = false
        }
    }

    private func renderImages(from url: URL) throws -> [UIImage] {
        guard let pdfDocument = StorageManager.shared.loadPDF(from: url) else {
            throw OCRError.processingFailed
        }
        var images: [UIImage] = []
        for i in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let format = UIGraphicsImageRendererFormat.default(); format.scale = 2
            let image  = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: bounds.size))
                ctx.cgContext.translateBy(x: -bounds.minX, y: bounds.height + bounds.minY)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            images.append(image)
        }
        guard !images.isEmpty else { throw OCRError.processingFailed }
        return images
    }
}

// MARK: - CustomShareSheet
//
// ROOT CAUSE OF LIBRARY SCREEN FAILURE — now fixed:
//
// ScannedDocument is a SwiftData @Model. Its properties (fileURL, ocrText, name)
// MUST be read on the @MainActor that owns the ModelContext. The previous code did:
//
//   DispatchQueue.global(qos: .userInitiated).async {
//       let url = ShareExportService.exportForSharing(document: docCopy, format: fmt)
//   }
//
// This crossed the actor boundary — SwiftData returned nil for fileURL from a
// background thread, so exportForSharing produced nil, and nothing happened.
//
// FIX: ShareExportService.shared.prepareURLs(for:format:) is @MainActor.
// It snapshots document.fileURL, document.name, document.ocrText on the main
// actor FIRST, then dispatches file I/O to Task.detached (nonisolated, background).
// This is the correct pattern for SwiftData + async/await on iOS 17+.

// MARK: - 10B · Native Handoff Share Sheet
//
// Replaces the old 10 · Share Sheet.
// Design: format chips → Password Protect toggle → Nearby Share row →
//         primary "Share via iOS…" CTA → "opens iOS share sheet ↓" caption.
// The CTA opens UIActivityViewController (full native sheet, no exclusions).

struct CustomShareSheet: View {
    let document:      ScannedDocument
    let isPro:         Bool
    var onNearbyShare: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat      = DisplayFormat.pdf
    @State private var isPreparingShare    = false
    @State private var isPrinting          = false
    @State private var shareErrorMessage:  String?
    @State private var showErrorAlert      = false
    @State private var showProPaywall      = false     // paywall for TXT / password features
    @State private var showNearbyDeniedAlert = false

    // Security section
    @State private var securityExpanded = true         // open by default
    @State private var addPDFPassword   = false        // "Add PDF password protection" toggle
    @State private var passwordInput    = ""           // password field content

    // Pre-warm: serialise the file as soon as the sheet opens (or format changes).
    // Tap-to-share resolves an already-finished Task → O(1) latency, no spinner.
    @State private var prewarmTask:   Task<[URL], Error>?
    @State private var prewarmFormat: ShareExportFormat?

    // ── Format (UI label ↔ service format) ───────────────────────────────

    enum DisplayFormat: String, CaseIterable {
        case pdf   = "PDF"
        case jpeg  = "JPEG"
        case txt   = "TXT"
        case pdfSm = "PDF\u{00B7}sm"

        var subtitle: String {
            switch self {
            case .pdf:   return "default"
            case .jpeg:  return "images"
            case .txt:   return "OCR text"
            case .pdfSm: return "compact"
            }
        }
        var requiresPro: Bool { self == .txt }
        var serviceFormat: ShareExportFormat {
            switch self {
            case .pdf:   return .pdf
            case .jpeg:  return .jpeg
            case .txt:   return .text
            case .pdfSm: return .pdfCompact
            }
        }
    }

    // ── Body ──────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            docHeader
            Divider()
            formatPicker.padding(.vertical, 12)
            Divider()
            securitySection
            Divider()
            nearbyRow
            Divider()
            printRow
            Divider()

            Spacer(minLength: 0)

            // Primary CTA — pinned flush to the bottom of the sheet
            Button { handleShare() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Share")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color("PrimaryGreen"))
                .cornerRadius(25)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .background(Color("Surface").ignoresSafeArea())
        .onAppear  { startPrewarm() }
        .onChange(of: selectedFormat) { _, _ in startPrewarm() }
        .fullScreenCover(isPresented: $showProPaywall) {
            PaywallView(triggerContext: .protect)
        }
        .alert("Sharing Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "An error occurred. Please try again.")
        }
        .alert("Local Network Access Required", isPresented: $showNearbyDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nearby Share needs local network access to find other ScanHonest users. Please enable it in Settings \u{2192} ScanHonest \u{2192} Local Network.")
        }
        .overlay {
            if isPreparingShare || isPrinting {
                ZStack {
                    Color.black.opacity(0.16).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.3).tint(Color("PrimaryGreen"))
                        Text(isPreparingShare ? "Preparing file\u{2026}" : "Preparing print\u{2026}")
                            .font(.system(size: 14)).foregroundColor(Color("TextMuted"))
                    }
                    .padding(28).background(Color("Surface")).cornerRadius(18)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
    }

    // ── Sub-views ─────────────────────────────────────────────────────────

    private var docHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color("Background")).frame(width: 44, height: 56)
                if let data = document.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 44, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc.text").font(.system(size: 20, weight: .light)).foregroundColor(Color("TextMuted"))
                }
                if document.pageCount > 1 {
                    Text("\(document.pageCount)p")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color("PrimaryGreen")).cornerRadius(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(2)
                }
            }
            .frame(width: 44, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.name).font(.system(size: 15, weight: .semibold)).foregroundColor(Color("TextPrimary")).lineLimit(1)
                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") \u{00B7} \(document.formattedFileSize)")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(Color("TextMuted"))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextMuted"))
                    .frame(width: 28, height: 28).background(Color("Background")).clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)
    }

    private var formatPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted")).tracking(0.8).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DisplayFormat.allCases, id: \.self) { fmt in
                        Button {
                            if fmt.requiresPro && !isPro {
                                // TXT OCR is Pro-only — open paywall directly
                                showProPaywall = true
                                return
                            }
                            selectedFormat = fmt
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 2) {
                                Text(fmt.rawValue).font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedFormat == fmt ? .white
                                                     : (fmt.requiresPro && !isPro ? Color("TextMuted").opacity(0.5) : Color("TextPrimary")))
                                Text(fmt.subtitle).font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(selectedFormat == fmt ? .white.opacity(0.8) : Color("TextMuted"))
                                if fmt.requiresPro && !isPro {
                                    Text("PRO").font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white).padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Color("Gold")).cornerRadius(3)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(selectedFormat == fmt ? Color("PrimaryGreen") : Color("Surface"))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedFormat == fmt ? Color.clear : Color("Hairline"), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }
        }
    }

    // Security section — collapsible card with password field + PDF-protection toggle.
    // Chevron (▾/▸) on the right collapses and expands the card.
    // By default: expanded. Toggle default: OFF.
    // Turning the toggle ON → paywall for free users; for Pro → enables password export.
    private var securitySection: some View {
        VStack(spacing: 0) {
            // Header — tapping anywhere on the row expands / collapses
            HStack(spacing: 14) {
                SHIconBadge(systemName: "lock.fill", size: 44, iconSize: 18, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Password Protect")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                        if !isPro {
                            Text("PRO")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color("Gold")).cornerRadius(3)
                        }
                    }
                    Text("AES-256 encryption")
                        .font(.system(size: 12)).foregroundColor(Color("TextMuted"))
                }
                Spacer()
                Image(systemName: securityExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(Color("Hairline"))
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { securityExpanded.toggle() } }

            if securityExpanded {
                // Password input field
                Divider().padding(.leading, 68)
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextMuted")).frame(width: 20)
                    SecureField("Enter password\u{2026}", text: $passwordInput)
                        .font(.system(size: 14)).foregroundColor(Color("TextPrimary"))
                        .autocorrectionDisabled(true).textInputAutocapitalization(.never)
                    if !passwordInput.isEmpty {
                        Button { passwordInput = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color("TextMuted"))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color("Background").opacity(0.5))

                // "Add PDF password protection" toggle
                Divider().padding(.leading, 68)
                Toggle(isOn: Binding(
                    get: { addPDFPassword },
                    set: { newVal in
                        guard newVal else { addPDFPassword = false; passwordInput = ""; return }
                        if isPro { addPDFPassword = true }
                        else     { showProPaywall = true }
                    }
                )) {
                    Text("Add PDF password protection")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextPrimary"))
                }
                .tint(Color("PrimaryGreen"))
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
    }

    private var nearbyRow: some View {
        Button {
            NearbyPermissionManager.shared.requestAndProceed(
                onGranted: {
                    NearbyShareManager.shared.startAdvertising()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onNearbyShare() }
                },
                onDenied: { showNearbyDeniedAlert = true }
            )
        } label: {
            HStack(spacing: 14) {
                SHIconBadge(systemName: "antenna.radiowaves.left.and.right", size: 44, iconSize: 20, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby Share").font(.system(size: 15, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                    Text("Share securely with nearby ScanHonest users").font(.system(size: 12)).foregroundColor(Color("TextMuted"))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundColor(Color("Hairline"))
            }
            .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // Print row — triggers UIPrintInteractionController via ShareExportService.
    private var printRow: some View {
        Button { handlePrint() } label: {
            HStack(spacing: 14) {
                SHIconBadge(systemName: "printer.fill", size: 44, iconSize: 18, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Print").font(.system(size: 15, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                    Text("Send to AirPrint printer").font(.system(size: 12)).foregroundColor(Color("TextMuted"))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundColor(Color("Hairline"))
            }
            .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPrinting)
    }

    // ── Pre-warm ──────────────────────────────────────────────────────────

    private func startPrewarm() {
        // Don't pre-warm TXT — it requires OCR text to be present and is rare.
        let format = selectedFormat.serviceFormat
        guard format != .text, format != prewarmFormat else { return }
        prewarmTask?.cancel()
        prewarmFormat = format
        prewarmTask = Task {
            try await ShareExportService.shared.prepareURLs(for: document, format: format)
        }
    }

    // ── Share action — opens UIActivityViewController (full native sheet) ──

    private func handleShare() {
        guard !isPreparingShare else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let format      = selectedFormat.serviceFormat
        let usePassword = addPDFPassword && isPro && !passwordInput.isEmpty
        let password    = passwordInput
        isPreparingShare  = true
        shareErrorMessage = nil

        Task { @MainActor in
            do {
                let urls: [URL]
                if usePassword && (format == .pdf || format == .pdfCompact) {
                    urls = try await ShareExportService.shared.prepareURLsWithPassword(
                        for: document, format: format, password: password
                    )
                } else if let task = prewarmTask, prewarmFormat == format {
                    urls = try await task.value
                } else {
                    urls = try await ShareExportService.shared.prepareURLs(for: document, format: format)
                }

                isPreparingShare = false
                let docName       = document.name
                let thumbData     = document.thumbnailData
                let dismissAction = dismiss

                // Dismiss the custom sheet first, then wait for the animation to
                // complete before presenting UIActivityViewController.
                // topmostVC() now skips mid-dismiss VCs, so the extra 50 ms is
                // just a safety margin for slower devices.
                dismissAction()
                try? await Task.sleep(nanoseconds: 430_000_000)   // ~430 ms

                ShareExportService.shared.presentRich(
                    urls: urls, target: .moreOptions,
                    docName: docName, thumbnailData: thumbData
                ) { urls in
                    ShareExportService.shared.cleanupURLs(urls)
                }
            } catch let e as ShareExportError {
                isPreparingShare  = false
                shareErrorMessage = e.localizedDescription
                showErrorAlert    = true
            } catch {
                if !Task.isCancelled {
                    isPreparingShare  = false
                    shareErrorMessage = "Export failed: \(error.localizedDescription)"
                    showErrorAlert    = true
                }
            }
        }
    }

    // ── Print action — UIPrintInteractionController ───────────────────────

    private func handlePrint() {
        guard !isPrinting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isPrinting = true

        Task { @MainActor in
            do {
                // Always print the PDF (compact or plain depending on current selection).
                let format = (selectedFormat == .pdfSm) ? ShareExportFormat.pdfCompact : .pdf
                let urls   = try await ShareExportService.shared.prepareURLs(for: document, format: format)
                guard let url = urls.first else { isPrinting = false; return }
                ShareExportService.shared.printDocument(url: url, jobName: document.name) {
                    ShareExportService.shared.cleanupURLs(urls)
                    Task { @MainActor in isPrinting = false }
                }
            } catch {
                isPrinting = false
            }
        }
    }
}

// MARK: - PDF Viewer

private struct UncheckedSendableObject: @unchecked Sendable {
    let value: Any?
    init(_ value: Any?) { self.value = value }
}

struct PDFViewerRepresentable: UIViewRepresentable {
    let url: URL; @Binding var currentPage: Int; var onPageChange: (() -> Void)?
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true; v.displayMode = .singlePageContinuous; v.displayDirection = .vertical
        v.backgroundColor = UIColor(Color("Background"))
        // Use StorageManager so AES-256-GCM encrypted files are decrypted first.
        // PDFDocument(url:) reads the raw bytes and returns nil for encrypted files.
        if let doc = StorageManager.shared.loadPDF(from: url) { v.document = doc }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged, object: v)
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage, onPageChange: onPageChange) }
    final class Coordinator: NSObject, @unchecked Sendable {
        var currentPage: Binding<Int>; var onPageChange: (() -> Void)?
        init(currentPage: Binding<Int>, onPageChange: (() -> Void)?) {
            self.currentPage = currentPage; self.onPageChange = onPageChange
        }
        @objc func pageChanged(_ n: Notification) {
            let boxed = UncheckedSendableObject(n.object)
            Task { @MainActor in
                guard let v = boxed.value as? PDFView, let page = v.currentPage, let doc = v.document else { return }
                let idx = doc.index(for: page)
                self.currentPage.wrappedValue = idx
                self.onPageChange?()
            }
        }
    }
}

// MARK: - DocActionBar
//
// Changes from audit:
//   1. Export removed — Share already includes PDF/JPEG/Compress/TXT
//   2. Lock shows locked/unlocked state visually
//   3. OCR shows green dot when text is already extracted
//   4. PRO badge uses .overlay instead of .offset to prevent clipping
//   5. Bottom padding uses safeAreaInsets via GeometryReader

struct DocActionBar: View {
    let isPro:        Bool
    let isLocked:     Bool      // shows filled green lock when true
    let hasOCRText:   Bool      // shows green dot on OCR button when true
    let onShare:  () -> Void
    let onOCR:    () -> Void
    let onLock:   () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Share — primary action, always enabled
            DocActionBtn(
                icon: .share,
                label: "Share",
                pro: false,
                isActive: false,
                badge: nil,
                action: onShare
            )
            .accessibilityIdentifier("shareButton")

            // OCR — Pro gated, green dot if text already extracted
            DocActionBtn(
                icon: .text,
                label: "OCR",
                pro: !isPro,
                isActive: false,
                badge: hasOCRText ? .dot : nil,
                action: onOCR
            )
            .accessibilityIdentifier("ocrButton")

            // Lock — shows active state when document is locked
            DocActionBtn(
                icon: .lock,
                label: isLocked ? "Locked" : "Lock",
                pro: !isPro,
                isActive: isLocked,
                badge: nil,
                action: onLock
            )
            .accessibilityIdentifier("lockButton")
        }
        .padding(.horizontal, 8).padding(.vertical, 14)
        .background(Color("Surface")).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color("Hairline"), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .padding(.horizontal, 16)
    }
}

private enum DocBadge { case dot }
private enum DetailActionIcon { case share, pdf, text, lock }

private struct DocActionBtn: View {
    let icon:     DetailActionIcon
    let label:    String
    let pro:      Bool
    let isActive: Bool          // filled/green when true (used for Lock)
    let badge:    DocBadge?     // green dot for OCR extracted state
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    DetailActionGlyph(
                        icon: icon,
                        color: isActive ? Color("AccentGreen") : Color("PrimaryGreen")
                    )
                    .frame(width: 26, height: 26)

                    // PRO badge — uses overlay alignment, no offset clipping
                    if pro {
                        Text("PRO")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).tracking(0.3)
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .background(Color("Gold"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .offset(x: 14, y: -6)
                    }

                    // Green dot — OCR text available
                    if badge == .dot {
                        Circle()
                            .fill(Color("AccentGreen"))
                            .frame(width: 7, height: 7)
                            .offset(x: 10, y: -4)
                    }
                }
                .frame(width: 32, height: 32)

                Text(label)
                    .font(.system(size: 10.5, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? Color("AccentGreen") : Color("TextMuted"))
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(DocActionBtnStyle())
    }
}

private struct DetailActionGlyph: View {
    let icon: DetailActionIcon; let color: Color
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*s, y: y*s) }
            switch icon {
            case .share:
                var p = Path()
                p.move(to: pt(12,3)); p.addLine(to: pt(12,16)); p.move(to: pt(12,3)); p.addLine(to: pt(8,7))
                p.move(to: pt(12,3)); p.addLine(to: pt(16,7)); p.move(to: pt(5,13)); p.addLine(to: pt(5,19))
                p.addQuadCurve(to: pt(7,21), control: pt(5,21)); p.addLine(to: pt(17,21))
                p.addQuadCurve(to: pt(19,19), control: pt(19,21)); p.addLine(to: pt(19,13))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.8*s, lineCap: .round, lineJoin: .round))
            case .pdf:
                var d = Path()
                d.move(to: pt(7,3)); d.addLine(to: pt(14,3)); d.addLine(to: pt(19,8)); d.addLine(to: pt(19,21)); d.addLine(to: pt(7,21)); d.closeSubpath()
                d.move(to: pt(14,3)); d.addLine(to: pt(14,8)); d.addLine(to: pt(19,8))
                context.stroke(d, with: .color(color), style: StrokeStyle(lineWidth: 1.6*s, lineJoin: .round))
                context.draw(Text("PDF").font(.system(size: 5*s, weight: .bold)).foregroundColor(color), at: pt(12,16), anchor: .center)
            case .text:
                var p = Path()
                p.move(to: pt(5,6)); p.addLine(to: pt(19,6)); p.move(to: pt(12,6)); p.addLine(to: pt(12,20))
                p.move(to: pt(9,20)); p.addLine(to: pt(15,20))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.8*s, lineCap: .round))
            case .lock:
                context.stroke(Path(roundedRect: CGRect(x: 5*s, y: 11*s, width: 14*s, height: 9*s), cornerRadius: 2*s), with: .color(color), lineWidth: 1.6*s)
                var sh = Path()
                sh.move(to: pt(8,11)); sh.addLine(to: pt(8,8)); sh.addCurve(to: pt(16,8), control1: pt(8,2.7), control2: pt(16,2.7)); sh.addLine(to: pt(16,11))
                context.stroke(sh, with: .color(color), lineWidth: 1.6*s)
            }
        }
        .frame(width: 22, height: 22)
    }
}

private struct DocActionBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - ExportOptionsSheet

struct ExportOptionsSheet: View {
    let document: ScannedDocument
    @State private var selected    = ExportFmt.pdf
    @State private var isExporting = false
    @State private var showError   = false
    @State private var errorMsg    = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager

    enum ExportFmt: String, CaseIterable {
        case pdf  = "PDF"; case jpeg = "JPEG Images"
        var icon: String { switch self { case .pdf: return "doc.fill"; case .jpeg: return "photo.stack" } }
        var subtitle: String { switch self { case .pdf: return "Original quality, all pages"; case .jpeg: return "One image per page" } }
        var serviceFormat: ShareExportFormat { switch self { case .pdf: return .pdf; case .jpeg: return .jpeg } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(ExportFmt.allCases, id: \.self) { fmt in
                        Button { selected = fmt } label: {
                            HStack(spacing: 14) {
                                Image(systemName: fmt.icon).font(.system(size: 20, weight: .light)).foregroundColor(Color("PrimaryGreen")).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fmt.rawValue).font(.system(size: 16, weight: .medium)).foregroundColor(Color("TextPrimary"))
                                    Text(fmt.subtitle).font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                                }
                                Spacer()
                                Text(sizeLabel(fmt)).font(.system(size: 12, design: .monospaced)).foregroundColor(Color("TextMuted"))
                                Image(systemName: selected == fmt ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                                    .foregroundColor(selected == fmt ? Color("AccentGreen") : Color("Hairline"))
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }.buttonStyle(.plain)
                        if fmt != ExportFmt.allCases.last { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color("Surface")).cornerRadius(14).padding(.horizontal, 20).padding(.top, 16)
                Spacer()
                Button { exportAndPresent() } label: {
                    Group {
                        if isExporting { ProgressView().tint(.white) }
                        else { Text("Export").font(.system(size: 17, weight: .semibold)).foregroundColor(.white) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16).background(Color("PrimaryGreen")).cornerRadius(28)
                }
                .padding(.horizontal, 20).disabled(isExporting)
            }
            .background(Color("Background").ignoresSafeArea())
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { dismiss() }.foregroundColor(Color("TextMuted")) } }
        }
        .alert("Export Failed", isPresented: $showError) { Button("OK", role: .cancel) {} } message: { Text(errorMsg) }
    }

    private func sizeLabel(_ fmt: ExportFmt) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        switch fmt {
        case .pdf:  return f.string(fromByteCount: document.fileSizeBytes)
        case .jpeg: return f.string(fromByteCount: max(document.fileSizeBytes / 2, 1024))
        }
    }

    // Uses the same @MainActor-safe pipeline as CustomShareSheet.
    // IMPORTANT: capture `dismiss` before entering the async Task so the closure
    // can call it from the UIActivityViewController completion handler without
    // referencing self (which could be gone by then).
    // We present UIActivityViewController ON TOP of this sheet — the same fix
    // applied to CustomShareSheet — so topmostVC() finds us as the presenter
    // rather than finding a VC that is already animating away.
    private func exportAndPresent() {
        isExporting = true
        let dismissAction = dismiss          // capture before leaving MainActor context
        let docName       = document.name
        let thumbData     = document.thumbnailData
        Task { @MainActor in
            do {
                let urls = try await ShareExportService.shared.prepareURLs(for: document, format: selected.serviceFormat)
                isExporting = false
                // Present the native share sheet ON TOP — don't dismiss first.
                // Dismissing before presenting causes topmostVC() to find the
                // animating-away sheet and the presentation silently fails.
                ShareExportService.shared.presentRich(
                    urls: urls, target: .moreOptions,
                    docName: docName, thumbnailData: thumbData
                ) { urls in
                    ShareExportService.shared.cleanupURLs(urls)
                    Task { @MainActor in dismissAction() }   // dismiss after share sheet closes
                }
            } catch let e as ShareExportError {
                isExporting = false; errorMsg = e.localizedDescription; showError = true
            } catch {
                isExporting = false; errorMsg = "Export failed: \(error.localizedDescription)"; showError = true
            }
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        DocumentDetailView(document: ScannedDocument(name: "Invoice_Dec2024", pageCount: 3, fileSizeBytes: 245_000))
            .environmentObject(StoreKitManager()).environmentObject(ScanLimitManager())
    }
    .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}
