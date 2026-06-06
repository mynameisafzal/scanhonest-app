import SwiftUI
import PDFKit

// MARK: - ScanReviewView
// ISSUE 3 FIX: .navigationBarBackButtonHidden(true) added so the system never
// injects a "..." truncated back button when this view's NavigationStack is
// presented as a fullScreenCover. The custom "← Retake" button is the only
// back affordance.

struct ScanReviewView: View {
    let images: [UIImage]
    @Binding var isPresented: Bool
    let onSave: (ScannedDocument) -> Void

    @State private var currentPage: Int = 0
    @State private var processedImages: [UIImage]
    @State private var undoStack: [[UIImage]] = []
    @State private var showSaveSheet = false
    @State private var fileName      = ""
    @State private var selectedFilter: ScanFilter = .enhanced
    @State private var isSaving      = false
    @State private var showCropView  = false
    @EnvironmentObject var storeKitManager: StoreKitManager

    enum ScanFilter: String, CaseIterable {
        case original = "Color"; case grayscale = "Grayscale"
        case blackWhite = "B&W"; case enhanced = "Enhanced"
    }

    init(images: [UIImage], isPresented: Binding<Bool>, onSave: @escaping (ScannedDocument) -> Void) {
        self.images       = images
        self._isPresented = isPresented
        self.onSave       = onSave
        let seed = images.isEmpty ? [UIImage.blankDocumentPlaceholder()] : images
        self._processedImages = State(initialValue: seed)
    }

