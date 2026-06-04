// CoordinateSmoothingFilter.swift
//
// Adaptive Exponential Moving Average (EMA) smoothing for document corner tracking.
//
// ── Algorithm ────────────────────────────────────────────────────────────────
//
//   EMA:  smoothed_n = smoothed_(n-1) + α × (raw_n − smoothed_(n-1))
//
//   Unlike the old fixed-weight WMA, α is dynamic:
//     • Fast movement  → α → 0.50  (brackets respond quickly, follow the doc)
//     • Slow movement  → α → 0.12  (brackets are stable, absorb micro-jitter)
//
//   The velocity used for α is the max Euclidean displacement between the
//   previous smoothed corners and the new raw corners (in normalised 0-1 space).
//
// ── Snap-to-Lock ─────────────────────────────────────────────────────────────
//
//   When the smoothed corners have moved less than kSnapThreshold for
//   kSnapFrameCount consecutive frames the filter enters "snapped" state and
//   suppresses all UI updates.  This makes the brackets appear perfectly still
//   when the phone is resting over a static document — no micro-shimmer.
//
//   The first frame that exceeds kSnapThreshold breaks the snap and resumes
//   normal EMA tracking.
//
// ── Stability Detection ───────────────────────────────────────────────────────
//
//   stableFrames counts how many consecutive frames the smoothed position has
//   been below the snap threshold.  After kStableFrameCount (~1 s at 20 fps)
//   isStable becomes true, signalling the overlay to show the glow + pill.
//
// ── Lock (Zero-Latency Shutter) ──────────────────────────────────────────────
//
//   lock() snapshots the current smoothed corners into lockedCorners and blocks
//   all further updates.  This guarantees the perspective-correction crop uses
//   exactly the corners the user saw on screen when they tapped the shutter,
//   not an observation from a frame that arrived later.
//
// Thread contract: @MainActor — called on the main thread from the Vision
//   completion handler dispatch.

import UIKit
import Vision

// MARK: - SmoothedResult

struct SmoothedResult {
    /// EMA-smoothed corner positions in Vision normalised space [TL, TR, BR, BL].
    /// These are geometrically sorted — TL is always the visual top-left corner
    /// regardless of how Vision labels the raw observation.
    let corners: [CGPoint]
    /// True when the position has been stable for ≥ kStableFrameCount frames.
    let isStable: Bool
}

// MARK: - CoordinateSmoothingFilter

@MainActor
final class CoordinateSmoothingFilter {

    // MARK: - EMA configuration

    /// Minimum alpha: used when the document is nearly still.
    private let alphaMin: CGFloat = 0.12

    /// Maximum alpha: used when the document is moving quickly.
    private let alphaMax: CGFloat = 0.50

    /// Raw velocity (normalised, per frame) at which alpha reaches alphaMax.
    private let velocityThreshold: CGFloat = 0.05

    // MARK: - Snap-to-lock / stability configuration
    //
    // Stability is measured as the L2 (Euclidean) distance sum across all 4 corners
    // between consecutive smoothed positions.  This is more meaningful than a pure
    // frame count because it directly represents geometric stability: the document
    // has moved less than ε = kSnapThreshold in total corner displacement.
    //
    // Auto-capture should only fire after the corner set has been stable for
    // ≥ 500 ms at 30 fps = 15 frames. kStableFrameCount drives that gate.

    /// Maximum total L2 corner displacement (normalised) that counts as "still".
    /// Sum of 4 corner distances: 0.008 total ≈ 2 px average per corner at 390 pt.
    private let kSnapThreshold: CGFloat = 0.008

    /// Consecutive "still" frames before snap-lock activates (~100 ms at 30 fps).
    private let kSnapFrameCount = 3

    /// Consecutive frames below kSnapThreshold before isStable → true.
    /// 15 frames × 33 ms = 500 ms — matches the audit's "epsilon stable for >500 ms" requirement.
    private let kStableFrameCount = 15

    // MARK: - State

