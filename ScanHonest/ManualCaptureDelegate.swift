// ManualCaptureDelegate.swift
//
// Modular, thread-safe AVCapturePhotoCaptureDelegate for manual document capture.
//
// Responsibilities
// ────────────────
//  • Accepts a frozen VNRectangleObservation injected at init time (set at
//    the exact millisecond the shutter button was pressed).
//  • Extracts a raw CIImage from the AVCapturePhoto without any UIImage
//    round-trip (zero unnecessary decode overhead).
//  • Reads ISO metadata from the photo to choose adaptive shadow-removal
//    aggressiveness before dispatching heavy work off the callback thread.
//  • Runs the full processing pipeline on the caller-supplied serial queue:
//       1. Orient sensor buffer → portrait space
//       2. Normalise extent origin
//       3. CIPerspectiveCorrection (frozen quad)
//       4. Shadow removal (Division Blending via ImageProcessor+ShadowRemoval)
//       5. Tone correction (CIToneCurve black-anchor + CIColorControls contrast)
//       6. Luminance sharpening (CISharpenLuminance)
//       7. Optional B&W (CIPhotoEffectMono)
//       8. Single GPU render (ciContext.createCGImage)
//  • Delivers a typed Result<UIImage, CaptureError> on the main thread.
//  • The AVCapturePhoto object goes out of scope as soon as ciImageFromPhoto()
//    returns — the large pixel buffer is released at that point; downstream
//    code only holds the lightweight CIImage DAG node.
//
// Thread model
// ─────────────
//  • photoOutput(_:didFinishProcessingPhoto:error:) fires on AVFoundation's
//    internal queue.  We snapshot all AVCapturePhoto-derived values there,
//    release the photo object, then dispatch the CPU/GPU work to processingQueue.
//  • processingQueue is a serial .userInitiated queue supplied by the VC so
//    the same queue (and the same CIContext) are reused across all captures.
//  • The completion handler is always called on the main thread.

import AVFoundation
import CoreImage
import Vision
import UIKit

// MARK: - ManualCaptureDelegate

