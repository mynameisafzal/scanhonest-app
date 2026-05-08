import SwiftUI
import PDFKit
import SwiftData
import LocalAuthentication

// MARK: - DocumentDetailView

struct DocumentDetailView: View {
    let document: ScannedDocument
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKitManager: StoreKitManager

    @State private var showCustomShare  = false   // NEW — custom share sheet
    @State private var showExportSheet  = false
    @State private var showOCRPanel     = false
    @State private var showLockAlert    = false
    @State private var showPaywall      = false
    @State private var paywallTrigger: PaywallView.PaywallTrigger = .ocr
    @State private var isEditingName    = false
    @State private var editedName       = ""
    @State private var showMoreMenu     = false
    @State private var currentPageIndex = 0
    @State private var showPageCount    = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color("Background").ignoresSafeArea()

            VStack(spacing: 0) {
                if let url = document.fileURL {
                    PDFViewerRepresentable(url: url, currentPage: $currentPageIndex) {
                        flashPagePill()
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundColor(Color("TextMuted").opacity(0.4))
                        Text("Preview unavailable")
                            .font(.system(size: 16))
                            .foregroundColor(Color("TextMuted"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer()
                }
            }

            // Page count pill
            if showPageCount {
                Text("Page \(currentPageIndex + 1) / \(document.pageCount)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                    .padding(.bottom, 88)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showPageCount)
            }

            // Action bar
            DocActionBar(
                isPro:    storeKitManager.isPro,
                onShare:  { showCustomShare = true },   // opens custom sheet
                onExport: { showExportSheet = true },
                onOCR: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if storeKitManager.isPro { showOCRPanel = true }
                    else { paywallTrigger = .ocr; showPaywall = true }
                },
                onLock: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if storeKitManager.isPro { lockDocument() }
                    else { paywallTrigger = .protect; showPaywall = true }
                },
                onMore: { showMoreMenu = true }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    editedName = document.name; isEditingName = true
                } label: {
                    HStack(spacing: 4) {
                        Text(document.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color("TextPrimary"))
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 180)
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showMoreMenu = true } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Color("TextPrimary"))
                }
            }
        }
        .alert("Rename Document", isPresented: $isEditingName) {
            TextField("Document name", text: $editedName).autocorrectionDisabled(true)
            Button("Save") { applyRename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("", isPresented: $showMoreMenu, titleVisibility: .hidden) {
            Button("Rename")         { editedName = document.name; isEditingName = true }
            Button("Move to Folder") {}
            Button("Duplicate")      { duplicateDocument() }
            Divider()
            Button("Delete", role: .destructive) { deleteDocument() }
            Button("Cancel", role: .cancel) {}
        }
        // CUSTOM SHARE SHEET
        .sheet(isPresented: $showCustomShare) {
            CustomShareSheet(document: document, isPro: storeKitManager.isPro)
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportOptionsSheet(document: document)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOCRPanel) {
            OCRPanel(document: document)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Document Protected", isPresented: $showLockAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This document is now protected with Face ID / Touch ID.")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(triggerContext: paywallTrigger)
        }
        .onAppear { flashPagePill() }
    }

    private func flashPagePill() {
        withAnimation { showPageCount = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showPageCount = false }
        }
    }

    private func applyRename() {
        let s = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        document.name = s
    }

    private func duplicateDocument() {
        guard let url = document.fileURL else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).pdf")
        guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
        let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int)
                     .flatMap { Int64($0) } ?? document.fileSizeBytes
        NotificationCenter.default.post(
            name: .ddDuplicate,
            object: ScannedDocument(name: "\(document.name) copy", pageCount: document.pageCount,
                                    fileSizeBytes: sz, fileURL: dest, thumbnailData: document.thumbnailData)
        )
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
            DispatchQueue.main.async {
                if ok { document.isPasswordProtected = true; self.showLockAlert = true }
            }
        }
    }
}

extension Notification.Name {
    static let ddDuplicate = Notification.Name("ddDuplicate")
    static let ddDelete    = Notification.Name("ddDelete")
}

// MARK: - Custom Share Sheet (matches design)

