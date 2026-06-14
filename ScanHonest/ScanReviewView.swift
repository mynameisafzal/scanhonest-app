import SwiftUI
@preconcurrency import PDFKit
import PhotosUI

// MARK: - ScanReviewView

struct ScanReviewView: View {
    let images: [UIImage]
    @Binding var isPresented: Bool
    let onSave: (ScannedDocument) -> Void

    @State private var currentPage: Int = 0
    @State private var processedImages: [UIImage]
    @State private var baseImages: [UIImage]
    @State private var undoStack: [[UIImage]] = []
    @State private var baseUndoStack: [[UIImage]] = []
    @State private var showSaveSheet      = false
    @State private var fileName           = ""
    @State private var selectedFilter: ScanFilter = .original
    @State private var isSaving           = false
    @State private var showCropView       = false
    @State private var isFilterProcessing = false
    @State private var showDeleteConfirm  = false
    @State private var showImagePicker    = false

    @EnvironmentObject var storeKitManager: StoreKitManager

    init(images: [UIImage], isPresented: Binding<Bool>, onSave: @escaping (ScannedDocument) -> Void) {
        self.images       = images
        self._isPresented = isPresented
        self.onSave       = onSave
        let seed = images.isEmpty ? [UIImage.blankDocumentPlaceholder()] : images
        self._processedImages = State(initialValue: seed)
        self._baseImages      = State(initialValue: seed)
    }

    private var safeCurrentPage: Int {
        guard !processedImages.isEmpty else { return 0 }
        return min(currentPage, processedImages.count - 1)
    }