    private var safeCurrentPage: Int {
        guard !processedImages.isEmpty else { return 0 }
        return min(currentPage, processedImages.count - 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Header ─ matches Screen 4 design exactly ─────────────────
                    // padding: '6px 20px 0'
                    // LEFT:   Icon.back(primary,18) + "Retake" 15pt/500 gap:4
                    // CENTER: "Review" 16pt/600 SH.text
                    // RIGHT:  "Save" pill bg:primary radius:999 14pt/600
                    // ──────────────────────────────────────────────────────────────
                    HStack(alignment: .center, spacing: 0) {

                        // LEFT ─ back + "Retake"
                        Button { isPresented = false } label: {
                            HStack(spacing: 4) {
                                Canvas { context, size in
                                    let s = min(size.width, size.height) / 24
                                    var p = Path()
                                    p.move(to:    CGPoint(x: 15*s, y:  5*s))
                                    p.addLine(to: CGPoint(x:  8*s, y: 12*s))
                                    p.addLine(to: CGPoint(x: 15*s, y: 19*s))
                                    context.stroke(p, with: .color(Color("PrimaryGreen")),
                                                   style: StrokeStyle(lineWidth: 2*s, lineCap: .round,
                                                                      lineJoin: .round))
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

                        // CENTER ─ "Review" 16pt semibold
                        Text("Review")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color("TextPrimary"))

                        Spacer(minLength: 8)

                        // RIGHT ─ "Save" pill
                        Button { showSaveSheet = true } label: {
                            Text("Save")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Color("PrimaryGreen"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(processedImages.isEmpty)
                        .accessibilityIdentifier("saveButton")
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 20)
                    .frame(height: 44)

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
                                            .shadow(color: .black.opacity(0.04), radius: 8,  y: 2)
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .tag(index)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .never))
                                .frame(width: geo.size.width, height: geo.size.height)
                            }
                            if processedImages.count > 1 {
                                Text("\(safeCurrentPage + 1) / \(processedImages.count)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color("TextMuted"))
                                    .padding(.top, 16).padding(.trailing, 24)
                            }
                        }
                    }

                    if processedImages.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(processedImages.indices, id: \.self) { index in
                                    PageStripThumbnail(image: processedImages[index],
                                                       isActive: safeCurrentPage == index,
                                                       pageNumber: index + 1)
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.25)) { currentPage = index }
                                    }
                                }
                                    // FIX #6: "+" button now re-opens the scanner to add another page.
                    // Previously it was a ZStack with no action — tapping did nothing.
                    Button {
                        isPresented = false   // close review; ScannerView re-presents
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color("Hairline"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
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
                        .frame(height: 88).background(Color("Background"))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ScanFilter.allCases, id: \.self) { filter in
                                Button(filter.rawValue) { applyFilter(filter) }
                                    .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .regular))
                                    .foregroundColor(selectedFilter == filter ? Color("PrimaryGreen") : Color("TextMuted"))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(selectedFilter == filter ? Color("AccentSoft") : Color.clear)
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20)
                                        .stroke(selectedFilter == filter ? Color("AccentGreen") : Color("Hairline"), lineWidth: 1))
                                    .accessibilityIdentifier({
                                        switch filter {
                                        case .original:   return "filterColor"
                                        case .grayscale:  return "filterGrayscale"
                                        case .blackWhite: return "filterBW"
                                        case .enhanced:   return "filterEnhanced"
                                        }
                                    }())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 8)

                    HStack(spacing: 0) {
                        ToolbarActionButton(icon: .crop,    label: "Crop")    { showCropView = true }
                            .accessibilityIdentifier("cropButton")
                        ToolbarActionButton(icon: .rotate,  label: "Rotate")  { pushUndo(); rotateCurrentPage() }
                            .accessibilityIdentifier("rotateButton")
                        ToolbarActionButton(icon: .enhance, label: "Enhance", isActive: true) { pushUndo(); enhanceCurrentPage() }
                            .accessibilityIdentifier("enhanceButton")
                        ToolbarActionButton(icon: .filter,  label: "Filter")  { applyFilter(.blackWhite) }
                            .accessibilityIdentifier("filterButton")
                        ToolbarActionButton(icon: .delete,  label: "Delete")  { deleteCurrentPage() }
                            .accessibilityIdentifier("deleteButton")
                    }
                    .padding(.horizontal, 4).padding(.vertical, 12)
                    .background(Color("Surface")).cornerRadius(18)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color("Hairline"), lineWidth: 1))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                }
            }
            // Hide the system navigation bar — header is drawn inline above
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            // Apply Auto Enhance immediately so the first frame users see is enhanced.
            .onAppear { applyFilter(.enhanced) }
            .sheet(isPresented: $showSaveSheet) {
                SaveDocumentSheet(images: processedImages, suggestedName: fileName,
                                  isSaving: $isSaving,
                                  onSave: { name, format in
                    saveDocument(name: name, format: format)
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCropView) {
                if !processedImages.isEmpty {
                    CropViewControllerRepresentable(
                        image: processedImages[safeCurrentPage],
                        isPresented: $showCropView
                    ) { cropped in
                        pushUndo()
                        if safeCurrentPage < processedImages.count {
                            processedImages[safeCurrentPage] = cropped
                        }
                        selectedFilter = .original
                    }
                    .ignoresSafeArea()
                }
            }
        }
    }

    private func pushUndo() { undoStack.append(processedImages); if undoStack.count > 10 { undoStack.removeFirst() } }

    private func applyFilter(_ filter: ScanFilter) {
        guard !processedImages.isEmpty else { return }
        pushUndo(); selectedFilter = filter
        processedImages = images.map { image in
            switch filter {
            case .original:   return image
            case .grayscale:  return image.applyingGrayscale()     ?? image
            case .blackWhite: return image.applyingBlackAndWhite() ?? image
            case .enhanced:   return image.applyingAutoEnhance()   ?? image
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func rotateCurrentPage() {
        guard !processedImages.isEmpty, safeCurrentPage < processedImages.count else { return }
        processedImages[safeCurrentPage] = processedImages[safeCurrentPage].rotated(by: 90) ?? processedImages[safeCurrentPage]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func enhanceCurrentPage() {
        guard !processedImages.isEmpty, safeCurrentPage < processedImages.count else { return }
        guard let enhanced = processedImages[safeCurrentPage].applyingAutoEnhance() else { return }
        processedImages[safeCurrentPage] = enhanced
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func retakePage() { isPresented = false }

    private func deleteCurrentPage() {
        guard !processedImages.isEmpty else { return }
        pushUndo()
        let idx = safeCurrentPage
        processedImages.remove(at: idx)
        if processedImages.isEmpty {
            // Last page deleted — close review
            isPresented = false
        } else {
            // Keep currentPage in bounds
            currentPage = min(idx, processedImages.count - 1)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func saveDocument(name: String, format: SaveFormat) {
        isSaving = true
        Task {
            // FIX #3: respect the format the user chose in SaveDocumentSheet.
            // Previously the code always built a PDFDocument regardless of
            // whether the user selected JPEG — the format parameter was ignored.
            switch format {

            case .pdf:
                let pdfDocument = PDFDocument()
                for (i, image) in processedImages.enumerated() {
                    if let page = PDFPage(image: image) { pdfDocument.insert(page, at: i) }
                }
                let result        = StorageManager.shared.savePDF(pdfDocument, name: name, thumbnail: processedImages.first)
                let thumbnailData = processedImages.first?.portraitDocumentThumbnail()
                let document = ScannedDocument(
                    name: name, pageCount: processedImages.count,
                    fileSizeBytes: result?.size ?? 0,
                    fileURL: result?.url, thumbnailData: thumbnailData
                )
                if storeKitManager.isPro, let firstImage = processedImages.first {
                    document.ocrText = try? await OCRProcessor.shared.extractText(from: firstImage)
                    if let text = document.ocrText, document.name == "Scan" {
                        document.name = OCRProcessor.shared.suggestFileName(from: text)
                    }
                }
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSave(document); isSaving = false; isPresented = false
                }

            case .jpeg:
                // Multi-page JPEG: save each page as a separate image file.
                // We create one ScannedDocument record pointing to the first image;
                // additional pages are stored alongside it as _page2.jpg, _page3.jpg.
                // The PDF viewer in DocumentDetailView will show a placeholder for
                // JPEG-only saves — the images are accessible via the share sheet.
                let fm       = FileManager.default
                let docsDir  = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                  .appendingPathComponent("ScanHonest", isDirectory: true)
                try? fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
                let baseName = "\(UUID().uuidString)"
                var firstURL: URL?; var totalSize: Int64 = 0

                for (i, image) in processedImages.enumerated() {
                    let suffix  = processedImages.count == 1 ? "" : "_page\(i + 1)"
                    let fileURL = docsDir.appendingPathComponent("\(baseName)\(suffix).jpg")
                    if let data = image.jpegData(compressionQuality: 0.88) {
                        try? data.write(to: fileURL)
                        totalSize += Int64(data.count)
                        if i == 0 { firstURL = fileURL }
                    }
                }

                let thumbnailData = processedImages.first?.portraitDocumentThumbnail()
                let document = ScannedDocument(
                    name: name, pageCount: processedImages.count,
                    fileSizeBytes: totalSize,
                    fileURL: firstURL, thumbnailData: thumbnailData
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onSave(document); isSaving = false; isPresented = false
                }
            }
        }
    }
}

// MARK: - UIImage blank placeholder
extension UIImage {
    static func blankDocumentPlaceholder() -> UIImage {
        let size = CGSize(width: 300, height: 390)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// (CropView removed — replaced by CropViewController.swift / CropViewControllerRepresentable)

private enum ReviewToolIcon { case crop, rotate, enhance, filter, delete }

private struct ToolbarActionButton: View {
    let icon: ReviewToolIcon; let label: String; var isActive=false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(isActive ? Color("AccentSoft") : Color.clear).frame(width: 38, height: 38)
                    ReviewToolGlyph(icon: icon, color: isActive ? Color("PrimaryGreen") : Color("TextPrimary"))
                }
                Text(label).font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? Color("PrimaryGreen") : Color("TextMuted"))
            }
            .frame(minWidth: 56, maxWidth: .infinity)
        }
        .buttonStyle(ReviewPressStyle())
    }
}

private struct ReviewToolGlyph: View {
    let icon: ReviewToolIcon; let color: Color
    var body: some View {
        Canvas { context, size in
            let s=min(size.width,size.height)/24
            func pt(_ x:CGFloat,_ y:CGFloat)->CGPoint{CGPoint(x:x*s,y:y*s)}
            switch icon {
            case .crop:
                var p=Path(); p.move(to:pt(6,2));p.addLine(to:pt(6,18));p.addLine(to:pt(22,18));p.move(to:pt(2,6));p.addLine(to:pt(18,6));p.addLine(to:pt(18,22))
                context.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineCap:.round))
            case .rotate:
                var p=Path(); p.addArc(center:pt(12,12),radius:9*s,startAngle:.degrees(35),endAngle:.degrees(335),clockwise:false)
                p.move(to:pt(21,4));p.addLine(to:pt(21,9));p.addLine(to:pt(16,9))
                context.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineCap:.round,lineJoin:.round))
            case .enhance:
                var p=Path(); p.move(to:pt(12,3));p.addLine(to:pt(13.8,7.5));p.addLine(to:pt(18,9));p.addLine(to:pt(13.8,10.5));p.addLine(to:pt(12,15));p.addLine(to:pt(10.2,10.5));p.addLine(to:pt(6,9));p.addLine(to:pt(10.2,7.5));p.closeSubpath()
                context.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineJoin:.round))
            case .filter:
                context.stroke(Path(ellipseIn:CGRect(x:3*s,y:6*s,width:12*s,height:12*s)),with:.color(color),lineWidth:1.6*s)
                context.stroke(Path(ellipseIn:CGRect(x:9*s,y:6*s,width:12*s,height:12*s)),with:.color(color),lineWidth:1.6*s)
            case .delete:
                // Trash-bin glyph: lid + body + three vertical slots
                // Lid
                var lid=Path(); lid.move(to:pt(3,6));lid.addLine(to:pt(21,6))
                context.stroke(lid,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineCap:.round))
                // Handle on lid
                var handle=Path(); handle.move(to:pt(9,6));handle.addLine(to:pt(9,4));handle.addLine(to:pt(15,4));handle.addLine(to:pt(15,6))
                context.stroke(handle,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineCap:.round,lineJoin:.round))
                // Body
                var body=Path(); body.move(to:pt(5,6));body.addLine(to:pt(6,20));body.addLine(to:pt(18,20));body.addLine(to:pt(19,6))
                context.stroke(body,with:.color(color),style:StrokeStyle(lineWidth:1.6*s,lineCap:.round,lineJoin:.round))
                // Vertical slots inside
                var s1=Path(); s1.move(to:pt(9,9));s1.addLine(to:pt(9,17))
                context.stroke(s1,with:.color(color),style:StrokeStyle(lineWidth:1.3*s,lineCap:.round))
                var s2=Path(); s2.move(to:pt(12,9));s2.addLine(to:pt(12,17))
                context.stroke(s2,with:.color(color),style:StrokeStyle(lineWidth:1.3*s,lineCap:.round))
                var s3=Path(); s3.move(to:pt(15,9));s3.addLine(to:pt(15,17))
                context.stroke(s3,with:.color(color),style:StrokeStyle(lineWidth:1.3*s,lineCap:.round))
            }
        }.frame(width:22,height:22)
    }
}

