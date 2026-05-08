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
    @State private var searchText         = ""
    @State private var selectedDocument: ScannedDocument?
    @State private var showDeleteConfirm  = false
    @State private var documentToDelete: ScannedDocument?
    @State private var layout: LibraryLayout = .grid
    @State private var showSettings       = false

    @State private var showImportOptions  = false
    @State private var showImagePicker    = false
    @State private var showDocumentPicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var importedImage: UIImage?
    @State private var showImportReview   = false

    enum LibraryLayout { case grid, list }

    var filteredDocuments: [ScannedDocument] {
        if searchText.isEmpty { return documents }
        return documents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color("Background").ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    LibraryTopBar(layout: $layout, showSettings: $showSettings)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    ScanCounterBanner(showPaywall: $showPaywall, isPro: storeKitManager.isPro)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    QuickActionsRow(
                        onScan:   handleScanTap,
                        onImport: { showImportOptions = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    if filteredDocuments.isEmpty {
                        LibraryEmptyState(onScan: handleScanTap)
                    } else {
                        HStack {
                            Text("RECENT")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color("TextMuted"))
                                .tracking(0.6)
                            Spacer()
                            Text("All folders")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color("TextMuted"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 22)
                        .padding(.bottom, 12)

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
                                .padding(.horizontal, 16)
                                .padding(.bottom, 140)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredDocuments) { doc in
                                        DocumentListRow(document: doc)
                                            .onTapGesture { selectedDocument = doc }
                                            .contextMenu { documentContextMenu(for: doc) }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 140)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedDocument) { doc in
                DocumentDetailView(document: doc)
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(triggerContext: paywallTrigger)
            }
            .confirmationDialog("Import Document", isPresented: $showImportOptions) {
                Button("Choose Photo")              { showImagePicker    = true }
                Button("Choose PDF or Document")    { showDocumentPicker = true }
                Button("Cancel", role: .cancel)     {}
            }
            .photosPicker(isPresented: $showImagePicker, selection: $photoPickerItem, matching: .images)
            .onChange(of: photoPickerItem) { _, item in
                Task {
                    guard let item else { return }
                    if let data  = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            importedImage    = image
                            photoPickerItem  = nil
                            showImportReview = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in handlePickedDocument(url: url) }
            }
            .fullScreenCover(isPresented: $showImportReview) {
                if let image = importedImage {
                    ScanReviewView(
                        images: [image],
                        isPresented: $showImportReview,
                        onSave: { document in saveDocument(document) }
                    )
                    .environmentObject(storeKitManager)
                    .environmentObject(scanLimitManager)
                }
            }
            .confirmationDialog("Delete Document?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let doc = documentToDelete { deleteDocument(doc) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Document Actions

    @ViewBuilder
    private func documentContextMenu(for document: ScannedDocument) -> some View {
        Button { } label: { Label("Rename",         systemImage: "pencil") }
        Button { } label: { Label("Move to Folder", systemImage: "folder") }
        Button { } label: { Label("Share",          systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive) {
            documentToDelete = document
            showDeleteConfirm = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    private func handleScanTap() {
        if storeKitManager.isPro || !scanLimitManager.hasReachedLimit {
            showScanner = true
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            paywallTrigger = .scanLimit
            showPaywall    = true
        }
    }

    private func handlePickedDocument(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            importPDF(from: url)
        } else if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                importedImage    = image
                showImportReview = true
            }
        }
    }

    private func importPDF(from sourceURL: URL) {
        let fileName = "\(UUID().uuidString).pdf"
        let destDir  = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScanHonest", isDirectory: true)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(fileName)
        guard (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil else { return }

        let attrs    = try? FileManager.default.attributesOfItem(atPath: destURL.path)
        let fileSize = (attrs?[.size] as? Int).flatMap { Int64($0) } ?? 0
        var pageCount = 1
        var thumbData: Data?

        if let pdf = PDFDocument(url: destURL) {
            pageCount = pdf.pageCount
            if let page = pdf.page(at: 0) {
                let rect  = page.bounds(for: .mediaBox)
                let scale: CGFloat = 1.5
                let size  = CGSize(width: rect.width * scale, height: rect.height * scale)
                let thumb = UIGraphicsImageRenderer(size: size).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.cgContext.scaleBy(x: scale, y: scale)
                    ctx.cgContext.translateBy(x: 0, y: rect.height)
                    ctx.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                thumbData = thumb.jpegData(compressionQuality: 0.7)
            }
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        saveDocument(ScannedDocument(
            name:          baseName.isEmpty ? "Imported PDF" : baseName,
            pageCount:     pageCount,
            fileSizeBytes: fileSize,
            fileURL:       destURL,
            thumbnailData: thumbData
        ))
    }

    func saveDocument(_ document: ScannedDocument) {
        modelContext.insert(document)
        if !storeKitManager.isPro { scanLimitManager.recordScan() }
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
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .jpeg, .png])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

// MARK: - Library Top Bar

private struct LibraryTopBar: View {
    @Binding var layout: LibraryView.LibraryLayout
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
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
            HStack(spacing: 12) {
                CircleToolbarButton(systemImage: "magnifyingglass")
                CircleToolbarButton(systemImage: "gearshape") { showSettings = true }
            }
        }
    }
}

private struct CircleToolbarButton: View {
    let systemImage: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color("TextPrimary"))
                .frame(width: 36, height: 36)
                .background(Color("Surface"))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scan Counter Banner

struct ScanCounterBanner: View {
    @Binding var showPaywall: Bool
    let isPro: Bool
    @EnvironmentObject var scanLimitManager: ScanLimitManager

    private var scanLimit: Int       { ScanLimitManager.freeMonthlyLimit }
    private var scansUsed: Int       { scanLimitManager.scansUsedThisMonth }
    private var isLimitReached: Bool { scansUsed >= scanLimit }

    private var progressColor: Color {
        if isLimitReached                            { return Color("Danger") }
        if scanLimitManager.progressFraction >= 0.8 { return Color("Warn")   }
        return Color("AccentGreen")
    }
    private var upgradeColor: Color { isLimitReached ? Color("Warn") : Color("SecondaryGreen") }

    private var usageLine: Text {
        let usedText  = Text("\(scansUsed)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(progressColor)
        let limitText = Text("\(scanLimit)")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(isLimitReached ? Color("Danger") : Color("TextPrimary"))
        return Text("\(usedText) of \(limitText) free scans used")
            .foregroundColor(Color("TextMuted"))
    }

    var body: some View {
        Button {
            if !isPro { showPaywall = true }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if isPro {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16)).foregroundColor(Color("AccentGreen"))
                        Text("Pro · Unlimited scans")
                            .font(.system(size: 14, weight: .medium)).foregroundColor(Color("TextPrimary"))
                        Spacer()
                        ProBadge()
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            usageLine.fixedSize(horizontal: false, vertical: true)
                            Text("\(scanLimitManager.scansRemaining) remaining · resets \(scanLimitManager.nextResetFormatted)")
                                .font(.system(size: 12))
                                .foregroundColor(isLimitReached ? Color("Warn") : Color("TextMuted"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("Upgrade →")
                            .font(.system(size: 12, weight: isLimitReached ? .bold : .semibold))
                            .foregroundColor(upgradeColor)
                            .padding(.top, 1)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color("Hairline").opacity(0.8)).frame(height: 4)
                            Capsule()
                                .fill(progressColor)
                                .frame(
                                    width: max(6, geo.size.width * CGFloat(scanLimitManager.progressFraction)),
                                    height: 4
                                )
                                .animation(.spring(response: 0.4), value: scanLimitManager.scansUsedThisMonth)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color("Hairline"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Actions Row

struct QuickActionsRow: View {
    let onScan:   () -> Void
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onScan) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 17, weight: .semibold))
                    Text("Scan Document").font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color("PrimaryGreen")).cornerRadius(28)
            }
            .buttonStyle(ScaleButtonStyle()).frame(maxWidth: .infinity)

            Button(action: onImport) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 15, weight: .medium))
                    Text("Import").font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(Color("PrimaryGreen"))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color("Surface"))
                .cornerRadius(28)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color("Hairline"), lineWidth: 1.5)
                )
            }
            .buttonStyle(ScaleButtonStyle()).frame(maxWidth: .infinity)
        }
    }
}