    /// Running smoothed corners [TL, TR, BR, BL] in Vision normalised space.
    private(set) var currentSmoothed: [CGPoint]? = nil

    /// Consecutive frames the smoothed position has been below kSnapThreshold.
    private var snapFrames   = 0

    /// Consecutive frames below kSnapThreshold (feeds isStable).
    private var stableFrames = 0

    /// True while the display should be frozen (snap-to-lock active).
    private var isSnapped    = false

    /// True once lock() has been called.
    private(set) var isLocked = false

    /// Smoothed corners captured at the exact moment lock() is called.
    /// Used by ManualCaptureDelegate as the definitive crop geometry.
    private(set) var lockedCorners: [CGPoint]? = nil

    // MARK: - Public API

    /// Feed a new set of geometrically-sorted corners (Vision normalised space).
    ///
    /// Returns a `SmoothedResult` when the display should be updated, or `nil`
    /// when the snap-to-lock is active (no visible movement).
    ///
    /// - Parameters:
    ///   - corners: Sorted [TL, TR, BR, BL] in Vision normalised coordinates.
    ///   - referenceWidth: Screen width in points (unused directly — snap threshold
    ///     is expressed in normalised units, which is device-independent).
    func process(_ corners: [CGPoint], referenceWidth: CGFloat) -> SmoothedResult? {
        guard !isLocked, corners.count == 4 else { return nil }

        // ── First detection: seed with raw corners ────────────────────────────
        guard let current = currentSmoothed else {
            currentSmoothed = corners
            snapFrames      = 0
            stableFrames    = 0
            isSnapped       = false
            return SmoothedResult(corners: corners, isStable: false)
        }

        // ── Dynamic alpha based on velocity ───────────────────────────────────
        // Velocity = max displacement between last smoothed position and new raw
        // corners (the "true" speed of the document in normalised space).
        let rawVelocity = zip(current, corners)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .max() ?? 0

        let t     = min(rawVelocity / velocityThreshold, 1.0)
        let alpha = alphaMin + t * (alphaMax - alphaMin)

        // ── EMA ───────────────────────────────────────────────────────────────
        let next: [CGPoint] = zip(current, corners).map { c, n in
            CGPoint(x: c.x + (n.x - c.x) * alpha,
                    y: c.y + (n.y - c.y) * alpha)
        }

        // ── L2 stability check ────────────────────────────────────────────────
        // Sum of Euclidean distances across all 4 corners (not just the max).
        // This is the "total geometric drift" measure: if the entire quad has
        // moved less than kSnapThreshold in aggregate, the document is stable.
        let smoothDelta = zip(current, next)
            .map { hypot($0.x - $1.x, $0.y - $1.y) }
            .reduce(0, +)   // total L2 sum across all 4 corners

        if smoothDelta < kSnapThreshold {
            snapFrames   = min(snapFrames   + 1, kSnapFrameCount)
            stableFrames = min(stableFrames + 1, kStableFrameCount)
        } else {
            // Movement detected — break out of snap state.
            snapFrames   = 0
            stableFrames = 0
            isSnapped    = false
        }

        currentSmoothed = next

        // Once we've been still for kSnapFrameCount frames, freeze the display.
        if snapFrames >= kSnapFrameCount {
            isSnapped = true
            return nil   // suppress UI update — brackets are already locked in place
        }

        return SmoothedResult(corners: next,
                              isStable: stableFrames >= kStableFrameCount)
    }

    /// True when the document has been stable for ≥ kStableFrameCount frames.
    var isStable: Bool { stableFrames >= kStableFrameCount }

    /// Freeze all output and snapshot the current smoothed position.
    /// Call when the shutter fires to guarantee zero-latency coordinate capture.
    func lock() {
        isLocked      = true
        lockedCorners = currentSmoothed
    }

    /// Discard all history and resume processing.  Call when returning to .scanning.
    func reset() {
        isLocked        = false
        currentSmoothed = nil
        lockedCorners   = nil
        snapFrames      = 0
        stableFrames    = 0
        isSnapped       = false
    }
}