struct CustomShareSheet: View {
    let document: ScannedDocument
    let isPro: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ShareFormat = .pdf

    enum ShareFormat: String, CaseIterable {
        case pdf     = "PDF"
        case jpeg    = "JPEG"
        case txt     = "TXT"
        case pdfSm   = "PDF·sm"

        var subtitle: String {
            switch self {
            case .pdf:   return "default"
            case .jpeg:  return "images"
            case .txt:   return "OCR text"
            case .pdfSm: return "compact"
            }
        }
        var requiresPro: Bool { self == .txt }
    }

    // Apps to show in send-to row
    private let sendToApps: [(label: String, icon: String, color: Color, scheme: String?)] = [
        ("AirDrop",   "wifi",              Color(red: 0.0, green: 0.48, blue: 1.0), nil),
        ("Messages",  "message.fill",      Color(red: 0.2, green: 0.78, blue: 0.35), "sms:"),
        ("Mail",      "envelope.fill",     Color(red: 0.0, green: 0.48, blue: 1.0), "mailto:"),
        ("WhatsApp",  "phone.fill",        Color(red: 0.07, green: 0.69, blue: 0.36), "whatsapp://"),
    ]

    private let sendToApps2: [(label: String, icon: String, color: Color, scheme: String?)] = [
        ("Drive",     "arrow.up.circle.fill",   Color(red: 0.26, green: 0.52, blue: 0.96), nil),
        ("Dropbox",   "shippingbox.fill",        Color(red: 0.04, green: 0.44, blue: 0.9), nil),
        ("Notes",     "note.text",               Color(red: 1.0, green: 0.84, blue: 0.0),  "mobilenotes:"),
        ("Files",     "folder.fill",             Color(red: 0.36, green: 0.36, blue: 0.36), nil),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Document header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color("Background"))
                            .frame(width: 44, height: 56)
                        if let data = document.thumbnailData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(width: 44, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "doc.text")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(Color("TextMuted"))
                        }
                        // Page count badge
                        if document.pageCount > 1 {
                            Text("\(document.pageCount)p")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(Color("PrimaryGreen"))
                                .cornerRadius(3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(2)
                        }
                    }
                    .frame(width: 44, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color("TextPrimary"))
                            .lineLimit(1)
                        Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") · \(document.formattedFileSize)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                            .frame(width: 28, height: 28)
                            .background(Color("Background"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                // Format picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("FORMAT")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color("TextMuted"))
                        .tracking(0.8)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ShareFormat.allCases, id: \.self) { fmt in
                                Button {
                                    if fmt.requiresPro && !isPro { return }
                                    selectedFormat = fmt
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(fmt.rawValue)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(
                                                selectedFormat == fmt ? .white
                                                : (fmt.requiresPro && !isPro ? Color("TextMuted").opacity(0.5)
                                                   : Color("TextPrimary"))
                                            )
                                        Text(fmt.subtitle)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(
                                                selectedFormat == fmt ? .white.opacity(0.8)
                                                : Color("TextMuted")
                                            )
                                        if fmt.requiresPro && !isPro {
                                            Text("PRO")
                                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color("Gold"))
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedFormat == fmt
                                        ? Color("PrimaryGreen")
                                        : Color("Surface")
                                    )
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedFormat == fmt ? Color.clear : Color("Hairline"),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 12)

                Divider()

                // Send To apps
                VStack(alignment: .leading, spacing: 10) {
                    Text("SEND TO")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color("TextMuted"))
                        .tracking(0.8)
                        .padding(.horizontal, 20)

                    // Row 1
                    HStack(spacing: 0) {
                        ForEach(sendToApps, id: \.label) { app in
                            ShareAppButton(
                                label: app.label,
                                icon: app.icon,
                                color: app.color
                            ) {
                                handleAppTap(app: app.label, scheme: app.scheme)
                            }
                        }
                    }
                    // Row 2
                    HStack(spacing: 0) {
                        ForEach(sendToApps2, id: \.label) { app in
                            ShareAppButton(
                                label: app.label,
                                icon: app.icon,
                                color: app.color
                            ) {
                                handleAppTap(app: app.label, scheme: app.scheme)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)

                Divider()

                // More options
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        presentNativeShareSheet()
                    }
                } label: {
                    Text("More options")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color("TextPrimary"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .background(Color("Surface").ignoresSafeArea())
        }
    }

    // MARK: - Actions

    private func handleAppTap(app: String, scheme: String?) {
        guard prepareFileURL() != nil else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch app {
            case "AirDrop":
                presentNativeShareSheet(activities: [UIActivity.ActivityType.airDrop])
            case "Messages":
                presentNativeShareSheet(activities: [UIActivity.ActivityType.message])
            case "Mail":
                presentNativeShareSheet(activities: [UIActivity.ActivityType.mail])
            case "Files":
                presentNativeShareSheet(activities: [UIActivity.ActivityType.saveToCameraRoll])
            default:
                // Try opening the app, fall back to native share
                if let scheme = scheme, let schemeURL = URL(string: scheme),
                   UIApplication.shared.canOpenURL(schemeURL) {
                    presentNativeShareSheet()
                } else {
                    presentNativeShareSheet()
                }
            }
        }
    }

    /// Prepare a properly-named temp file for sharing
    private func prepareFileURL() -> URL? {
        guard let sourceURL = document.fileURL else { return nil }

        // Create a temp copy with the proper document name
        let tempDir = FileManager.default.temporaryDirectory
        let safeName = document.name
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")

        switch selectedFormat {
        case .pdf, .pdfSm:
            let destURL = tempDir.appendingPathComponent("\(safeName).pdf")
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL

        case .jpeg:
            // Return the source PDF — share sheet handles display
            let destURL = tempDir.appendingPathComponent("\(safeName).pdf")
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL

        case .txt:
            if let text = document.ocrText, !text.isEmpty {
                let txtURL = tempDir.appendingPathComponent("\(safeName).txt")
                try? text.write(to: txtURL, atomically: true, encoding: .utf8)
                return txtURL
            }
            return sourceURL
        }
    }

    private func presentNativeShareSheet(activities: [UIActivity.ActivityType]? = nil) {
        guard let url = prepareFileURL() else { return }
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root  = scene.windows.first?.rootViewController else { return }
        var top = root; while let p = top.presentedViewController { top = p }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let activities = activities {
            av.excludedActivityTypes = UIActivity.ActivityType.allCases.filter { !activities.contains($0) }
        }
        if let pop = av.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(av, animated: true)
    }
}

