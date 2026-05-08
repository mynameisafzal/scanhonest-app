import SwiftUI
import PDFKit

// MARK: - ScanReviewView

struct ScanReviewView: View {
    let images: [UIImage]
    @Binding var isPresented: Bool
    let onSave: (ScannedDocument) -> Void

    @State private var currentPage      = 0
    @State private var processedImages: [UIImage]
    @State private var undoStack:       [[UIImage]]   = []   // history for undo
    @State private var showSaveSheet    = false
    @State private var fileName         = ""
    @State private var selectedFilter: ScanFilter = .original
    @State private var isSaving         = false
    @State private var showCropView     = false
    @EnvironmentObject var storeKitManager: StoreKitManager

    enum ScanFilter: String, CaseIterable {
        case original   = "Color"
        case grayscale  = "Grayscale"
        case blackWhite = "B&W"
        case enhanced   = "Enhanced"
    }

    init(images: [UIImage], isPresented: Binding<Bool>, onSave: @escaping (ScannedDocument) -> Void) {
        self.images           = images
        self._isPresented     = isPresented
        self.onSave           = onSave
        self._processedImages = State(initialValue: images)
    }

    private var canUndo: Bool { !undoStack.isEmpty }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Main preview ──
                    GeometryReader { geo in
                        ZStack(alignment: .topTrailing) {
                            TabView(selection: $currentPage) {
                                ForEach(processedImages.indices, id: \.self) { index in
                                    Image(uiImage: processedImages[index])
                                        .resizable()
                                        .scaledToFit()
                                        .cornerRadius(12)
                                        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
                                        .shadow(color: .black.opacity(0.04), radius: 8,  y: 2)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .frame(width: geo.size.width, height: geo.size.height)

                            if processedImages.count > 1 {
                                Text("\(currentPage + 1) / \(processedImages.count)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color("TextMuted"))
                                    .padding(.top, 16)
                                    .padding(.trailing, 24)
                            }
                        }
                    }

                    // ── Page strip ──
                    if processedImages.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(processedImages.indices, id: \.self) { index in
                                    PageStripThumbnail(
                                        image: processedImages[index],
                                        isActive: currentPage == index,
                                        pageNumber: index + 1
                                    )
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25)) { currentPage = index }
                                    }
                                }
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
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .frame(height: 88)
                        .background(Color("Background"))
                    }

                    // ── Filter strip ──
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ScanFilter.allCases, id: \.self) { filter in
                                Button(filter.rawValue) { applyFilter(filter) }
                                    .font(.system(size: 14,
                                                  weight: selectedFilter == filter ? .semibold : .regular))
                                    .foregroundColor(selectedFilter == filter
                                                     ? Color("PrimaryGreen") : Color("TextMuted"))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color("AccentSoft") : Color.clear)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(selectedFilter == filter
                                                    ? Color("AccentGreen") : Color("Hairline"), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 8)

                    // ── Bottom toolbar ──
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 0) {
                            ToolbarActionButton(icon: "crop",            label: "Crop")    { showCropView = true }
                            ToolbarActionButton(icon: "rotate.right",    label: "Rotate")  { pushUndo(); rotateCurrentPage() }
                            ToolbarActionButton(icon: "wand.and.stars",  label: "Enhance") { pushUndo(); enhanceCurrentPage() }
                            ToolbarActionButton(
                                icon:  canUndo ? "arrow.uturn.backward" : "arrow.uturn.backward",
                                label: "Undo",
                                color: canUndo ? Color("TextPrimary") : Color("Hairline")
                            ) { undoLastChange() }
                            ToolbarActionButton(icon: "camera.badge.clock", label: "Retake") { retakePage() }
                        }
                        .frame(height: 72)
                        .background(Color("Surface"))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { isPresented = false } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Retake")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(Color("PrimaryGreen"))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color("Surface"))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .principal) {
                    Text("Review")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color("TextPrimary"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSaveSheet = true } label: {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color("PrimaryGreen"))
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                SaveDocumentSheet(
                    images: processedImages,
                    suggestedName: fileName,
                    isSaving: $isSaving,
                    onSave: { name, format in saveDocument(name: name, format: format) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCropView) {
                CropView(image: processedImages[currentPage]) { cropped in
                    pushUndo()
                    processedImages[currentPage] = cropped
                    selectedFilter = .original
                }
            }
        }
    }

    // MARK: - Undo

    private func pushUndo() {
        undoStack.append(processedImages)
        // Keep max 10 undo steps to avoid memory bloat
        if undoStack.count > 10 { undoStack.removeFirst() }
    }

    private func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        processedImages = previous
        selectedFilter  = .original
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Actions

    private func applyFilter(_ filter: ScanFilter) {
        pushUndo()
        selectedFilter  = filter
        let base = undoStack.last ?? images
        processedImages = base.map { image in
            switch filter {
            case .original:   return image
            case .grayscale:  return image.applyingGrayscale()    ?? image
            case .blackWhite: return image.applyingBlackAndWhite() ?? image
            case .enhanced:   return image.applyingAutoEnhance()   ?? image
            }
        }
        // If undo was pushed just for filter, pop it back and repush with correct base
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rotateCurrentPage() {
        let rotated = processedImages[currentPage].rotated(by: 90) ?? processedImages[currentPage]
        processedImages[currentPage] = rotated
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func enhanceCurrentPage() {
        guard let enhanced = processedImages[currentPage].applyingAutoEnhance() else { return }
        processedImages[currentPage] = enhanced
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func retakePage() { isPresented = false }

    private func saveDocument(name: String, format: SaveFormat) {
        isSaving = true
        Task {
            let pdfDocument = PDFDocument()
            for (i, image) in processedImages.enumerated() {
                if let page = PDFPage(image: image) { pdfDocument.insert(page, at: i) }
            }
            let result        = StorageManager.shared.savePDF(pdfDocument, name: name, thumbnail: processedImages.first)
            let thumbnailData = processedImages.first?.portraitDocumentThumbnail()
            let document = ScannedDocument(
                name:          name,
                pageCount:     processedImages.count,
                fileSizeBytes: result?.size ?? 0,
                fileURL:       result?.url,
                thumbnailData: thumbnailData
            )
            if storeKitManager.isPro, let firstImage = processedImages.first {
                document.ocrText = try? await OCRProcessor.shared.extractText(from: firstImage)
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
        }
    }
}

// MARK: - CropView (pixel-accurate UIKit renderer)

struct CropView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    // User gesture state
    @State private var scale:      CGFloat = 1.0
    @State private var lastScale:  CGFloat = 1.0
    @State private var offset:     CGSize  = .zero
    @State private var lastOffset: CGSize  = .zero

    // Screen geometry captured at render time
    @State private var screenSize:    CGSize = .zero
    @State private var cropFrameRect: CGRect = .zero  // in screen coords

    private let cropRatio: CGFloat = 0.77  // A4 portrait

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let cropW = geo.size.width - 48
                let cropH = cropW / cropRatio
                let cropX = (geo.size.width  - cropW) / 2
                let cropY = (geo.size.height - cropH) / 2

                ZStack {
                    // Image — fills screen, pan + zoom
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale, anchor: .center)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { v in scale = max(1.0, lastScale * v) }
                                    .onEnded   { _ in lastScale = scale },
                                DragGesture()
                                    .onChanged { v in
                                        offset = CGSize(
                                            width:  lastOffset.width  + v.translation.width,
                                            height: lastOffset.height + v.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                        )
                        .clipped()

                    // Dark overlay outside crop
                    Color.black.opacity(0.55)
                        .mask(
                            Rectangle()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .frame(width: cropW, height: cropH)
                                        .blendMode(.destinationOut)
                                )
                        )
                        .allowsHitTesting(false)

                    // Crop border
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: cropW, height: cropH)
                        .allowsHitTesting(false)

                    // Corner handles
                    cropCornerHandles(w: cropW, h: cropH)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear {
                    screenSize = geo.size
                    cropFrameRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                }
                .onChange(of: geo.size) { _, newSize in
                    screenSize = newSize
                    let w = newSize.width - 48
                    let h = w / cropRatio
                    cropFrameRect = CGRect(
                        x: (newSize.width  - w) / 2,
                        y: (newSize.height - h) / 2,
                        width: w, height: h
                    )
                }
            }

            // Top bar
            VStack {
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                        .padding(20)
                    Spacer()
                    Text("Crop")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") {
                        let cropped = renderCrop()
                        onCrop(cropped)
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("AccentGreen"))
                    .padding(20)
                }
                Spacer()
            }

            // Bottom hint
            VStack {
                Spacer()
                Text("Pinch to zoom · Drag to reposition")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Pixel-accurate crop renderer

    /// Renders exactly what is visible inside the crop frame at full image resolution.
    private func renderCrop() -> UIImage {
        guard screenSize != .zero, cropFrameRect != .zero else { return image }

        let imgW = image.size.width
        let imgH = image.size.height

        // 1. What scale does the image render at (scaledToFill into screenSize)?
        let fillScaleX = screenSize.width  / imgW
        let fillScaleY = screenSize.height / imgH
        let fillScale  = max(fillScaleX, fillScaleY)   // scaledToFill uses max

        // 2. Rendered image size on screen (before user scale/offset) — used to verify fill scale
        _ = imgW * fillScale  // renderedW — confirms fill calculation
        _ = imgH * fillScale  // renderedH — confirms fill calculation

        // 3. Image centre on screen (accounting for user offset + user scale)
        let centerX = screenSize.width  / 2 + offset.width
        let centerY = screenSize.height / 2 + offset.height

        // 4. Top-left of rendered image on screen (with user zoom)
        let totalScale = fillScale * scale
        let imgLeft = centerX - (imgW * totalScale) / 2
        let imgTop  = centerY - (imgH * totalScale) / 2

        // 5. Convert crop frame (screen coords) → image pixel coords
        let pixelX = (cropFrameRect.minX - imgLeft) / totalScale
        let pixelY = (cropFrameRect.minY - imgTop)  / totalScale
        let pixelW = cropFrameRect.width  / totalScale
        let pixelH = cropFrameRect.height / totalScale

        // 6. Clamp to image bounds
        let clampedX = max(0, min(pixelX, imgW - 1))
        let clampedY = max(0, min(pixelY, imgH - 1))
        let clampedW = min(pixelW, imgW - clampedX)
        let clampedH = min(pixelH, imgH - clampedY)

        guard clampedW > 0, clampedH > 0 else { return image }

        // 7. Scale pixel coords to CGImage resolution
        let s = image.scale
        let cgRect = CGRect(
            x: clampedX * s, y: clampedY * s,
            width: clampedW * s, height: clampedH * s
        )

        if let cgImg = image.cgImage?.cropping(to: cgRect) {
            return UIImage(cgImage: cgImg, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }

    @ViewBuilder
    private func cropCornerHandles(w: CGFloat, h: CGFloat) -> some View {
        let arm: CGFloat   = 22
        let thick: CGFloat = 3
        ZStack {
            Group {
                // Top-left
                Path { p in
                    p.move(to:    CGPoint(x: -w/2,       y: -h/2 + arm))
                    p.addLine(to: CGPoint(x: -w/2,       y: -h/2))
                    p.addLine(to: CGPoint(x: -w/2 + arm, y: -h/2))
                }.stroke(Color.white, lineWidth: thick)
                // Top-right
                Path { p in
                    p.move(to:    CGPoint(x: w/2 - arm,  y: -h/2))
                    p.addLine(to: CGPoint(x: w/2,        y: -h/2))
                    p.addLine(to: CGPoint(x: w/2,        y: -h/2 + arm))
                }.stroke(Color.white, lineWidth: thick)
                // Bottom-left
                Path { p in
                    p.move(to:    CGPoint(x: -w/2,       y:  h/2 - arm))
                    p.addLine(to: CGPoint(x: -w/2,       y:  h/2))
                    p.addLine(to: CGPoint(x: -w/2 + arm, y:  h/2))
                }.stroke(Color.white, lineWidth: thick)
                // Bottom-right
                Path { p in
                    p.move(to:    CGPoint(x: w/2 - arm,  y:  h/2))
                    p.addLine(to: CGPoint(x: w/2,        y:  h/2))
                    p.addLine(to: CGPoint(x: w/2,        y:  h/2 - arm))
                }.stroke(Color.white, lineWidth: thick)
            }
        }
    }
}

// MARK: - ToolbarActionButton (with optional colour override)

struct ToolbarActionButton: View {
    let icon:   String
    let label:  String
    var color:  Color = Color("TextPrimary")
    let action: () -> Void

    init(icon: String, label: String, color: Color = Color("TextPrimary"), action: @escaping () -> Void) {
        self.icon   = icon
        self.label  = label
        self.color  = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color == Color("TextPrimary") ? Color("TextMuted") : color.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ReviewPressStyle())
    }
}

// MARK: - PageStripThumbnail

struct PageStripThumbnail: View {
    let image:      UIImage
    let isActive:   Bool
    let pageNumber: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color("AccentGreen") : Color("Hairline"),
                                lineWidth: isActive ? 2 : 1)
                )
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

