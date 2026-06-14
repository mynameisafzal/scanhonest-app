// DocumentOverlayView.swift
//
// Full-border document overlay with curved edge support.
//
// Straight-line mode (default):
//   Draws a closed quad through [TL, TR, BR, BL] with straight lines.
//   Used when VNDetectRectanglesRequest is active (iOS <16).
//
// Curved mode:
//   When edgePoints are provided (from VNDocumentObservation on iOS 16+),
//   the overlay traces the actual document boundary including page curl,
//   staple bulge, and fold distortions using a smooth bezier spline.
//   This makes the green overlay visually conform to the curved paper edge.
//
// The key fix for the stapled-page problem:
//   A stapled page has a curved inner edge (the binding creates a 3D bow).
//   The old overlay connected TL→TR with a straight line that cut across
//   the curve, making the overlay appear not to match the page.
//   The new overlay traces the actual segmentation contour so the green
//   line follows the paper edge exactly — including the curve.

import UIKit
import Vision

// MARK: - DocumentEdgePoints
//
// Carries the intermediate contour points along each edge of the document.
// Populated from VNDocumentObservation's normalised path on iOS 16+.
// When nil, the overlay falls back to straight-line quad drawing.

struct DocumentEdgePoints {
    /// Points along the top edge, left-to-right, Vision normalised coords.
    var top:    [CGPoint]
    /// Points along the right edge, top-to-bottom.
    var right:  [CGPoint]
    /// Points along the bottom edge, right-to-left.
    var bottom: [CGPoint]
    /// Points along the left edge, bottom-to-top.
    var left:   [CGPoint]

    /// True if any edge has meaningful curvature (max deviation from straight > threshold).
    var hasCurvature: Bool {
        let threshold: CGFloat = 0.015  // 1.5% of normalised width — ~6 pt on 390pt screen
        return [top, right, bottom, left].contains { edge in
            guard edge.count >= 3 else { return false }
            guard let first = edge.first, let last = edge.last else { return false }
            // Max perpendicular distance from the straight line first→last
            let maxDev = edge.dropFirst().dropLast().map { pt in
                perpendicularDistance(pt, from: first, to: last)
            }.max() ?? 0
            return maxDev > threshold
        }
    }

    private func perpendicularDistance(_ p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x; let dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dx * (a.y - p.y) - (a.x - p.x) * dy) / len
    }
}

// MARK: - DocumentOverlayView

final class DocumentOverlayView: UIView {

    // MARK: Design tokens

    private let kBorderColorFlat   = UIColor(red: 0.322, green: 0.718, blue: 0.533, alpha: 1) // #52B788 — straight
    private let kBorderColorCurved = UIColor(red: 0.455, green: 0.776, blue: 0.616, alpha: 1) // #74C69D — curved (brighter to signal curl)
    private let kLineWidth:         CGFloat = 3.0
    private let kCurvedLineWidth:   CGFloat = 2.5  // slightly thinner on curved paths — cleaner
    private let kGlowRadius:        CGFloat = 8
    private let kFadeInDuration:    Double  = 0.20
    private let kAnimDuration:      Double  = 0.10

    // MARK: Layers

    private let borderLayer = CAShapeLayer()
    private let maskLayer   = CAShapeLayer()

    // MARK: State