struct PageStripThumbnail: View {
    let image:UIImage; let isActive:Bool; let pageNumber:Int
    var body: some View {
        ZStack(alignment:.bottomTrailing) {
            Image(uiImage:image).resizable().scaledToFill().frame(width:56,height:72).clipShape(RoundedRectangle(cornerRadius:8))
                .overlay(RoundedRectangle(cornerRadius:8).stroke(isActive ? Color("AccentGreen"):Color("Hairline"),lineWidth:isActive ? 2:1))
                .shadow(color:.black.opacity(0.06),radius:4,y:2).scaleEffect(isActive ? 1.0:0.97)
                .animation(.spring(response:0.25,dampingFraction:0.8),value:isActive)
            Text("\(pageNumber)").font(.system(size:8,weight:.semibold,design:.monospaced))
                .foregroundColor(Color("TextMuted")).padding(.trailing,4).padding(.bottom,4)
        }
    }
}

private struct ReviewBackGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s=min(size.width,size.height)/24
            var p=Path(); p.move(to:CGPoint(x:15*s,y:5*s)); p.addLine(to:CGPoint(x:8*s,y:12*s)); p.addLine(to:CGPoint(x:15*s,y:19*s))
            context.stroke(p,with:.color(Color("PrimaryGreen")),style:StrokeStyle(lineWidth:2*s,lineCap:.round,lineJoin:.round))
        }.frame(width:18,height:18)
    }
}

