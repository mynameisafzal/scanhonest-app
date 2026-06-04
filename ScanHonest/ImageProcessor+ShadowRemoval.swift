// ImageProcessor+ShadowRemoval.swift
//
// CIImage extensions that implement the document illumination-correction
// pipeline used by ManualCaptureDelegate.
//
// ── Algorithm overview (Division Blending / Background Estimation) ─────────
//
//   1. Estimate the background illumination:
//      Blur the document heavily (radius 21–35 px depending on ISO).
//      A large Gaussian averages out all high-frequency content (text, lines)
//      leaving only the broad, low-frequency lighting gradient — the "shadow map."
//
//   2. Division blend:
//      Result = Original ÷ Illumination
//
//      • White paper under shadow:   0.70 ÷ 0.70 = 1.00  (pure white  ✓)
//      • Evenly-lit white paper:     0.95 ÷ 0.95 = 1.00  (pure white  ✓)
//      • Black text pixel:           0.05 ÷ 0.85 = 0.06  (stays dark  ✓)
//      • Highlight glare:            1.00 ÷ 0.90 = 1.00  (clamped     ✓)
//
//      The division mathematically "cancels out" the uneven illumination while
//      leaving the text signal intact, because ink absorbs the same proportion
//      of ambient light regardless of how bright that ambient light is.
//
//   3. Adaptive aggressiveness (ISO-aware):
//      At high ISO the sensor is noisy. Dividing by a small illumination value
//      can amplify noise from the numerator — especially in very dark shadow
//      regions. A larger blur radius "smooths out" the noise in the denominator
//      and produces a gentler, less artifact-prone result.
//
//      ISO < 200  → radius 21  (aggressive:  clean sensor, push hard)
//      ISO < 800  → radius 27  (moderate:    typical indoor light)
//      ISO ≥ 800  → radius 35  (gentle:      noisy sensor, stay safe)
//
// ── CIDivideBlendMode formula ─────────────────────────────────────────────
//
//   Core Image's CIDivideBlendMode computes:
//       Result = Background ÷ Source
//   where inputBackgroundImage is the dividend and inputImage is the divisor.
//   We pass:
//       inputBackgroundImage = original   ← numerator
//       inputImage           = blurred    ← denominator
//   giving Result = Original ÷ Blurred  ✓

import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Illumination estimation

extension CIImage {

    /// Estimates the document's background illumination by applying a large
    /// Gaussian blur.  `clampedToExtent()` is required to prevent the Gaussian
    /// kernel from producing a dark ring at the image boundary (which would
    /// divide to very high values and blow out the paper edges).
    ///
    /// - Parameter radius: Blur radius in pixels.  Larger values catch broader
    ///   shadow gradients but cost slightly more GPU time.
    func illuminationMap(blurRadius: Double) -> CIImage {
        clampedToExtent()
            .applyingFilter("CIGaussianBlur",
                            parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: extent)
    }

    // MARK: - Division blend

    /// Removes cast shadows via Division Blending.
    ///
    /// Creates a blurred illumination map and divides the original by it so
    /// that all paper regions — whether shadowed or directly lit — normalise
    /// to the same white level while text pixels (which absorb light uniformly)
    /// remain dark.
    ///
    /// - Parameter blurRadius: Controls how aggressively shadows are removed.
    ///   Use `shadowRemoved(iso:)` to pick this automatically.
    /// - Returns: Shadow-free CIImage, or `nil` if `CIDivideBlendMode` is
    ///   unavailable on the current device (extremely unlikely on iOS 8+).
    func shadowRemoved(blurRadius: Double) -> CIImage? {
        let illumination = illuminationMap(blurRadius: blurRadius)

        // CIDivideBlendMode: Result = inputBackgroundImage ÷ inputImage
        //   inputBackgroundImage = self        (original — numerator)
        //   inputImage           = illumination (blurred  — denominator)
        return CIFilter(name: "CIDivideBlendMode", parameters: [
            kCIInputImageKey:       illumination,   // divisor  (bottom of fraction)
            "inputBackgroundImage": self            // dividend (top of fraction)
        ])?.outputImage
    }