    private var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()
                VStack(spacing: 0) {
                    headerBar
                    documentPreview
                    pageStrip
                    filterStrip
                    toolbarRow
                }
                if isFilterProcessing { filterSpinner }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showSaveSheet) {
                SaveDocumentSheet(
                    images: processedImages,
                    suggestedName: fileName,
                    isSaving: $isSaving,
                    onSave: { name, format in saveDocument(name: name, format: format) }
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCropView) {
                if !processedImages.isEmpty {
                    CropViewControllerRepresentable(
                        image: processedImages[safeCurrentPage],
                        isPresented: $showCropView
                    ) { cropped in
                        pushUndo()
                        guard safeCurrentPage < processedImages.count else { return }
                        baseImages[safeCurrentPage]      = cropped
                        processedImages[safeCurrentPage] = applyFilterToImage(cropped, filter: selectedFilter)
                    }
                    .ignoresSafeArea()
                }
            }
            .alert("Delete Page", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteCurrentPage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(processedImages.count == 1
                     ? "This is the last page. Deleting it will close the review."
                     : "Delete page \(safeCurrentPage + 1) of \(processedImages.count)?")
            }
            .sheet(isPresented: $showImagePicker) {
                MultiImagePicker { picked in
                    guard !picked.isEmpty else { return }
                    appendImages(picked)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { isPresented = false } label: {
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
                    Text("Retake")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color("PrimaryGreen"))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("retakeButton")

            Spacer(minLength: 8)

            Text("Review")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color("TextPrimary"))

            Spacer(minLength: 8)

            Button { showSaveSheet = true } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color("PrimaryGreen"))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(processedImages.isEmpty || isSaving)
            .accessibilityIdentifier("saveButton")
        }
        .padding(.top, 6).padding(.horizontal, 20).frame(height: 44)
    }

    private var documentPreview: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if processedImages.isEmpty {
                    Color("Surface").cornerRadius(12).padding(16)
                } else {
                    TabView(selection: $currentPage) {
                        ForEach(processedImages.indices, id: \.self) { index in
                            Image(uiImage: processedImages[index])
                                .resizable().scaledToFit()
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if processedImages.count > 0 {
                    Text(processedImages.count == 1
                         ? "1 page"
                         : "\(safeCurrentPage + 1) / \(processedImages.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color("TextMuted"))
                        .padding(.top, 16).padding(.trailing, 24)
                }
            }
        }
    }

    private var pageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(processedImages.indices, id: \.self) { index in
                    PageStripThumbnail(
                        image: processedImages[index],
                        isActive: safeCurrentPage == index,
                        pageNumber: index + 1
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25)) { currentPage = index }
                    }
                }
                Button { showImagePicker = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color("Hairline"),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 56, height: 72)
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                    }
                }
                .buttonStyle(ReviewPressStyle())
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .frame(height: 88)
        .background(Color("Background"))
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScanFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) {
                        guard !isFilterProcessing else { return }
                        applyFilter(filter)
                    }
                    .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .regular))
                    .foregroundColor(selectedFilter == filter ? Color("PrimaryGreen") : Color("TextMuted"))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(selectedFilter == filter ? Color("AccentSoft") : Color.clear)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(selectedFilter == filter ? Color("AccentGreen") : Color("Hairline"), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }

    private var toolbarRow: some View {
        HStack(spacing: 0) {
            ToolbarActionButton(icon: .crop,   label: "Crop")   { showCropView = true }
                .accessibilityIdentifier("cropButton")
            ToolbarActionButton(icon: .rotate, label: "Rotate") { pushUndo(); rotateCurrentPage() }
                .accessibilityIdentifier("rotateButton")
            ToolbarActionButton(icon: .undo,   label: "Undo", isActive: canUndo) { performUndo() }
                .accessibilityIdentifier("undoButton")
                .disabled(!canUndo)
            ToolbarActionButton(icon: .delete, label: "Delete") { showDeleteConfirm = true }
                .accessibilityIdentifier("deleteButton")
        }
        .padding(.horizontal, 4).padding(.vertical, 12)
        .background(Color("Surface")).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color("Hairline"), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
    }

    private var filterSpinner: some View {
        ZStack {
            Color(UIColor.systemFill).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView().scaleEffect(1.2).tint(Color("PrimaryGreen"))
                Text("Applying filter\u{2026}")
                    .font(.system(size: 13))
                    .foregroundColor(Color("TextMuted"))
            }
            .padding(24)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.12)))
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(processedImages)
        baseUndoStack.append(baseImages)
        if undoStack.count > 15 { undoStack.removeFirst(); baseUndoStack.removeFirst() }
    }

    private func performUndo() {
        guard let lp = undoStack.popLast(), let lb = baseUndoStack.popLast() else { return }
        processedImages = lp; baseImages = lb
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Filter

    private func applyFilter(_ filter: ScanFilter) {
        guard !baseImages.isEmpty else { return }
        let gate = DispatchWorkItem { withAnimation { isFilterProcessing = true } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: gate)
        pushUndo(); selectedFilter = filter
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let snapshot = baseImages
        Task.detached(priority: .userInitiated) {
            let filtered = snapshot.map { ScanFilterProcessor.apply(filter, to: $0) }
            await MainActor.run {
                gate.cancel()
                withAnimation { isFilterProcessing = false }
                processedImages = filtered
            }
        }
    }

    private func applyFilterToImage(_ image: UIImage, filter: ScanFilter) -> UIImage {
        ScanFilterProcessor.apply(filter, to: image)
    }

    // MARK: - Rotate

    private func rotateCurrentPage() {
        guard !processedImages.isEmpty, safeCurrentPage < processedImages.count else { return }
        let rotated = baseImages[safeCurrentPage].rotated(by: 90) ?? baseImages[safeCurrentPage]
        baseImages[safeCurrentPage]      = rotated
        processedImages[safeCurrentPage] = applyFilterToImage(rotated, filter: selectedFilter)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Delete

    private func deleteCurrentPage() {
        guard !processedImages.isEmpty else { return }
        pushUndo()
        let idx = safeCurrentPage
        processedImages.remove(at: idx); baseImages.remove(at: idx)
        if processedImages.isEmpty { isPresented = false }
        else { currentPage = min(idx, processedImages.count - 1) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Append
    //
    // Filter application on multiple large images was synchronous on @MainActor.
    // Fix: run CIFilter processing in Task.detached, append results on main actor.

    private func appendImages(_ newImages: [UIImage]) {
        pushUndo()
        let filter = selectedFilter
        Task.detached(priority: .userInitiated) {
            let filtered = newImages.map { ScanFilterProcessor.apply(filter, to: $0) }
            let thumbs   = newImages
            await MainActor.run {
                baseImages.append(contentsOf: thumbs)
                processedImages.append(contentsOf: filtered)
                let firstNew = processedImages.count - newImages.count
                withAnimation(.spring(response: 0.3)) { currentPage = firstNew }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Save
    //
    // Explicit result structs are required because Swift cannot infer the
    // generic parameter 'Success' of Task.detached when the closure returns
    // a tuple containing optionals or mixed types — leading to:
    //   "Cannot convert value of type 'Task<Success, Never>' to specified type '(_, _)'"
    //   "Generic parameter 'Success' could not be inferred"
    //
    // Using named structs makes the return type unambiguous and also fixes
    // "Expected 'else' after guard condition" that occurs when guard is used
    // on a tuple-destructure pattern like (url, size, thumb).

    private struct PDFSaveResult: @unchecked Sendable {
        let doc:   PDFDocument
        let thumb: Data?
    }
    private struct JPEGSaveResult {
        let url:   URL?
        let size:  Int64
        let thumb: Data?
    }

    private func saveDocument(name: String, format: SaveFormat) {
        isSaving = true
        let imagesCopy = processedImages
        let isPro      = storeKitManager.isPro

        Task {
            switch format {

            case .pdf:
                // Build PDFDocument + thumbnail off main thread.
                // Explicit ': PDFSaveResult' annotation avoids Swift type-inference failure.
                let work: PDFSaveResult = await Task.detached(priority: .userInitiated) {
                    let pdf = PDFDocument()
                    for (i, img) in imagesCopy.enumerated() {
                        if let page = PDFPage(image: img) { pdf.insert(page, at: i) }
                    }
                    return PDFSaveResult(
                        doc:   pdf,
                        thumb: imagesCopy.first?.portraitDocumentThumbnail()
                    )
                }.value

                // Encrypt + write to disk (async, off main thread inside savePDF)
                let result = await StorageManager.shared.savePDF(
                    work.doc, name: name, thumbnail: nil
                )

                let document = ScannedDocument(
                    name:          name,
                    pageCount:     imagesCopy.count,
                    fileSizeBytes: result?.size ?? 0,
                    fileURL:       result?.url,
                    thumbnailData: work.thumb
                )

                if isPro, let first = imagesCopy.first {
                    document.ocrText = try? await OCRProcessor.shared.extractText(from: first)
                    if let text = document.ocrText, document.name == "Scan" {
                        document.name = OCRProcessor.shared.suggestFileName(from: text)
                    }
                }

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSave(document)
                    isSaving    = false
                    isPresented = false
                }

            case .jpeg:
                // JPEG encode + file I/O off main thread.
                // Explicit ': JPEGSaveResult' annotation avoids Swift type-inference failure.
                let work: JPEGSaveResult = await Task.detached(priority: .userInitiated) {
                    let fm      = FileManager.default
                    let docsDir = fm.urls(for: .documentDirectory,
                                          in: .userDomainMask)[0]
                                    .appendingPathComponent("ScanHonest", isDirectory: true)
                    try? fm.createDirectory(at: docsDir, withIntermediateDirectories: true)

                    let base = UUID().uuidString
                    var firstURL: URL?
                    var totalSize: Int64 = 0

                    for (i, img) in imagesCopy.enumerated() {
                        let suffix  = imagesCopy.count == 1 ? "" : "_page\(i+1)"
                        let fileURL = docsDir.appendingPathComponent("\(base)\(suffix).jpg")
                        if let data = img.jpegData(compressionQuality: 0.88) {
                            try? data.write(to: fileURL)
                            totalSize += Int64(data.count)
                            if i == 0 { firstURL = fileURL }
                        }
                    }
                    return JPEGSaveResult(
                        url:   firstURL,
                        size:  totalSize,
                        thumb: imagesCopy.first?.portraitDocumentThumbnail()
                    )
                }.value

                // guard on a named binding — fixes "Expected 'else' after guard condition"
                // that occurs when guard is used on a tuple-destructure pattern.
                guard let savedURL = work.url else {
                    await MainActor.run { isSaving = false }
                    return
                }

                let document = ScannedDocument(
                    name:          name,
                    pageCount:     imagesCopy.count,
                    fileSizeBytes: work.size,
                    fileURL:       savedURL,
                    thumbnailData: work.thumb
                )

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSave(document)
                    isSaving = false
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
                await MainActor.run { isPresented = false }
            }
        }
    }
}

// MARK: - UIImage (non-filter extensions — main actor safe)

extension UIImage {
    static func blankDocumentPlaceholder() -> UIImage {
        let size = CGSize(width: 300, height: 390)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemGray6.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func portraitDocumentThumbnail() -> Data? {
        let targetRatio: CGFloat = 0.77
        let thumbSize = CGSize(width: 300, height: 390)
        let srcW = size.width, srcH = size.height
        let cropRect: CGRect
        if srcH > 0, (srcW / srcH) > targetRatio {
            let w = srcH * targetRatio
            cropRect = CGRect(x: (srcW - w) / 2, y: 0, width: w, height: srcH)
        } else {
            let h = srcH > 0 ? srcW / targetRatio : srcW
            cropRect = CGRect(x: 0, y: 0, width: srcW, height: min(h, srcH))
        }
        let s = scale
        guard let cg = cgImage?.cropping(to: CGRect(
            x: cropRect.minX*s, y: cropRect.minY*s,
            width: cropRect.width*s, height: cropRect.height*s)) else {
            return jpegData(compressionQuality: 0.7)
        }
        return UIGraphicsImageRenderer(size: thumbSize).image { _ in
            UIImage(cgImage: cg, scale: s, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: thumbSize))
        }.jpegData(compressionQuality: 0.75)
    }
}

// MARK: - Toolbar

private enum ReviewToolIcon { case crop, rotate, undo, delete }

private struct ToolbarActionButton: View {
    let icon: ReviewToolIcon
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isActive ? Color("AccentSoft") : Color.clear)
                        .frame(width: 38, height: 38)
                    ReviewToolGlyph(icon: icon,
                                    color: isActive ? Color("PrimaryGreen") : Color("TextPrimary"))
                }
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? Color("PrimaryGreen") : Color("TextMuted"))
            }
            .frame(minWidth: 56, maxWidth: .infinity)
        }
        .buttonStyle(ReviewPressStyle())
    }
}