private struct ScaleButtonStyle: ButtonStyle {
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
                    if let thumbnailData = document.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 160)
                            .clipped()
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
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .frame(height: 160)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.04), lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                .shadow(color: .black.opacity(0.03), radius: 8, y: 2)

                if document.pageCount > 1 {
                    Text("\(document.pageCount)p")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color("PrimaryGreen").opacity(0.92))
                        .cornerRadius(4).padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("TextPrimary"))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(document.formattedDate) · \(document.pageCount)p · \(document.formattedFileSize)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color("TextMuted"))
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
                if let thumbnailData = document.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
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
                Text(document.name).font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color("TextPrimary")).lineLimit(1)
                Text("\(document.formattedDate) · \(document.pageCount)p · \(document.formattedFileSize)")
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(Color("TextMuted"))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                .foregroundColor(Color("Hairline"))
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
            EmptyLibraryGlyph().padding(.bottom, 26)
            VStack(spacing: 10) {
                Text("Your scans will appear here")
                    .font(.system(size: 20, weight: .semibold)).foregroundColor(Color("TextPrimary"))
                Text("You have 5 free scans. No card needed.")
                    .font(.system(size: 15)).foregroundColor(Color("TextMuted")).multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
            Button("Scan your first document", action: onScan)
                .buttonStyle(SHPrimaryButtonStyle(isFullWidth: false))
                .tint(Color("AccentGreen"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

private struct EmptyLibraryGlyph: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("TextMuted").opacity(0.35), lineWidth: 2)
                .frame(width: 42, height: 56)
                .overlay(alignment: .top) {
                    VStack(spacing: 5) {
                        Capsule().fill(Color("TextMuted").opacity(0.35)).frame(width: 20, height: 2)
                        Capsule().fill(Color("TextMuted").opacity(0.25)).frame(width: 16, height: 2)
                    }.padding(.top, 10)
                }
            Circle()
                .stroke(Color("TextMuted").opacity(0.45), lineWidth: 2)
                .frame(width: 20, height: 20)
                .background(Color("Background"))
                .overlay { Rectangle().fill(Color("Background")).frame(width: 18, height: 18) }
                .overlay(alignment: .bottomTrailing) {
                    Capsule().fill(Color("TextMuted").opacity(0.45))
                        .frame(width: 10, height: 2)
                        .rotationEffect(.degrees(45))
                        .offset(x: 5, y: 5)
                }
                .offset(x: 10, y: 8)
        }
        .frame(width: 64, height: 72)
    }
}

// MARK: - Previews

#Preview {
    LibraryView(showScanner: .constant(false))
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
        .modelContainer(for: [ScannedDocument.self, DocumentFolder.self], inMemory: true)
}