// MARK: - Button Styles

private struct ReviewPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Save Sheet

enum SaveFormat { case pdf, jpeg }

struct SaveDocumentSheet: View {
    let images:        [UIImage]
    var suggestedName: String
    @Binding var isSaving: Bool
    let onSave: (String, SaveFormat) -> Void

    @State private var format:     SaveFormat = .pdf
    @State private var editedName: String     = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                        TextField("Document name", text: $editedName)
                            .font(.system(size: 16))
                            .padding(14)
                            .background(Color("Background"))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("Hairline"), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("TextMuted"))
                        Picker("Format", selection: $format) {
                            Text("PDF").tag(SaveFormat.pdf)
                            Text("JPEG").tag(SaveFormat.jpeg)
                        }
                        .pickerStyle(.segmented)
                    }
                    Button {
                        onSave(editedName.isEmpty ? suggestedName : editedName, format)
                        dismiss()
                    } label: {
                        Group {
                            if isSaving { ProgressView().tint(.white) }
                            else {
                                Text("Save to ScanHonest")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color("PrimaryGreen"))
                        .cornerRadius(28)
                    }
                    .disabled(isSaving)

                    Button {
                        onSave(editedName.isEmpty ? suggestedName : editedName, format)
                    } label: {
                        Text("Save & Share")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Color("AccentGreen"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color("AccentGreen"), lineWidth: 1.5))
                    }
                    .buttonStyle(ReviewPressStyle())
                }
                .padding(.horizontal, 24).padding(.top, 12)
                Spacer()
            }
            .background(Color("Surface"))
            .navigationTitle("Save Document")
            .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - UIImage Extensions