// MARK: - Share App Button

struct ShareAppButton: View {
    let label:  String
    let icon:   String
    let color:  Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color("TextPrimary"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ShareAppBtnStyle())
    }
}

private struct ShareAppBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// Helper — all activity types for exclusion
extension UIActivity.ActivityType {
    static var allCases: [UIActivity.ActivityType] {
        [.postToFacebook, .postToTwitter, .postToWeibo, .message, .mail,
         .print, .copyToPasteboard, .assignToContact, .saveToCameraRoll,
         .addToReadingList, .postToFlickr, .postToVimeo, .postToTencentWeibo,
         .airDrop, .openInIBooks, .collaborationInviteWithLink,
         .collaborationCopyLink, .sharePlay, .markupAsPDF]
    }
}

// MARK: - PDF Viewer

struct PDFViewerRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    var onPageChange: (() -> Void)?

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true; v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(Color("Background"))
        if let doc = PDFDocument(url: url) { v.document = doc }
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: v)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(currentPage: $currentPage, onPageChange: onPageChange) }

    class Coordinator: NSObject {
        var currentPage: Binding<Int>; var onPageChange: (() -> Void)?
        init(currentPage: Binding<Int>, onPageChange: (() -> Void)?) {
            self.currentPage = currentPage; self.onPageChange = onPageChange
        }
        @objc func pageChanged(_ n: Notification) {
            guard let v = n.object as? PDFView, let page = v.currentPage, let doc = v.document else { return }
            DispatchQueue.main.async {
                self.currentPage.wrappedValue = doc.index(for: page)
                self.onPageChange?()
            }
        }
    }
}

// MARK: - Action Bar

