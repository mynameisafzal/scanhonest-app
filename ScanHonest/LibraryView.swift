import SwiftUI
import SwiftData
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: - LibraryView

struct LibraryView: View {
    @Binding var showScanner: Bool
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScannedDocument.dateModified, order: .reverse) private var documents: [ScannedDocument]
    @EnvironmentObject var scanLimitManager: ScanLimitManager
    @EnvironmentObject var storeKitManager: StoreKitManager

    @State private var showPaywall        = false
    @State private var paywallTrigger: PaywallView.PaywallTrigger = .scanLimit
    // FIX: search state wired to a visible text field
    @State private var searchText         = ""
    @State private var isSearching        = false
    @State private var selectedDocument: ScannedDocument?
    // MED-05 FIX: Rename and Move to Folder were empty closures.
    // Rename now presents a focused alert; Move to Folder shows a placeholder
    // confirmationDialog until the folders feature is fully built.
    @State private var renamingDocument: ScannedDocument?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var movingDocument: ScannedDocument?
    @State private var showMoveSheet = false
    @State private var documentToDelete: ScannedDocument?
    @State private var layout: LibraryLayout = .grid
    @State private var showSettings       = false
    // Import flow — custom popup replaces confirmationDialog
    @State private var showImportOptions  = false
    @State private var showImagePicker    = false
    @State private var showDocumentPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    // Wraps UIImage so fullScreenCover(item:) only fires after the image is set.
    // Using isPresented + optional body can race: the cover opens before the
    // image is assigned, resulting in a blank review screen.
    @State private var importedImageItem: ImportedImageItem?
    // Delete flow — custom popup replaces confirmationDialog
    @State private var showDeletePopup = false

    /// Stable identity wrapper for an imported UIImage.
    struct ImportedImageItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    enum LibraryLayout { case grid, list }

    var filteredDocuments: [ScannedDocument] {
        searchText.isEmpty ? documents : documents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color("Background").ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {

                    // ── Top bar ──
                    HStack(spacing: 10) {
                        // Wordmark (hidden when searching)
                        if !isSearching {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color("PrimaryGreen"))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                Text("ScanHonest")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color("TextPrimary"))
                            }
                            Spacer()
                        }

                        // Search field — shown when searching
                        if isSearching {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color("TextMuted"))
                                TextField("Search documents…", text: $searchText)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color("TextPrimary"))
                                    .autocorrectionDisabled(true)
                                    .submitLabel(.search)
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Color("TextMuted"))
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color("Surface"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("Hairline"), lineWidth: 1))
                        }

                        // Icons
                        HStack(spacing: 12) {
                            // Search toggle
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isSearching.toggle()
                                    if !isSearching { searchText = "" }
                                }
                            } label: {
                                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(Color("TextPrimary"))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("searchButton")

                            if !isSearching {
                                // Grid/List toggle
                                Button {
                                    withAnimation { layout = layout == .grid ? .list : .grid }
                                } label: {
                                    Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(Color("TextPrimary"))
                                }
                                .buttonStyle(.plain)

                                // Settings — custom gear icon matching screens.jsx Icon.gear
                                // SVG: circle r=3 at centre + 8 spokes at cardinal & diagonal
                                Button { showSettings = true } label: {
                                    Canvas { context, size in
                                        let s  = size.width / 24
                                        let lw = 1.6 * s
                                        let c  = GraphicsContext.Shading.color(Color("TextPrimary"))
                                        let style = StrokeStyle(lineWidth: lw, lineCap: .round)
                                        // Centre circle (r = 3)
                                        context.stroke(
                                            Path(ellipseIn: CGRect(x: 9*s, y: 9*s, width: 6*s, height: 6*s)),
                                            with: c, lineWidth: lw)
                                        // 8 spokes
                                        var p = Path()
                                        let spokes: [(CGPoint, CGPoint)] = [
                                            (CGPoint(x: 12*s, y: 2*s),  CGPoint(x: 12*s, y: 5*s)),
                                            (CGPoint(x: 12*s, y: 19*s), CGPoint(x: 12*s, y: 22*s)),
                                            (CGPoint(x: 2*s,  y: 12*s), CGPoint(x: 5*s,  y: 12*s)),
                                            (CGPoint(x: 19*s, y: 12*s), CGPoint(x: 22*s, y: 12*s)),
                                            (CGPoint(x: 5*s,  y: 5*s),  CGPoint(x: 7*s,  y: 7*s)),
                                            (CGPoint(x: 17*s, y: 17*s), CGPoint(x: 19*s, y: 19*s)),
                                            (CGPoint(x: 5*s,  y: 19*s), CGPoint(x: 7*s,  y: 17*s)),
                                            (CGPoint(x: 17*s, y: 7*s),  CGPoint(x: 19*s, y: 5*s)),
                                        ]
                                        for (a, b) in spokes { p.move(to: a); p.addLine(to: b) }
                                        context.stroke(p, with: c, style: style)
                                    }
                                    .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settingsButton")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .animation(.spring(response: 0.3), value: isSearching)

                    // ── Scan counter ──
                    if !isSearching {
                        ScanCounterView(
                            state: scanLimitManager.counterState(isPro: storeKitManager.isPro),
                            resetDate: scanLimitManager.nextResetFormatted,
                            onUpgradeTap: storeKitManager.isPro ? nil : {
                                paywallTrigger = .scanLimit
                                showPaywall    = true
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .accessibilityIdentifier("scanCounterBanner")

                        // ── Quick actions ──
                        HStack(spacing: 10) {
                            Button(action: handleScanTap) {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Scan Document")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color("PrimaryGreen"))
                                .cornerRadius(28)
                            }
                            .buttonStyle(LibraryScaleStyle())
                            .accessibilityIdentifier("scanDocumentButton")

                            Button { showImportOptions = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Import")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundColor(Color("PrimaryGreen"))
                                .frame(height: 44).padding(.horizontal, 16)
                                .background(Color("PrimaryGreen").opacity(0.08))
                                .cornerRadius(28)
                            }
                            .buttonStyle(LibraryScaleStyle())
                            .accessibilityIdentifier("importButton")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    // ── Section header ──
                    HStack {
                        Text(isSearching && !searchText.isEmpty
                             ? "\(filteredDocuments.count) result\(filteredDocuments.count == 1 ? "" : "s")"
                             : "RECENT")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color("TextMuted"))
                            .tracking(0.6)
                        Spacer()
                        if !isSearching {
                            // "All Folders" — Pro gate: free users see paywall
                            Button {
                                if storeKitManager.isPro {
                                    // TODO: navigate to FolderListView when built
                                } else {
                                    paywallTrigger = .folders
                                    showPaywall    = true
                                }
                            } label: {
                                Text(storeKitManager.isPro ? "All folders →" : "Folders  ✦ Pro")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, isSearching ? 16 : 20)
                    .padding(.bottom, 10)

                    // ── Document grid / list ──
                    if filteredDocuments.isEmpty {
                        if isSearching && !searchText.isEmpty {
                            // No search results
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40, weight: .ultraLight))
                                    .foregroundColor(Color("TextMuted").opacity(0.4))
                                Text("No results for \"\(searchText)\"")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color("TextMuted"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            LibraryEmptyState(onScan: handleScanTap)
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            if layout == .grid {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)
                                    ],
                                    spacing: 14
                                ) {
                                    ForEach(filteredDocuments) { doc in
                                        DocumentGridCell(document: doc)
                                            .onTapGesture { selectedDocument = doc }
                                            .contextMenu { documentContextMenu(for: doc) }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 140)
                                .accessibilityIdentifier("documentGrid")
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredDocuments) { doc in
                                        DocumentListRow(document: doc)
                                            .onTapGesture { selectedDocument = doc }
                                            .contextMenu { documentContextMenu(for: doc) }
                                    }
                                }
                                .padding(.horizontal, 16).padding(.bottom, 140)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedDocument) { DocumentDetailView(document: $0) }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showPaywall) { PaywallView(triggerContext: paywallTrigger) }
            // Custom import choice popup (11B-A) — replaces system confirmationDialog
            // Presented as a ZStack overlay so it renders above the NavigationStack.
            .overlay {
                if showImportOptions {
                    ImportChoicePopup(
                        onCameraRoll: { showImportOptions = false; showImagePicker    = true },
                        onFiles:      { showImportOptions = false; showDocumentPicker = true },
                        onCancel:     { showImportOptions = false }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showImportOptions)
                    .zIndex(100)
                }
            }
            // Custom delete confirmation popup (11C) — replaces system confirmationDialog
            .overlay {
                if showDeletePopup, let doc = documentToDelete {
                    DeleteDocumentPopup(
                        documentName: doc.name,
                        onDelete: {
                            showDeletePopup  = false
                            documentToDelete = nil
                            deleteDocument(doc)
                        },
                        onCancel: {
                            showDeletePopup  = false
                            documentToDelete = nil
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: showDeletePopup)
                    .zIndex(100)
                }
            }
            .photosPicker(isPresented: $showImagePicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data  = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            photoPickerItem  = nil
                            // Assign the item wrapper so fullScreenCover(item:) fires
                            // only after the image is guaranteed non-nil.
                            importedImageItem = ImportedImageItem(image: image)
                        }
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in handlePickedDocument(url: url) }
            }
            // item:-based cover — closure runs only when importedImageItem != nil
            .fullScreenCover(item: $importedImageItem) { item in
                ScanReviewView(
                    images: [item.image],
                    isPresented: Binding(
                        get: { importedImageItem != nil },
                        set: { if !$0 { importedImageItem = nil } }
                    ),
                    onSave: { saveDocument($0) }
                )
                .environmentObject(storeKitManager)
                .environmentObject(scanLimitManager)
            }
            // MED-05: Rename alert
            .alert("Rename Document", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                    .autocorrectionDisabled(true)
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { renamingDocument?.name = trimmed }
                    renamingDocument = nil
                }
                Button("Cancel", role: .cancel) { renamingDocument = nil }
            }
            // MED-05: Move to Folder sheet (placeholder until folder picker is built)
            .confirmationDialog(
                "Move to Folder",
                isPresented: $showMoveSheet,
                titleVisibility: .visible
            ) {
                Button("All Documents") {
                    // Default folder — no-op until folder model is built
                    movingDocument = nil
                }
                Button("Cancel", role: .cancel) { movingDocument = nil }
            } message: {
                Text("Folder organisation is coming soon. Your document is saved in All Documents.")
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func documentContextMenu(for document: ScannedDocument) -> some View {
        // MED-05 FIX: Rename now opens a real alert with a pre-filled text field.
        Button {
            renameText       = document.name
            renamingDocument = document
            showRenameAlert  = true
        } label: { Label("Rename", systemImage: "pencil") }

        // Move to Folder — Pro gate.
        // Free users see the paywall; Pro users see the folder picker.
        Button {
            if storeKitManager.isPro {
                movingDocument = document
                showMoveSheet  = true
            } else {
                paywallTrigger = .folders
                showPaywall    = true
            }
        } label: {
            storeKitManager.isPro
                ? Label("Move to Folder", systemImage: "folder")
                : Label("Move to Folder  ✦ Pro", systemImage: "folder")
        }

        Button {
            Task { @MainActor in
                // FIX #2: pass through ShareExportService so the encrypted
                // PDF is decrypted before UIActivityViewController receives it.
                // The old code passed document.fileURL directly — sending raw
                // AES-256-GCM ciphertext to the recipient.
                do {
                    let urls = try await ShareExportService.shared.prepareURLs(
                        for: document, format: .pdf
                    )
                    ShareExportService.shared.presentRich(
                        urls: urls, target: .moreOptions,
                        docName: document.name,
                        thumbnailData: document.thumbnailData
                    ) { ShareExportService.shared.cleanupURLs($0) }
                } catch {
                    // Silent fallback — share action simply does nothing on error
                }
            }
        } label: { Label("Share", systemImage: "square.and.arrow.up") }

        Divider()
        Button(role: .destructive) {
            documentToDelete = document
            showDeletePopup  = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Actions

    private func handleScanTap() {
        if storeKitManager.isPro || !scanLimitManager.hasReachedLimit {
            showScanner = true
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            paywallTrigger = .scanLimit; showPaywall = true
        }
    }

    private func handlePickedDocument(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { importPDF(from: url) }
        else if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                importedImageItem = ImportedImageItem(image: image)
            }
        }
    }

    private func importPDF(from sourceURL: URL) {
        // FIX #5: imported PDFs must be encrypted at rest just like scanned ones.
        // Old code used FileManager.copyItem — writing plaintext to disk.
        // Now we read the PDF data, pass it through StorageManager.savePDF
        // which applies AES-256-GCM encryption before writing.
        guard let pdfDoc = PDFDocument(url: sourceURL) else { return }

        var thumbData: Data?
        if let page = pdfDoc.page(at: 0) {
            let rect = page.bounds(for: .mediaBox); let scale: CGFloat = 1.5
            let size = CGSize(width: rect.width * scale, height: rect.height * scale)
            let thumb = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.scaleBy(x: scale, y: scale)
                ctx.cgContext.translateBy(x: 0, y: rect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            thumbData = thumb.jpegData(compressionQuality: 0.7)
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let docName  = baseName.isEmpty ? "Imported PDF" : baseName

        // savePDF encrypts with AES-256-GCM and returns the secure URL + size
        guard let result = StorageManager.shared.savePDF(
            pdfDoc, name: docName,
            thumbnail: thumbData.flatMap { UIImage(data: $0) }
        ) else { return }

        saveDocument(ScannedDocument(
            name: docName,
            pageCount: pdfDoc.pageCount,
            fileSizeBytes: result.size,
            fileURL: result.url,
            thumbnailData: thumbData
        ), countAsScan: false)
    }

    func saveDocument(_ document: ScannedDocument, countAsScan: Bool = true) {
        modelContext.insert(document)
        // FIX #10: only charge scan quota for actual camera scans.
        // Importing an existing PDF/image from Files or Photos should NOT
        // consume one of the user's 5 free monthly scans.
        if countAsScan && !storeKitManager.isPro { scanLimitManager.recordScan() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func deleteDocument(_ document: ScannedDocument) {
        if let url = document.fileURL { StorageManager.shared.deleteDocument(at: url) }
        modelContext.delete(document)
    }
}

// MARK: - DocumentPicker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .jpeg, .png])
        p.delegate = context.coordinator; p.allowsMultipleSelection = false; return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ p: DocumentPicker) { self.parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }; parent.onPick(url)
        }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) {}
    }
}

// MARK: - Button Styles

private struct LibraryScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Document Grid Cell

struct DocumentGridCell: View {
    let document: ScannedDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let data = document.thumbnailData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color("Surface")
                            VStack(alignment: .leading, spacing: 5) {
                                Color("PrimaryGreen").opacity(0.5).frame(width: 55, height: 4).cornerRadius(1)
                                Spacer().frame(height: 2)
                                ForEach([0.9, 0.85, 0.92, 0.70, 0.0, 0.88, 0.60, 0.78], id: \.self) { w in
                                    if w > 0 { Color.black.opacity(0.12).frame(width: 80 * w, height: 2) }
                                    else     { Spacer().frame(height: 4) }
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .aspectRatio(0.77, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.04), lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
                if document.pageCount > 1 {
                    Text("\(document.pageCount)p")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color("PrimaryGreen").opacity(0.92)).cornerRadius(4).padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name).font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextPrimary"))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(document.formattedDate) · \(document.pageCount)p · \(document.formattedFileSize)")
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(Color("TextMuted"))
            }
        }
    }
}