final class ManualCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    // MARK: - Typed error

    enum CaptureError: Error, LocalizedError {
        case photoBufferNil
        case perspectiveCorrectionFailed
        case shadowRemovalFailed
        case enhancementFailed
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .photoBufferNil:              return "Photo buffer was nil or corrupt"
            case .perspectiveCorrectionFailed: return "Perspective correction failed"
            case .shadowRemovalFailed:         return "Shadow removal pipeline failed"
            case .enhancementFailed:           return "Tone/sharpen step failed"
            case .renderFailed:                return "Final GPU render failed"
            }
        }
    }

    // MARK: - Injected dependencies

    /// Geometrically-sorted [TL, TR, BR, BL] corners in Vision normalised space,
    /// captured at the exact shutter-tap moment from CoordinateSmoothingFilter.
    /// Using sorted corners (not raw VNRectangleObservation labels) ensures the
    /// perspective crop matches exactly what the user saw on screen.
    /// `nil` → full-frame oriented crop is returned.
    private let sortedCorners:   [CGPoint]?

    /// Enhancement mode requested by the user.
    private let captureFilter:   ScannerCaptureFilter

    /// Shared CIContext (Metal GPU, high-priority queue, no intermediate caching).
    private let ciContext:       CIContext

    /// Serial queue that runs all Core Image work.
    private let processingQueue: DispatchQueue

    /// Called on the main thread when processing completes (success or failure).
    private let completion: (Result<UIImage, CaptureError>) -> Void

    // MARK: - Init

    init(
        sortedCorners:   [CGPoint]?,
        captureFilter:   ScannerCaptureFilter,
        ciContext:       CIContext,
        processingQueue: DispatchQueue,
        completion:      @escaping (Result<UIImage, CaptureError>) -> Void
    ) {
        self.sortedCorners   = sortedCorners
        self.captureFilter   = captureFilter
        self.ciContext       = ciContext
        self.processingQueue = processingQueue
        self.completion      = completion
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        // ── Snapshot on the AVFoundation thread ──────────────────────────────
        // All values derived from AVCapturePhoto must be read here, before the
        // photo object is released.  After this block we hold only:
        //   • sourceCI     — lightweight lazy CIImage node (no pixel data yet)
        //   • exifOrientation — Int32
        //   • iso          — Float

        guard error == nil else {
            deliver(.failure(.photoBufferNil)); return
        }
        guard let (sourceCI, exifOrientation) = ciImageFromPhoto(photo) else {
            deliver(.failure(.photoBufferNil)); return
        }

        // Extract ISO before the photo goes out of scope.
        let iso = capturedISO(from: photo)

        // photo is released here — the pixel buffer backing sourceCI is still
        // alive because CIImage holds a strong reference to the CVPixelBuffer
        // (BGRA path) or the NSData (compressed path).

        let filter = captureFilter  // capture before leaving main actor

        // ── Dispatch heavy work to the dedicated serial queue ─────────────────
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result = self.runPipeline(
                source:          sourceCI,
                exifOrientation: exifOrientation,
                iso:             iso,
                filter:          filter
            )
            // sourceCI is released here once the pipeline is done — the GPU
            // has already rendered the final CGImage, so the backing buffer
            // is no longer needed.
            self.deliver(result)
        }
    }

    // MARK: - CIImage extraction (no UIImage round-trip)

    /// Extracts a raw CIImage and EXIF orientation from an AVCapturePhoto.
    ///
    /// **BGRA path** (preferred): `CIImage(cvPixelBuffer:)` wraps the buffer
    /// lazily — zero bytes are decoded until the first filter reads them.
    /// Hard-codes EXIF orientation 6 for back-camera portrait captures.
    ///
    /// **Compressed path** (HEIF / JPEG fallback): `CIImage(data:)` streams
    /// the compressed bytes; the embedded EXIF tag is forwarded.
    private func ciImageFromPhoto(_ photo: AVCapturePhoto) -> (CIImage, Int32)? {
        if let pixelBuffer = photo.pixelBuffer {
            // Raw sensor buffer: landscape pixels, portrait by EXIF orientation 6
            return (CIImage(cvPixelBuffer: pixelBuffer), 6)
        }
        guard let data = photo.fileDataRepresentation(),
              let ci   = CIImage(data: data) else { return nil }
        let exif = (ci.properties[kCGImagePropertyOrientation as String] as? Int32) ?? 6
        return (ci, exif)
    }

    // MARK: - ISO extraction

    /// Reads the ISO speed from EXIF metadata embedded in the captured photo.
    /// Falls back to 400 (a reasonable "average indoor" assumption) if absent.
    private func capturedISO(from photo: AVCapturePhoto) -> Float {
        let exifDict  = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let isoRatings = exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int]
        return Float(isoRatings?.first ?? 400)
    }

    // MARK: - Full Core Image pipeline

    /// Runs the complete document-processing chain on the current thread
    /// (expected: processingQueue — never call on the main thread).
    ///
    /// All CIImage steps build a lazy DAG; no GPU work happens until
    /// `ciContext.createCGImage()` at the very end, which fuses the entire
    /// graph into a single Metal kernel invocation.
    private func runPipeline(source: CIImage,
                              exifOrientation: Int32,
                              iso: Float,
                              filter: ScannerCaptureFilter) -> Result<UIImage, CaptureError> {

        // ── Stage 1: Sensor → portrait coordinate space ───────────────────────
        // Vision ran with orientation:.right on the CVPixelBuffer so its normalised
        // coords are already in portrait space.  The sensor buffer is landscape.
        // oriented(forExifOrientation: 6) applies:
        //     x_portrait = y_sensor ,  y_portrait = 1 − x_sensor
        let rotated = source.oriented(forExifOrientation: exifOrientation)

        // ── Stage 2: Normalise extent origin ──────────────────────────────────
        // oriented() shifts the extent origin (e.g. y = −4032 after CW-90°).
        // CIPerspectiveCorrection expects absolute coords inside the extent.
        let shift      = CGAffineTransform(translationX: -rotated.extent.origin.x,
                                           y:            -rotated.extent.origin.y)
        let orientedCI = rotated.transformed(by: shift)

        // ── Stage 3: Perspective correction ───────────────────────────────────
        // Uses geometrically-sorted corners [TL, TR, BR, BL] captured at shutter
        // tap time — these match exactly what the user saw in the overlay, eliminating
        // any mismatch caused by Vision relabelling corners on a tilted phone.
        let cropped: CIImage
        if let corners = sortedCorners, corners.count == 4 {
            let w = orientedCI.extent.width
            let h = orientedCI.extent.height
            func pt(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }

            guard let perspFilter = CIFilter(name: "CIPerspectiveCorrection") else {
                return .failure(.perspectiveCorrectionFailed)
            }
            perspFilter.setValue(orientedCI,         forKey: kCIInputImageKey)
            perspFilter.setValue(pt(corners[0]),     forKey: "inputTopLeft")
            perspFilter.setValue(pt(corners[1]),     forKey: "inputTopRight")
            perspFilter.setValue(pt(corners[2]),     forKey: "inputBottomRight")
            perspFilter.setValue(pt(corners[3]),     forKey: "inputBottomLeft")

            guard let out = perspFilter.outputImage else {
                return .failure(.perspectiveCorrectionFailed)
            }
            cropped = out
        } else {
            cropped = orientedCI   // no detection: full oriented frame
        }

        // .original mode: crop only, no enhancement.
        if filter == .original {
            return render(cropped)
        }

        // ── Stage 4a: Pre-denoising (ISO-aware) ──────────────────────────────
        // Run CINoiseReduction BEFORE shadow removal so the division blending
        // operates on a cleaner signal. At high ISO, sensor noise in the
        // numerator would otherwise amplify into bright speckles after division.
        // No-op below ISO 400 to avoid softening fine text on clean captures.
        let denoised = cropped.denoised(iso: iso)

        // ── Stage 4b: Shadow removal (Division Blending) ──────────────────────
        guard let shadowFree = denoised.shadowRemoved(iso: iso) else {
            return .failure(.shadowRemovalFailed)
        }

        // ── Stages 5 & 6: Tone correction + luminance sharpening ─────────────
        let params = DocumentEnhancementParams(iso: iso, filter: filter)

        guard let toned = shadowFree.documentEnhanced(
            contrast:   params.contrast,
            saturation: params.saturation,
            blackPoint: params.blackPoint,
            whitePoint: params.whitePoint
        ) else { return .failure(.enhancementFailed) }

        guard let sharpened = toned.sharpenedForDocument(amount: params.sharpness) else {
            return .failure(.enhancementFailed)
        }

        // ── Stage 7 (optional): B&W mono ──────────────────────────────────────
        // CIPhotoEffectMono produces a clean, neutral desaturation with no warm
        // bias — appropriate for text documents where accurate tones matter.
        // (The saturation=0 in documentEnhanced already desaturates; this adds
        //  a subtle luminance curve characteristic of a classic B&W print.)
        let finalCI: CIImage
        if filter == .blackWhite {
            finalCI = CIFilter(name: "CIPhotoEffectMono",
                               parameters: [kCIInputImageKey: sharpened])?
                          .outputImage ?? sharpened
        } else {
            finalCI = sharpened
        }

        // ── Single GPU render ──────────────────────────────────────────────────
        return render(finalCI)
    }

    // MARK: - Render helper

    /// Calls `ciContext.createCGImage()` — the single point where all queued
    /// CIImage filter nodes are compiled and dispatched to the Metal GPU.
    /// The shared `ciContext` ensures zero allocation overhead per capture.
    private func render(_ ci: CIImage) -> Result<UIImage, CaptureError> {
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else {
            return .failure(.renderFailed)
        }
        return .success(UIImage(cgImage: cg, scale: 1.0, orientation: .up))
    }

    // MARK: - Delivery

    private func deliver(_ result: Result<UIImage, CaptureError>) {
        // Use Task { @MainActor in } instead of DispatchQueue.main.async.
        // DispatchQueue closures are @Sendable and cannot capture the
        // non-Sendable completion handler in strict concurrency mode.
        let completion = self.completion
        Task { @MainActor in completion(result) }
    }
}