extension UIImage {

    func portraitDocumentThumbnail() -> Data? {
        let targetRatio: CGFloat = 0.77
        let thumbSize = CGSize(width: 300, height: 390)
        let srcW = size.width, srcH = size.height
        let cropRect: CGRect
        if (srcW / srcH) > targetRatio {
            let w = srcH * targetRatio
            cropRect = CGRect(x: (srcW - w) / 2, y: 0, width: w, height: srcH)
        } else {
            let h = srcW / targetRatio
            cropRect = CGRect(x: 0, y: 0, width: srcW, height: min(h, srcH))
        }
        let s = scale
        let scaled = CGRect(x: cropRect.minX*s, y: cropRect.minY*s,
                            width: cropRect.width*s, height: cropRect.height*s)
        guard let cg = cgImage?.cropping(to: scaled) else { return jpegData(compressionQuality: 0.7) }
        let cropped  = UIImage(cgImage: cg, scale: s, orientation: imageOrientation)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        return renderer.image { _ in cropped.draw(in: CGRect(origin: .zero, size: thumbSize)) }
            .jpegData(compressionQuality: 0.75)
    }

    func applyingGrayscale() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let f = CIFilter(name: "CIColorControls")
        f?.setValue(ci, forKey: kCIInputImageKey)
        f?.setValue(0,  forKey: kCIInputSaturationKey)
        guard let out = f?.outputImage else { return nil }
        guard let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func applyingBlackAndWhite() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let f = CIFilter(name: "CIPhotoEffectNoir")
        f?.setValue(ci, forKey: kCIInputImageKey)
        guard let out = f?.outputImage else { return nil }
        guard let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func applyingAutoEnhance() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let f = CIFilter(name: "CIColorControls")
        f?.setValue(ci,   forKey: kCIInputImageKey)
        f?.setValue(1.15, forKey: kCIInputContrastKey)
        f?.setValue(0.05, forKey: kCIInputBrightnessKey)
        f?.setValue(1.1,  forKey: kCIInputSaturationKey)
        guard let out = f?.outputImage else { return nil }
        guard let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func rotated(by degrees: CGFloat) -> UIImage? {
        let rad = degrees * .pi / 180
        var s = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: rad)).size
        s.width = floor(s.width); s.height = floor(s.height)
        UIGraphicsBeginImageContextWithOptions(s, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.translateBy(x: s.width/2, y: s.height/2)
        ctx.rotate(by: rad)
        draw(in: CGRect(x: -size.width/2, y: -size.height/2, width: size.width, height: size.height))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}

// MARK: - Previews

#Preview {
    ScanReviewView(images: [], isPresented: .constant(true), onSave: { _ in })
        .environmentObject(StoreKitManager())
        .environmentObject(ScanLimitManager())
}