private struct ReviewToolGlyph: View {
    let icon: ReviewToolIcon
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*s, y: y*s) }
            switch icon {
            case .crop:
                var p = Path()
                p.move(to: pt(6,2)); p.addLine(to: pt(6,18)); p.addLine(to: pt(22,18))
                p.move(to: pt(2,6)); p.addLine(to: pt(18,6)); p.addLine(to: pt(18,22))
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round))
            case .rotate:
                var p = Path()
                p.addArc(center: pt(12,12), radius: 9*s,
                         startAngle: .degrees(35), endAngle: .degrees(335), clockwise: false)
                p.move(to: pt(21,4)); p.addLine(to: pt(21,9)); p.addLine(to: pt(16,9))
                context.stroke(p, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round, lineJoin: .round))
            case .undo:
                var p = Path()
                p.addArc(center: pt(12,12), radius: 9*s,
                         startAngle: .degrees(205), endAngle: .degrees(335), clockwise: true)
                p.move(to: pt(3,7)); p.addLine(to: pt(3,12)); p.addLine(to: pt(8,12))
                context.stroke(p, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round, lineJoin: .round))
            case .delete:
                var lid = Path()
                lid.move(to: pt(3,6)); lid.addLine(to: pt(21,6))
                context.stroke(lid, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round))
                var handle = Path()
                handle.move(to: pt(9,6)); handle.addLine(to: pt(9,4))
                handle.addLine(to: pt(15,4)); handle.addLine(to: pt(15,6))
                context.stroke(handle, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round, lineJoin: .round))
                var body = Path()
                body.move(to: pt(5,6)); body.addLine(to: pt(6,20))
                body.addLine(to: pt(18,20)); body.addLine(to: pt(19,6))
                context.stroke(body, with: .color(color),
                               style: StrokeStyle(lineWidth: 1.6*s, lineCap: .round, lineJoin: .round))
                for cx in [9.0, 12.0, 15.0] {
                    var sl = Path()
                    sl.move(to: pt(cx,9)); sl.addLine(to: pt(cx,17))
                    context.stroke(sl, with: .color(color),
                                   style: StrokeStyle(lineWidth: 1.3*s, lineCap: .round))
                }
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Page strip thumbnail

