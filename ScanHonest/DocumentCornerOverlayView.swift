// DocumentCornerOverlayView.swift
//
// Four independent L-bracket CAShapeLayers that replace the single full-quad
// bounding box drawn by CameraOverlayCoordinator.
//
// Why this eliminates flicker
// ────────────────────────────
// The old design cleared and re-drew one continuous path on the main thread
// every Vision frame (~20 fps). Any frame-to-frame variation in the returned
// VNRectangleObservation — even sub-pixel noise — caused the entire quad to
// redraw visibly. Two additional failure modes made it worse:
//   • The implicit CALayer animation for `path` fires a 250ms dissolve that
//     overlaps the next redraw, creating a "ghost" effect.
//   • Vision coordinates vary ±2-4 px per frame even on a static document.
//
// This implementation eliminates all three root causes:
//   1. Four SEPARATE L-bracket layers — each path segment is short and cheap;
//      the human eye tracks corners, not edges, so tiny edge variations are invisible.
//   2. Low-pass spatial smoothing (lerp) — raw Vision coordinates are blended
//      toward the running smoothed position each frame. High-frequency noise is
//      attenuated before it ever reaches the layer.
//   3. Movement threshold — if the smoothed corners moved less than `moveThreshold`
//      points since the last draw, the path update is skipped entirely. This stops
//      sub-pixel redraws and avoids triggering implicit animations.
//   4. CATransaction.setDisableActions(true) — suppresses the implicit path-change
//      animation on the layer so updates are instant when they do happen.
//   5. Graceful fade-out — when Vision stops detecting for `fadeOutFrames` frames,
//      the brackets cross-fade to opacity 0 instead of instantly vanishing.
//
// Thread contract: all public methods must be called on the main thread.

import UIKit
import Vision

// MARK: - DocumentCornerOverlayView

final class DocumentCornerOverlayView: UIView {

    // MARK: - Configuration

    struct Config {
        /// Length of each L-bracket arm (points).
        var bracketLength:  CGFloat = 28
        /// Stroke width.
        var lineWidth:      CGFloat = 4.5
        /// SH.accent — matches shutter button idle colour.
        var strokeColor:    UIColor = UIColor(red: 0.455, green: 0.776, blue: 0.616, alpha: 1)
        /// Glow radius for the shadow halo around each bracket.
        var glowRadius:     CGFloat = 8
        /// Glow opacity (0–1).
        var glowOpacity:    Float   = 0.90
        /// Interior fill alpha — very subtle tint inside the document quad.
        var fillAlpha:      CGFloat = 0.07
        /// Low-pass smoothing factor.  0 = frozen, 1 = no smoothing (raw Vision coords).
        /// 0.25 means each frame moves 25% of the remaining distance to the target.
        var smoothingAlpha: CGFloat = 0.28
        /// Minimum corner displacement (pts) required to trigger a path update.
        /// Keeps micro-jitter from causing sub-pixel redraws.
        var moveThreshold:  CGFloat = 1.8
        /// Consecutive Vision frames with no detection before the fade-out starts.
        var fadeOutFrames:  Int     = 5
        /// Fade-in duration (seconds).
        var fadeInDuration:  Double = 0.18
        /// Fade-out duration (seconds).
        var fadeOutDuration: Double = 0.28
    }

    var config = Config()

    // MARK: - Private layers

    private let topLeftLayer     = CAShapeLayer()
    private let topRightLayer    = CAShapeLayer()
    private let bottomRightLayer = CAShapeLayer()
    private let bottomLeftLayer  = CAShapeLayer()
    /// Subtle quad fill behind the brackets.
    private let fillLayer        = CAShapeLayer()

    /// Ordered [TL, TR, BR, BL] — matches the corner index convention used throughout.
    private var bracketLayers: [CAShapeLayer] {
        [topLeftLayer, topRightLayer, bottomRightLayer, bottomLeftLayer]
    }

    // MARK: - Smoothing state (main thread only)

    /// Running low-pass-filtered corner positions [TL, TR, BR, BL].
    /// `nil` while no document has been seen this session.
    private var smoothedCorners: [CGPoint]? = nil