struct DocActionBar: View {
    let isPro: Bool
    let onShare: () -> Void; let onExport: () -> Void
    let onOCR: () -> Void;   let onLock: () -> Void; let onMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color("Hairline")).frame(height: 0.5)
            HStack(spacing: 0) {
                DocActionBtn(icon: "square.and.arrow.up", label: "Share",  pro: false,  action: onShare)
                DocActionBtn(icon: "arrow.up.doc",        label: "Export", pro: false,  action: onExport)
                DocActionBtn(icon: "text.viewfinder",     label: "OCR",    pro: !isPro, action: onOCR)
                DocActionBtn(icon: "lock.shield",         label: "Lock",   pro: !isPro, action: onLock)
                DocActionBtn(icon: "ellipsis",            label: "More",   pro: false,  action: onMore)
            }
            .padding(.horizontal, 8).padding(.vertical, 10).padding(.bottom, 4)
        }
        .background(.ultraThinMaterial)
    }
}

struct DocActionBtn: View {
    let icon: String; let label: String; let pro: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon).font(.system(size: 22, weight: .light))
                        .foregroundColor(Color("TextPrimary")).frame(width: 28, height: 28)
                    if pro {
                        Text("PRO").font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).padding(.horizontal, 3).padding(.vertical, 1.5)
                            .background(Color("Gold")).cornerRadius(3).offset(x: 12, y: -6)
                    }
                }
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundColor(Color("TextMuted"))
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(DocActionBtnStyle())
    }
}

private struct DocActionBtnStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let document: ScannedDocument
    @State private var selected: ExportFmt = .pdf
    @Environment(\.dismiss) private var dismiss

    enum ExportFmt: String, CaseIterable {
        case pdf  = "PDF"; case jpeg = "JPEG Images"; case text = "Text (OCR)"
        var icon: String {
            switch self { case .pdf: return "doc.fill"; case .jpeg: return "photo.stack"; case .text: return "text.alignleft" }
        }
        var subtitle: String {
            switch self {
            case .pdf:  return "Original quality, all pages"
            case .jpeg: return "One image per page"
            case .text: return "Extracted text content"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(ExportFmt.allCases, id: \.self) { fmt in
                        Button { selected = fmt } label: {
                            HStack(spacing: 14) {
                                Image(systemName: fmt.icon).font(.system(size: 20, weight: .light))
                                    .foregroundColor(Color("PrimaryGreen")).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fmt.rawValue).font(.system(size: 16, weight: .medium)).foregroundColor(Color("TextPrimary"))
                                    Text(fmt.subtitle).font(.system(size: 13)).foregroundColor(Color("TextMuted"))
                                }
                                Spacer()
                                Text(sizeLabel(fmt)).font(.system(size: 12, design: .monospaced)).foregroundColor(Color("TextMuted"))
                                Image(systemName: selected == fmt ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(selected == fmt ? Color("AccentGreen") : Color("Hairline"))
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        if fmt != ExportFmt.allCases.last { Divider().padding(.leading, 62) }
                    }
                }
                .background(Color("Surface")).cornerRadius(14)
                .padding(.horizontal, 20).padding(.top, 16)
                Spacer()
                Button { exportAndShare() } label: {
                    Text("Export & Share")
                        .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color("PrimaryGreen")).cornerRadius(28)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
            .background(Color("Background").ignoresSafeArea())
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color("TextMuted"))
                }
            }
        }
    }

    private func sizeLabel(_ fmt: ExportFmt) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        switch fmt {
        case .pdf:  return f.string(fromByteCount: document.fileSizeBytes)
        case .jpeg: return f.string(fromByteCount: max(document.fileSizeBytes / 2, 1024))
        case .text: return "~\(document.pageCount * 2) KB"
        }
    }

    private func exportAndShare() {
        guard let sourceURL = document.fileURL else { dismiss(); return }
        // Create properly named temp file
        let tempDir  = FileManager.default.temporaryDirectory
        let safeName = document.name
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
        let destURL  = tempDir.appendingPathComponent("\(safeName).pdf")
        try? FileManager.default.removeItem(at: destURL)
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        let shareURL = FileManager.default.fileExists(atPath: destURL.path) ? destURL : sourceURL

        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root  = scene.windows.first?.rootViewController else { return }
            var top = root; while let p = top.presentedViewController { top = p }
            let av = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
            if let pop = av.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            top.present(av, animated: true)
        }
    }
}