struct PageStripThumbnail: View {
    let image: UIImage; let isActive: Bool; let pageNumber: Int
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color("AccentGreen") : Color("Hairline"),
                            lineWidth: isActive ? 2 : 1))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                .scaleEffect(isActive ? 1.0 : 0.97)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
            Text("\(pageNumber)")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(Color("TextMuted"))
                .padding(.trailing, 4).padding(.bottom, 4)
        }
    }
}

struct ReviewPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Save format

enum SaveFormat { case pdf, jpeg }

// MARK: - Save document sheet

struct SaveDocumentSheet: View {
    let images: [UIImage]
    var suggestedName: String
    @Binding var isSaving: Bool
    let onSave: (String, SaveFormat) -> Void

    @State private var format:     SaveFormat = .pdf
    @State private var editedName: String     = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                        TextField("Document name", text: $editedName)
                            .font(.system(size: 16)).padding(14)
                            .background(Color("Background")).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color("Hairline"), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                        Picker("Format", selection: $format) {
                            Text("PDF").tag(SaveFormat.pdf)
                            Text("JPEG").tag(SaveFormat.jpeg)
                        }.pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16)
                Spacer()
                Button { onSave(resolvedName, format); dismiss() } label: {
                    Group {
                        if isSaving { ProgressView().tint(.white) }
                        else {
                            Text("Save to ScanHonest")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color("PrimaryGreen")).cornerRadius(28)
                }
                .padding(.horizontal, 24).padding(.bottom, 16).disabled(isSaving)
            }
            .background(Color("Surface"))
            .navigationTitle("Save Document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color("TextMuted"))
                }
            }
            .onAppear {
                editedName = suggestedName.isEmpty
                    ? "Scan_\(Date().formatted(date: .abbreviated, time: .omitted))"
                    : suggestedName
            }
        }
    }

    private var resolvedName: String {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? suggestedName : editedName
    }
}

// MARK: - MultiImagePicker

struct MultiImagePicker: UIViewControllerRepresentable {
    let onPick: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images; config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator; return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([UIImage]) -> Void
        init(onPick: @escaping ([UIImage]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { onPick([]); return }
            var images = [UIImage?](repeating: nil, count: results.count)
            let group  = DispatchGroup()
            for (i, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    defer { group.leave() }; images[i] = obj as? UIImage
                }
            }
            group.notify(queue: .main) { self.onPick(images.compactMap { $0 }) }
        }
    }
}

// MARK: - Preview

#Preview {
    ScanReviewView(images: [], isPresented: .constant(true), onSave: { _ in })
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}