    /// ISO-aware wrapper that chooses `blurRadius` automatically.
    ///
    /// High-ISO captures are noisy; a larger blur radius averages the noise into
    /// the illumination estimate so the division doesn't amplify individual noisy
    /// pixels into white speckles.
    ///
    /// | ISO          | Radius | Mode      |
    /// |--------------|--------|-----------|
    /// | < 200        |   21   | Aggressive|
    /// | 200 – 799    |   27   | Moderate  |
    /// | ≥ 800        |   35   | Gentle    |
    func shadowRemoved(iso: Float) -> CIImage? {
        let blurRadius: Double
        switch iso {
        case ..<200:  blurRadius = 21   // ideal — push hard, clean sensor
        case ..<800:  blurRadius = 27   // typical indoor — balanced
        default:      blurRadius = 35   // high ISO — large blur averages noise
        }
        return shadowRemoved(blurRadius: blurRadius)
    }

    // MARK: - Tone correction

    /// Applies a black-point-anchored tone curve, contrast, and a gentle
    /// white-point lift after shadow removal.
    ///
    /// WHY THE OLD VERSION FADED TEXT
    /// The previous implementation applied `CIExposureAdjust` (a linear EV
    /// multiply) which brightens EVERY pixel by the same factor — including the
    /// dark ink. Black text at luminance ~0.06 multiplied by an exposure boost
    /// drifts up to grey, so the page came out looking washed-out / faded.
    ///
    /// THE FIX — a tone curve that:
    ///   • pins the BLACK point: anything at/below `blackPoint` luminance maps to
    ///     pure black, so ink stays crisp and dark (no grey haze).
    ///   • rolls the WHITE point down a touch so the paper saturates to pure
    ///     white instead of light-grey.
    ///   • keeps the midpoint slightly below linear, deepening near-black strokes.
    /// Contrast is then applied on top to widen the ink-to-paper separation.
    ///
    /// - Parameters:
    ///   - contrast:   CIColorControls contrast multiplier (1.0 = unchanged).
    ///   - saturation: CIColorControls saturation (0 = grayscale, 1 = colour).
    ///   - blackPoint: Luminance (0–1) below which everything clamps to black.
    ///                 0.12–0.20 is typical for document ink.
    ///   - whitePoint: Luminance (0–1) at/above which everything clamps to white.
    ///                 0.90–0.96 lifts paper to pure white without clipping detail.
    func documentEnhanced(contrast: Float,
                          saturation: Float,
                          blackPoint: Float,
                          whitePoint: Float) -> CIImage? {
        // ── Stage 1: tone curve — anchor black, lift white ───────────────────
        // Five control points spanning input luminance 0…1. Mapping the low end
        // to 0 keeps text dark; mapping the high end to 1 whitens paper.
        guard let tone = CIFilter(name: "CIToneCurve") else { return nil }
        tone.setValue(self, forKey: kCIInputImageKey)

        let bp = CGFloat(max(0, min(blackPoint, 0.4)))
        let wp = CGFloat(max(0.6, min(whitePoint, 1.0)))
        // Below blackPoint → 0 (pure black ink).
        tone.setValue(CIVector(x: 0,            y: 0),    forKey: "inputPoint0")
        tone.setValue(CIVector(x: bp,           y: 0),    forKey: "inputPoint1")
        // Midtone pulled slightly down to deepen faint strokes.
        tone.setValue(CIVector(x: (bp + wp)/2,  y: 0.46), forKey: "inputPoint2")
        // Above whitePoint → 1 (pure white paper).
        tone.setValue(CIVector(x: wp,           y: 1.0),  forKey: "inputPoint3")
        tone.setValue(CIVector(x: 1.0,          y: 1.0),  forKey: "inputPoint4")
        guard let toned = tone.outputImage else { return nil }

        // ── Stage 2: contrast + saturation ───────────────────────────────────
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorFilter.setValue(toned,      forKey: kCIInputImageKey)
        colorFilter.setValue(contrast,   forKey: kCIInputContrastKey)
        colorFilter.setValue(Float(0),   forKey: kCIInputBrightnessKey)
        colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
        return colorFilter.outputImage
    }