// MARK: - OCR Panel

struct OCRPanel: View {
    let document: ScannedDocument
    @State private var ocrText    = ""
    @State private var searchTerm = ""
    @State private var processing = false
    @State private var copiedAll  = false
    @State private var ocrError: String?
    @Environment(\.dismiss) private var dismiss

    private var wordCount: Int { ocrText.split { !$0.isLetter }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                if processing {
                    VStack(spacing: 20) {
                        ProgressView().scaleEffect(1.4)
                        Text("Reading document…").font(.system(size: 15)).foregroundColor(Color("TextMuted"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = ocrError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48, weight: .ultraLight)).foregroundColor(Color("Warn").opacity(0.7))
                        Text(err).font(.system(size: 15)).foregroundColor(Color("TextMuted"))
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button("Try Again") { Task { await runOCR() } }
                            .buttonStyle(SHPrimaryButtonStyle(isFullWidth: false))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if ocrText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 52, weight: .ultraLight)).foregroundColor(Color("TextMuted").opacity(0.5))
                        Text("No text found in this document.").font(.system(size: 16)).foregroundColor(Color("TextMuted"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 13)).foregroundColor(Color("AccentGreen"))
                                Text("99% accurate").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(Color("AccentGreen"))
                            }
                            Spacer()
                            Text("\(wordCount) words").font(.system(size: 12, design: .monospaced)).foregroundColor(Color("TextMuted"))
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color("AccentSoft"))
                        .overlay(Rectangle().fill(Color("Hairline")).frame(height: 1), alignment: .bottom)

                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(Color("TextMuted"))
                            TextField("Search in text…", text: $searchTerm)
                                .font(.system(size: 15)).foregroundColor(Color("TextPrimary"))
                            if !searchTerm.isEmpty {
                                Button { searchTerm = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(Color("TextMuted"))
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color("Surface"))
                        .overlay(Rectangle().fill(Color("Hairline")).frame(height: 1), alignment: .bottom)

                        ScrollView(showsIndicators: false) {
                            Text(ocrText)
                                .font(.system(size: 15)).foregroundColor(Color("TextPrimary"))
                                .textSelection(.enabled).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }
                    }
                }
            }
            .navigationTitle("Extracted Text").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }.foregroundColor(Color("AccentGreen"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !ocrText.isEmpty {
                        Button {
                            UIPasteboard.general.string = ocrText
                            withAnimation { copiedAll = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copiedAll = false }
                            }
                        } label: {
                            Text(copiedAll ? "Copied!" : "Copy All")
                                .font(.system(size: 15, weight: .medium)).foregroundColor(Color("AccentGreen"))
                        }
                    }
                }
            }
            .task {
                if let cached = document.ocrText, !cached.isEmpty { ocrText = cached }
                else { await runOCR() }
            }
        }
    }

    private func runOCR() async {
        guard let url  = document.fileURL,
              let pdf  = PDFDocument(url: url),
              let page = pdf.page(at: 0)
        else { ocrError = "Could not load document for OCR."; return }
        processing = true; ocrError = nil
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let sz = CGSize(width: rect.width * scale, height: rect.height * scale)
        let img = UIGraphicsImageRenderer(size: sz).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: sz))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            ctx.cgContext.translateBy(x: 0, y: rect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        do {
            let text = try await OCRProcessor.shared.extractText(from: img)
            await MainActor.run {
                ocrText = text
                document.ocrText = text.isEmpty ? nil : text
                processing = false
                if !text.isEmpty {
                    NotificationManager.shared.sendScanCompleteNotification(documentName: document.name)
                }
            }
        } catch {
            await MainActor.run {
                ocrError  = "OCR failed: \(error.localizedDescription)"
                processing = false
            }
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        DocumentDetailView(
            document: ScannedDocument(name: "Invoice_Dec2024", pageCount: 3, fileSizeBytes: 245_000)
        )
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
    }
    .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}

