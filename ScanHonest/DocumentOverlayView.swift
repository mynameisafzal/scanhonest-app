// DocumentOverlayView.swift
//
// Full-border document overlay:
//   • Single CAShapeLayer draws a complete closed quadrilateral along the document edges
//   • fillRule .evenOdd mask dims the area outside the document
//   • Glow on the border layer signals "ready to capture"
//   • Smooth implicit path animation via CATransaction (0.10 s easeOut)

import UIKit

final class DocumentOverlayView: UIView {

    // MARK: - Design tokens

    private let kBorderColor   = UIColor(red: 0.322, green: 0.718, blue: 0.533, alpha: 1) // #52B788
    private let kLineWidth:      CGFloat = 3.0
    private let kGlowRadius:     CGFloat = 8
    private let kFadeInDuration: Double  = 0.20
    private let kAnimDuration:   Double  = 0.10

    // MARK: - Layers

    /// Single layer that draws the full document border (closed quad).
    private let borderLayer = CAShapeLayer()

    /// Dims the area outside the document quad using fillRule .evenOdd.
    private let maskLayer   = CAShapeLayer()

    // MARK: - State

    private var isVisible = false
    private var isLocked  = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        // Mask — semi-transparent dark area outside the document
        maskLayer.fillRule  = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.40).cgColor
        maskLayer.opacity   = 0
        layer.addSublayer(maskLayer)

        // Border — full closed outline following all four document edges
        borderLayer.fillColor   = UIColor.clear.cgColor
        borderLayer.strokeColor = kBorderColor.cgColor
        borderLayer.lineWidth   = kLineWidth
        borderLayer.lineCap     = .round
        borderLayer.lineJoin    = .round
        borderLayer.opacity     = 0
        borderLayer.shadowColor   = kBorderColor.cgColor
        borderLayer.shadowRadius  = kGlowRadius
        borderLayer.shadowOpacity = 0
        borderLayer.shadowOffset  = .zero
        borderLayer.masksToBounds = false
        layer.addSublayer(borderLayer)
    }

    // MARK: - Public API

    /// Update the overlay with new smoothed corners [TL, TR, BR, BL] in layer space.
    func update(corners: [CGPoint], isStable: Bool) {
        guard !isLocked, corners.count == 4 else { return }

        let tl = corners[0], tr = corners[1]
        let br = corners[2], bl = corners[3]

        CATransaction.begin()
        CATransaction.setAnimationDuration(kAnimDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        // ── Border: closed quadrilateral around the document ──────────────────
        let border = UIBezierPath()
        border.move(to:    tl)
        border.addLine(to: tr)
        border.addLine(to: br)
        border.addLine(to: bl)
        border.close()
        borderLayer.path = border.cgPath

        // ── Dimming mask (same quad, punches through the dark fill) ───────────
        let mask = UIBezierPath(rect: bounds)
        mask.append(border)
        maskLayer.path = mask.cgPath

        // ── Glow — same transaction so border + mask always composite together ─
        let targetGlow: Float = isStable ? 0.85 : 0.0
        if borderLayer.shadowOpacity != targetGlow {
            borderLayer.shadowOpacity = targetGlow
        }

        CATransaction.commit()

        if !isVisible { fadeIn() }
    }

    /// Freeze and enhance glow to confirm capture.
    func lock() {
        guard !isLocked else { return }
        isLocked = true
        borderLayer.shadowOpacity = 1.0
        maskLayer.opacity = 0.55
    }

    /// Release lock and hide. Called when returning to .scanning.
    func unlock() {
        isLocked = false
        hideImmediate()
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
        borderLayer.opacity = 0
        maskLayer.opacity   = 0
        borderLayer.shadowOpacity = 0
        CATransaction.commit()
    }
}