    private var isVisible  = false
    private var isLocked   = false
    private var isCurved   = false   // true when drawing a bezier spline overlay

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        maskLayer.fillRule  = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.40).cgColor
        maskLayer.opacity   = 0
        layer.addSublayer(maskLayer)

        borderLayer.fillColor   = UIColor.clear.cgColor
        borderLayer.strokeColor = kBorderColorFlat.cgColor
        borderLayer.lineWidth   = kLineWidth
        borderLayer.lineCap     = .round
        borderLayer.lineJoin    = .round
        borderLayer.opacity     = 0
        borderLayer.shadowColor   = kBorderColorFlat.cgColor
        borderLayer.shadowRadius  = kGlowRadius
        borderLayer.shadowOpacity = 0
        borderLayer.shadowOffset  = .zero
        borderLayer.masksToBounds = false
        layer.addSublayer(borderLayer)
    }

    // MARK: - Public API

    /// Straight-line quad update — used when no edge curvature data is available.
    func update(corners: [CGPoint], isStable: Bool) {
        update(corners: corners, edgePoints: nil, isStable: isStable)
    }

    /// Full update with optional curved edge points.
    ///
    /// - Parameters:
    ///   - corners:    [TL, TR, BR, BL] in layer space — always required.
    ///   - edgePoints: Intermediate contour points per edge in layer space.
    ///                 When non-nil and hasCurvature == true, draws a bezier spline.
    ///   - isStable:   Whether the detection has been stable long enough for glow.
    func update(corners: [CGPoint], edgePoints: DocumentEdgePoints?, isStable: Bool) {
        guard !isLocked, corners.count == 4 else { return }

        let curved = edgePoints?.hasCurvature == true
        isCurved = curved

        CATransaction.begin()
        CATransaction.setAnimationDuration(kAnimDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        let borderPath: UIBezierPath
        if curved, let ep = edgePoints {
            borderPath = buildCurvedPath(corners: corners, edgePoints: ep)
            borderLayer.strokeColor = kBorderColorCurved.cgColor
            borderLayer.shadowColor = kBorderColorCurved.cgColor
            borderLayer.lineWidth   = kCurvedLineWidth
            // Dashed line on curved edges — visually distinguishes "adaptive" mode
            // and hints to the user that a curved/stapled page was detected.
            borderLayer.lineDashPattern = [NSNumber(value: 8), NSNumber(value: 4)]
        } else {
            borderPath = buildStraightPath(corners: corners)
            borderLayer.strokeColor = kBorderColorFlat.cgColor
            borderLayer.shadowColor = kBorderColorFlat.cgColor
            borderLayer.lineWidth   = kLineWidth
            borderLayer.lineDashPattern = nil
        }

        borderLayer.path = borderPath.cgPath

        let mask = UIBezierPath(rect: bounds)
        mask.append(borderPath)
        maskLayer.path = mask.cgPath

        let targetGlow: Float = isStable ? 0.85 : 0.0
        if borderLayer.shadowOpacity != targetGlow {
            borderLayer.shadowOpacity = targetGlow
        }

        CATransaction.commit()

        if !isVisible { fadeIn() }
    }

    func lock() {
        guard !isLocked else { return }
        isLocked = true
        borderLayer.shadowOpacity = 1.0
        maskLayer.opacity = 0.55
    }

    func unlock() {
        isLocked = false
        isCurved = false
        hideImmediate()
    }

    // MARK: - Path builders

    /// Straight-line closed quad — fast path for flat documents.
    private func buildStraightPath(corners: [CGPoint]) -> UIBezierPath {
        let tl = corners[0], tr = corners[1]
        let br = corners[2], bl = corners[3]
        let p = UIBezierPath()
        p.move(to: tl)
        p.addLine(to: tr)
        p.addLine(to: br)
        p.addLine(to: bl)
        p.close()
        return p
    }

    /// Catmull-Rom spline through the actual document contour points.
    /// This traces the real paper edge including page curl and staple bulge.
    ///
    /// Algorithm: Catmull-Rom → Bezier conversion.
    /// Each segment [P1, P2] uses P0 and P3 as phantom control points:
    ///   cp1 = P1 + (P2 - P0) / 6
    ///   cp2 = P2 - (P3 - P1) / 6
    /// This produces a smooth C1-continuous spline that passes exactly through
    /// every detected contour point — the green line hugs the paper edge.
    private func buildCurvedPath(corners: [CGPoint],
                                  edgePoints: DocumentEdgePoints) -> UIBezierPath {
        // Assemble the full contour in winding order: top → right → bottom → left
        var contour: [CGPoint] = []
        contour.append(corners[0])            // TL
        contour.append(contentsOf: edgePoints.top)
        contour.append(corners[1])            // TR
        contour.append(contentsOf: edgePoints.right)
        contour.append(corners[2])            // BR
        contour.append(contentsOf: edgePoints.bottom)
        contour.append(corners[3])            // BL
        contour.append(contentsOf: edgePoints.left)

        guard contour.count >= 3 else { return buildStraightPath(corners: corners) }

        let p = UIBezierPath()
        p.move(to: contour[0])

        let n = contour.count
        for i in 0..<n {
            let p0 = contour[(i - 1 + n) % n]
            let p1 = contour[i]
            let p2 = contour[(i + 1) % n]
            let p3 = contour[(i + 2) % n]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            p.addCurve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        p.close()
        return p
    }

    // MARK: - Visibility

    private func fadeIn() {
        isVisible = true
        let animator = UIViewPropertyAnimator(duration: kFadeInDuration, curve: .easeOut) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(self.kFadeInDuration)
            if self.borderLayer.opacity < 0.5 { self.borderLayer.opacity = 1.0 }
            if self.maskLayer.opacity   < 0.5 { self.maskLayer.opacity   = 1.0 }
            CATransaction.commit()
        }
        animator.startAnimation()
    }

    func fadeOut() {
        guard isVisible else { return }
        isVisible = false
        for l in [borderLayer, maskLayer] {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.toValue = Float(0.0)
            anim.duration = 0.28
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            l.add(anim, forKey: "fadeOut")
            l.opacity = 0.0
        }
        borderLayer.shadowOpacity = 0
    }

    private func hideImmediate() {
        isVisible = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderLayer.opacity       = 0
        maskLayer.opacity         = 0
        borderLayer.shadowOpacity = 0
        CATransaction.commit()
    }
}