struct ReviewPressStyle: ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.91:1.0)
            .animation(.spring(response:0.2,dampingFraction:0.7),value:configuration.isPressed)
    }
}

enum SaveFormat { case pdf, jpeg }

struct SaveDocumentSheet: View {
    let images:[UIImage]; var suggestedName:String
    @Binding var isSaving:Bool
    let onSave:(String,SaveFormat)->Void
    @State private var format:SaveFormat = .pdf
    @State private var editedName:String = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fields at the top
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Name").font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextMuted"))
                        TextField("Document name", text: $editedName).font(.system(size: 16)).padding(14)
                            .background(Color("Background")).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("Hairline"), lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format").font(.system(size: 13, weight: .medium)).foregroundColor(Color("TextMuted"))
                        Picker("Format", selection: $format) {
                            Text("PDF").tag(SaveFormat.pdf)
                            Text("JPEG").tag(SaveFormat.jpeg)
                        }.pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 12)

                Spacer()

                // Save button pinned flush to the bottom
                Button { onSave(resolvedName, format); dismiss() } label: {
                    Group {
                        if isSaving { ProgressView().tint(.white) }
                        else { Text("Save to ScanHonest").font(.system(size: 17, weight: .semibold)).foregroundColor(.white) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color("PrimaryGreen")).cornerRadius(28)
                }
                .padding(.horizontal, 24)
                .disabled(isSaving)
            }
            .background(Color("Surface"))
            .navigationTitle("Save Document").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Cancel") { dismiss() }.foregroundColor(Color("TextMuted")) } }
            .onAppear { editedName = suggestedName.isEmpty ? "Scan_\(Date().formatted(date: .abbreviated, time: .omitted))" : suggestedName }
        }
    }
    private var resolvedName:String { editedName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? suggestedName : editedName }
}