    // MARK: - Denoising (pre-processing)

    /// ISO-aware noise reduction applied BEFORE shadow removal.
    ///
    /// Why before, not after: the shadow division amplifies pixel-level noise
    /// (dividing a noisy dark pixel by a small illumination value → very bright
    /// speckle). Smoothing the noise in the numerator first prevents that.
    ///
    /// `CINoiseReduction` targets sensor chroma/luma noise without blurring
    /// character edges because it operates in a frequency band below the
    /// spatial frequency of ink strokes.
    ///
    /// Only applied at ISO ≥ 400 — below that the sensor is clean enough that
    /// noise reduction would marginally soften fine text.
    func denoised(iso: Float) -> CIImage {
        guard iso >= 400 else { return self }
        guard let filter = CIFilter(name: "CINoiseReduction") else { return self }

        // Scale noise level linearly: 0 at ISO 400, 0.02 at ISO 1600+.
        // Higher values remove more grain but can slightly soften sub-pixel strokes.
        let noiseLevel = Float(min((iso - 400.0) / 1200.0, 1.0)) * 0.02
        filter.setValue(self,        forKey: kCIInputImageKey)
        filter.setValue(noiseLevel,  forKey: "inputNoiseLevel")
        filter.setValue(Float(0.40), forKey: "inputSharpness")   // preserve edge contrast
        return filter.outputImage ?? self
    }

    // MARK: - Luminance sharpening

    /// Sharpens only the luminance channel (text edges) without touching
    /// chroma — prevents coloured text from acquiring fringing artefacts.
    ///
    /// - Parameter amount: Sharpness amount.  0.30–0.50 is appropriate for
    ///   document text; above 0.60 introduces ringing on smooth fills.
    func sharpenedForDocument(amount: Float) -> CIImage? {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return nil }
        filter.setValue(self,   forKey: kCIInputImageKey)
        filter.setValue(amount, forKey: kCIInputSharpnessKey)
        return filter.outputImage
    }
}

// MARK: - ISO-adaptive enhancement parameters

/// Bundles the ISO-adaptive tone/sharpness values used by ManualCaptureDelegate.
struct DocumentEnhancementParams {
    let contrast:   Float
    let saturation: Float   // 0 = B&W, 1 = colour
    let blackPoint: Float   // luminance below which ink clamps to pure black
    let whitePoint: Float   // luminance above which paper clamps to pure white
    let sharpness:  Float

    /// Selects parameters based on the captured ISO and the user's filter choice.
    ///
    /// At low ISO the sensor is clean so we can push contrast, black-point, and
    /// sharpness hard for crisp dark text. At high ISO we ease the black-point
    /// (so sensor noise in shadows isn't crushed into blotches) and soften
    /// sharpness to avoid amplifying grain.
    ///
    /// | ISO      | Contrast | BlackPt | WhitePt | Sharpness |
    /// |----------|----------|---------|---------|-----------|
    /// | < 200    |   1.30   |  0.20   |  0.90   |   0.50    |
    /// | 200–799  |   1.25   |  0.17   |  0.92   |   0.40    |
    /// | ≥ 800    |   1.18   |  0.13   |  0.94   |   0.30    |
    init(iso: Float, filter: ScannerCaptureFilter) {
        let isBW = (filter == .blackWhite)
        saturation = isBW ? 0.0 : 1.0

        switch iso {
        case ..<200:
            contrast = 1.30; blackPoint = 0.20; whitePoint = 0.90; sharpness = 0.50
        case ..<800:
            contrast = 1.25; blackPoint = 0.17; whitePoint = 0.92; sharpness = 0.40
        default:
            contrast = 1.18; blackPoint = 0.13; whitePoint = 0.94; sharpness = 0.30
        }
    }
}