// MARK: - Document List Row

struct DocumentListRow: View {
    let document: ScannedDocument
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let data = document.thumbnailData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color("Surface")
                    Image(systemName: "doc.text").font(.system(size: 18, weight: .light))
                        .foregroundColor(Color("TextMuted").opacity(0.5))
                }
            }
            .frame(width: 44, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color("Hairline"), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.name).font(.system(size: 15, weight: .medium)).foregroundColor(Color("TextPrimary")).lineLimit(1)
                Text("\(document.formattedDate) · \(document.pageCount)p · \(document.formattedFileSize)")
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(Color("TextMuted"))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundColor(Color("Hairline"))
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Color("Hairline")).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Empty State

struct LibraryEmptyState: View {
    let onScan: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundColor(Color("TextMuted").opacity(0.35))
                .padding(.bottom, 20)
            VStack(spacing: 10) {
                Text("Your scans will appear here")
                    .font(.system(size: 20, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                Text("You have 5 free scans. No card needed.")
                    .font(.system(size: 15)).foregroundColor(Color("TextMuted")).multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
            Button("Scan your first document", action: onScan)
                .buttonStyle(SHPrimaryButtonStyle(isFullWidth: false))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.bottom, 40)
    }
}

// MARK: - Previews

#Preview {
    LibraryView(showScanner: .constant(false))
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}