extension UIImage {
    func portraitDocumentThumbnail()->Data? {
        let targetRatio:CGFloat=0.77; let thumbSize=CGSize(width:300,height:390)
        let srcW=size.width,srcH=size.height
        let cropRect:CGRect
        if srcH>0,(srcW/srcH)>targetRatio { let w=srcH*targetRatio; cropRect=CGRect(x:(srcW-w)/2,y:0,width:w,height:srcH) }
        else { let h=srcH>0 ? srcW/targetRatio:srcW; cropRect=CGRect(x:0,y:0,width:srcW,height:min(h,srcH)) }
        let s=scale
        guard let cg=cgImage?.cropping(to:CGRect(x:cropRect.minX*s,y:cropRect.minY*s,width:cropRect.width*s,height:cropRect.height*s)) else { return jpegData(compressionQuality:0.7) }
        return UIGraphicsImageRenderer(size:thumbSize).image{_ in UIImage(cgImage:cg,scale:s,orientation:imageOrientation).draw(in:CGRect(origin:.zero,size:thumbSize))}.jpegData(compressionQuality:0.75)
    }
    func applyingGrayscale()->UIImage? {
        guard let ci=CIImage(image:self) else{return nil}
        let f=CIFilter(name:"CIColorControls");f?.setValue(ci,forKey:kCIInputImageKey);f?.setValue(0,forKey:kCIInputSaturationKey)
        guard let out=f?.outputImage,let cg=CIContext().createCGImage(out,from:out.extent) else{return nil}
        return UIImage(cgImage:cg,scale:scale,orientation:imageOrientation)
    }
    func applyingBlackAndWhite()->UIImage? {
        guard let ci=CIImage(image:self) else{return nil}
        let f=CIFilter(name:"CIPhotoEffectNoir");f?.setValue(ci,forKey:kCIInputImageKey)
        guard let out=f?.outputImage,let cg=CIContext().createCGImage(out,from:out.extent) else{return nil}
        return UIImage(cgImage:cg,scale:scale,orientation:imageOrientation)
    }
    // FIX #1: use the same tone-curve pipeline as the capture path.
    // Old code used CIColorControls contrast+brightness which brightened text
    // along with paper, making it look faded. The tone-curve approach anchors
    // the black point so ink stays dark while paper lifts to white.
    func applyingAutoEnhance() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        // Apply tone curve matching DocumentEnhancementParams at mid-ISO (200-800)
        guard let toneFilter = CIFilter(name: "CIToneCurve") else { return nil }
        toneFilter.setValue(ci, forKey: kCIInputImageKey)
        toneFilter.setValue(CIVector(x: 0,    y: 0),    forKey: "inputPoint0")
        toneFilter.setValue(CIVector(x: 0.17, y: 0),    forKey: "inputPoint1")
        toneFilter.setValue(CIVector(x: 0.55, y: 0.46), forKey: "inputPoint2")
        toneFilter.setValue(CIVector(x: 0.92, y: 1.0),  forKey: "inputPoint3")
        toneFilter.setValue(CIVector(x: 1.0,  y: 1.0),  forKey: "inputPoint4")
        guard let toned = toneFilter.outputImage else { return nil }
        // Apply contrast on top to widen ink-to-paper separation
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorFilter.setValue(toned,  forKey: kCIInputImageKey)
        colorFilter.setValue(1.25,   forKey: kCIInputContrastKey)
        colorFilter.setValue(0,      forKey: kCIInputBrightnessKey)
        colorFilter.setValue(1.0,    forKey: kCIInputSaturationKey)
        guard let out = colorFilter.outputImage,
              let cg  = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
    func rotated(by degrees:CGFloat)->UIImage? {
        let rad=degrees * .pi/180
        var s=CGRect(origin:.zero,size:size).applying(CGAffineTransform(rotationAngle:rad)).size
        s.width=floor(s.width);s.height=floor(s.height)
        UIGraphicsBeginImageContextWithOptions(s,false,scale)
        guard let ctx=UIGraphicsGetCurrentContext() else{return nil}
        ctx.translateBy(x:s.width/2,y:s.height/2);ctx.rotate(by:rad)
        draw(in:CGRect(x:-size.width/2,y:-size.height/2,width:size.width,height:size.height))
        let result=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext()
        return result
    }
}

#Preview {
    ScanReviewView(images:[],isPresented:.constant(true),onSave:{_ in})
        .environmentObject(StoreKitManager()).environmentObject(ScanLimitManager())
}