    /// Number of consecutive Vision frames that returned no detection.
    private var noDetectionFrameCount = 0

    /// When `true` the view ignores all `update(with:in:)` calls — used during
    /// the shutter-tap → photo-processing window so the brackets don't move.
    private(set) var isFrozen = false

    /// Tracks whether the brackets are currently visible to avoid redundant fade calls.
    private var isVisible = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // Fill layer sits below brackets
        fillLayer.strokeColor = UIColor.clear.cgColor
        fillLayer.fillColor   = config.strokeColor.withAlphaComponent(config.fillAlpha).cgColor
        fillLayer.opacity     = 0
        layer.addSublayer(fillLayer)

        // Bracket layers
        for l in bracketLayers {
            l.fillColor   = UIColor.clear.cgColor
            l.strokeColor = config.strokeColor.cgColor
            l.lineWidth   = config.lineWidth
            l.lineCap     = .round
            l.lineJoin    = .round
            l.opacity     = 0
            // Glow halo — shadowPath is not set explicitly so Core Animation derives
            // it from the rendered stroke, which is correct for L-shaped paths.
            l.shadowColor   = config.strokeColor.cgColor
            l.shadowRadius  = config.glowRadius
            l.shadowOpacity = config.glowOpacity
            l.shadowOffset  = .zero
            // Must stay false; the shadow extends outside the layer bounds.
            l.masksToBounds = false
            layer.addSublayer(l)
        }
    }

    // MARK: - Public API

    /// Feed a new Vision observation (or `nil`) every frame.
    ///
    /// - Parameters:
    ///   - observation: The latest `VNRectangleObservation`, or `nil` when Vision
    ///     found no document in this frame.
    ///   - bounds: The coordinate space to map into (typically `view.bounds`).
    func update(with observation: VNRectangleObservation?, in bounds: CGRect) {
        guard !isFrozen else { return }

        guard let obs = observation else {
            noDetectionFrameCount += 1
            if noDetectionFrameCount >= config.fadeOutFrames {
                fadeOut()
            }
            return
        }

        noDetectionFrameCount = 0

        // ── Convert Vision normalised coords → UIKit points ──────────────────
        // Vision: y = 0 at bottom-left.  UIKit: y = 0 at top-left.
        let w = bounds.width, h = bounds.height
        func convert(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * w, y: (1.0 - p.y) * h)
        }

        let rawCorners: [CGPoint] = [
            convert(obs.topLeft),
            convert(obs.topRight),
            convert(obs.bottomRight),
            convert(obs.bottomLeft),
        ]

        // ── Low-pass spatial smoothing ────────────────────────────────────────
        // Each frame we lerp the previous smoothed position toward the new raw
        // coordinates.  High-frequency noise (Vision ±2–4 px jitter on a static
        // document) is attenuated before it reaches the layer paths.
        let next = lerp(current: smoothedCorners, toward: rawCorners, alpha: config.smoothingAlpha)

        // ── Movement threshold ────────────────────────────────────────────────
        // Skip the redraw if the corners barely moved — sub-pixel changes are
        // invisible to the user but do trigger implicit layer animations.
        if let prev = smoothedCorners,
           maxDisplacement(from: prev, to: next) < config.moveThreshold {
            return
        }

        smoothedCorners = next
        applyPaths(corners: next)

        if !isVisible { fadeIn() }
    }

    /// Lock the overlay at its current position.
    /// Called when the shutter fires; the frozen brackets serve as a capture
    /// confirmation indicator while the photo is being processed.
    func freeze() {
        isFrozen = true
        // Current opacity intentionally preserved — brackets stay on screen.
    }

    /// Resume live updates.  Called when the scanner returns to `.scanning`.
    func unfreeze() {
        isFrozen              = false
        smoothedCorners       = nil     // start fresh from next observation
        noDetectionFrameCount = 0
        fadeOut(immediate: true)        // clear old brackets instantly
    }

    // MARK: - Path construction

    /// Builds four L-bracket paths and updates the layers.
    /// Called on the main thread only; `CATransaction.setDisableActions(true)`
    /// prevents the implicit 250ms path-change animation.
    private func applyPaths(corners: [CGPoint]) {
        let tl  = corners[0]
        let tr  = corners[1]
        let br  = corners[2]
        let bl  = corners[3]
        let len = config.bracketLength

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // ── Top-left: arm extends DOWN then RIGHT ─────────────────────────────
        let tlPath = UIBezierPath()
        tlPath.move(to:    CGPoint(x: tl.x,       y: tl.y + len))
        tlPath.addLine(to: CGPoint(x: tl.x,       y: tl.y))
        tlPath.addLine(to: CGPoint(x: tl.x + len, y: tl.y))
        topLeftLayer.path = tlPath.cgPath

        // ── Top-right: arm extends LEFT then DOWN ─────────────────────────────
        let trPath = UIBezierPath()
        trPath.move(to:    CGPoint(x: tr.x - len, y: tr.y))
        trPath.addLine(to: CGPoint(x: tr.x,       y: tr.y))
        trPath.addLine(to: CGPoint(x: tr.x,       y: tr.y + len))
        topRightLayer.path = trPath.cgPath

        // ── Bottom-right: arm extends UP then LEFT ────────────────────────────
        let brPath = UIBezierPath()
        brPath.move(to:    CGPoint(x: br.x,       y: br.y - len))
        brPath.addLine(to: CGPoint(x: br.x,       y: br.y))
        brPath.addLine(to: CGPoint(x: br.x - len, y: br.y))
        bottomRightLayer.path = brPath.cgPath

        // ── Bottom-left: arm extends RIGHT then UP ────────────────────────────
        let blPath = UIBezierPath()
        blPath.move(to:    CGPoint(x: bl.x + len, y: bl.y))
        blPath.addLine(to: CGPoint(x: bl.x,       y: bl.y))
        blPath.addLine(to: CGPoint(x: bl.x,       y: bl.y - len))
        bottomLeftLayer.path = blPath.cgPath

        // ── Fill quad ─────────────────────────────────────────────────────────
        let fillPath = UIBezierPath()
        fillPath.move(to:    tl)
        fillPath.addLine(to: tr)
        fillPath.addLine(to: br)
        fillPath.addLine(to: bl)
        fillPath.close()
        fillLayer.path = fillPath.cgPath

        CATransaction.commit()
    }

    // MARK: - Fade transitions

    private func fadeIn() {
        guard !isVisible else { return }
        isVisible = true
        setOpacity(1.0, duration: config.fadeInDuration)
    }

    private func fadeOut(immediate: Bool = false) {
        guard isVisible || immediate else { return }
        isVisible = false
        if immediate {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for l in bracketLayers + [fillLayer] { l.opacity = 0 }
            CATransaction.commit()
        } else {
            setOpacity(0.0, duration: config.fadeOutDuration)
        }
    }

    private func setOpacity(_ opacity: Float, duration: Double) {
        for l in bracketLayers + [fillLayer] {
            let anim        = CABasicAnimation(keyPath: "opacity")
            anim.toValue    = opacity
            anim.duration   = duration
            anim.fillMode   = .forwards
            anim.isRemovedOnCompletion = false
            l.add(anim, forKey: "opacity_\(opacity)")
            l.opacity = opacity
        }
    }

    // MARK: - Maths helpers

    /// Linear interpolation toward `new` at `alpha` per frame.
    /// If `current` is nil (first detection) the raw coords are returned unchanged.
    private func lerp(current: [CGPoint]?, toward new: [CGPoint], alpha: CGFloat) -> [CGPoint] {
        guard let cur = current else { return new }
        return zip(cur, new).map { c, n in
            CGPoint(x: c.x + (n.x - c.x) * alpha,
                    y: c.y + (n.y - c.y) * alpha)
        }
    }

    /// Returns the maximum Euclidean distance between corresponding corner pairs.
    private func maxDisplacement(from a: [CGPoint], to b: [CGPoint]) -> CGFloat {
        zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }
}
