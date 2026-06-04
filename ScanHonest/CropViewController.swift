// CropViewController.swift
// Production-grade UIKit crop + perspective-correction screen, wrapped for SwiftUI.
//
// Component map:
//   LoupeView              — magnifying-glass overlay (shows under-finger pixel detail)
//   CropOverlayView        — CAShapeLayer-based quad overlay with 9 drag handles
//   CropViewController     — UIScrollView zoom host + gesture coordination
//   CropViewControllerRepresentable — SwiftUI bridge

import UIKit
import SwiftUI

// MARK: - LoupeView
//
// A circular magnifier that renders a zoomed-in tile of the source image
// centred on `focusPoint` (in the overlay view's coordinate space).

final class LoupeView: UIView {

    var image:            UIImage?
    var imageDisplayRect = CGRect.zero   // in overlay (parent) view coordinates
    var focusPoint       = CGPoint.zero  // in overlay (parent) view coordinates

    private let magnification: CGFloat = 2.8

    override var isOpaque: Bool { get { false } set {} }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let img = image,
              imageDisplayRect.width > 0, imageDisplayRect.height > 0 else { return }

        ctx.saveGState()
        UIBezierPath(ovalIn: bounds).addClip()

        // Normalised position of the focus point within the image
        let norm = GeometryEngine.viewToNormalized(focusPoint, in: imageDisplayRect)

        // Fraction of the image shown inside the loupe
        let winW = 1.0 / magnification
        let winH = winW * (img.size.height / max(img.size.width, 1))

        // Source rect in image-point space
        let srcX = (norm.x - winW / 2) * img.size.width
        let srcY = (norm.y - winH / 2) * img.size.height

        // Scale source tile to fill the loupe bounds
        let scaleX = bounds.width  / (winW * img.size.width)
        let scaleY = bounds.height / (winH * img.size.height)
        let drawRect = CGRect(
            x: -srcX * scaleX,   y: -srcY * scaleY,
            width:  img.size.width  * scaleX,
            height: img.size.height * scaleY
        )
        img.draw(in: drawRect)
        ctx.restoreGState()

        // Outer ring
        UIColor.white.withAlphaComponent(0.90).setStroke()
        let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3; ring.stroke()

        // Cross-hair
        UIColor.white.withAlphaComponent(0.75).setStroke()
        let ch = UIBezierPath(); ch.lineWidth = 1.0
        ch.move(to: CGPoint(x: bounds.midX - 7, y: bounds.midY))
        ch.addLine(to: CGPoint(x: bounds.midX + 7, y: bounds.midY))
        ch.move(to: CGPoint(x: bounds.midX, y: bounds.midY - 7))
        ch.addLine(to: CGPoint(x: bounds.midX, y: bounds.midY + 7))
        ch.stroke()
    }
}

// MARK: - CropOverlayViewDelegate

protocol CropOverlayViewDelegate: AnyObject {
    func cropOverlayDidBeginEditing()
    func cropOverlayDidEndEditing()
}

// MARK: - CropOverlayView
//
// Renders a semi-transparent mask outside the crop quad, a quad border,
// a rule-of-thirds grid, and 9 drag handles (4 corners, 4 mid-edges, 1 centre).
//
// Geometry:
//   • `quad`             — normalised 0…1 in image space; the authoritative state.
//   • `imageDisplayRect` — where the image is rendered in THIS view's coordinates;
//                          updated by CropViewController on every scroll/zoom event.
//   • Handle positions   — derived each frame from quad + imageDisplayRect.
//
// Hit-testing:
//   hitTest returns `self` only when the touch is within `kHandleTouchR` pt of a handle.
//   All other touches fall through to the UIScrollView underneath (zoom/pan).

final class CropOverlayView: UIView {

    // MARK: Public state
    var quad = Quadrilateral.inset(by: 0.03) { didSet { refresh() } }
    var imageDisplayRect = CGRect.zero       { didSet { refresh() } }
    weak var delegate: CropOverlayViewDelegate?

    // MARK: Appearance constants
    private let kHandleRadius:  CGFloat = 11
    private let kHandleTouchR:  CGFloat = 30   // generous touch target
    private let kLineW:         CGFloat = 1.5
    private let kActiveLineW:   CGFloat = 2.5
    private let kSnapDist:      CGFloat = 10   // pt — snap to image edge
    private let kInactive  = UIColor.white
    private let kActive    = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1.0)

    // MARK: CAShapeLayers (all drawing in GPU-composited layers → 60 fps)
    private let maskLayer   = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let gridLayer   = CAShapeLayer()
    private var handleLayers = [CAShapeLayer]()   // 9 layers, one per handle

    // MARK: Loupe
    private let loupeSize: CGFloat = 90
    private lazy var loupe: LoupeView = {
        let v = LoupeView(frame: CGRect(x: 0, y: 0, width: loupeSize, height: loupeSize))
        v.isHidden = true
        return v
    }()

    // MARK: Handle positions (view-space, recomputed each refresh)
    // Index 0-3: corners TL, TR, BR, BL
    // Index 4-7: mid-edges Top, Right, Bottom, Left
    // Index   8: centre
    private var handlePositions = [CGPoint](repeating: .zero, count: 9)

    // MARK: Gesture state
    private var activeIdx         = -1             // -1 = none active
    private var dragStartQuad     = Quadrilateral.unit
    private var dragStartLocation = CGPoint.zero
    private var didSnapEdge       = false

    private let impact    = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()

    // MARK: - Init

    override init(frame: CGRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        backgroundColor        = .clear
        isOpaque               = false
        isMultipleTouchEnabled = false

        // Mask: even-odd fill cuts the crop window out of the dark overlay
        maskLayer.fillRule  = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        layer.addSublayer(maskLayer)

        borderLayer.fillColor   = UIColor.clear.cgColor
        borderLayer.strokeColor = kInactive.cgColor
        borderLayer.lineWidth   = kLineW
        layer.addSublayer(borderLayer)

        gridLayer.fillColor   = UIColor.clear.cgColor
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.30).cgColor
        gridLayer.lineWidth   = 0.5
        layer.addSublayer(gridLayer)

        for _ in 0..<9 {
            let l = CAShapeLayer()
            l.fillColor   = kInactive.cgColor
            l.strokeColor = UIColor.clear.cgColor
            layer.addSublayer(l)
            handleLayers.append(l)
        }

        addSubview(loupe)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        impact.prepare(); selection.prepare()
    }

    // MARK: - Hit-test: only consume touches near a handle

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard imageDisplayRect != .zero else { return nil }
        for pos in handlePositions {
            if hypot(pos.x - point.x, pos.y - point.y) < kHandleTouchR { return self }
        }
        return nil   // pass through to UIScrollView
    }

    // MARK: - Layout

    override func layoutSubviews() { super.layoutSubviews(); refresh() }

    private func refresh() {
        guard imageDisplayRect != .zero else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit layer animations
        computeHandlePositions()
        drawMask(); drawBorder(); drawGrid(); drawHandles()
        CATransaction.commit()
    }

    // MARK: - Handle position computation

    private func computeHandlePositions() {
        let r = imageDisplayRect
        let c = quad.corners.map { GeometryEngine.normalizedToView($0, in: r) }
        handlePositions = [
            c[0], c[1], c[2], c[3],                                        // 0-3 corners
            mid(c[0], c[1]), mid(c[1], c[2]),                               // 4 top, 5 right
            mid(c[2], c[3]), mid(c[3], c[0]),                               // 6 bottom, 7 left
            CGPoint(x: (c[0].x+c[1].x+c[2].x+c[3].x)/4,                  // 8 centre
                    y: (c[0].y+c[1].y+c[2].y+c[3].y)/4),
        ]
    }

    // MARK: - Layer drawing (UIBezierPath → CAShapeLayer.path → GPU compositing)

    private func drawMask() {
        let full = UIBezierPath(rect: bounds)
        let hole = UIBezierPath()
        let p    = handlePositions
        hole.move(to: p[0]); hole.addLine(to: p[1])
        hole.addLine(to: p[2]); hole.addLine(to: p[3]); hole.close()
        full.append(hole)        // evenOdd rule cuts hole in the mask
        maskLayer.path = full.cgPath
    }

    private func drawBorder() {
        let path = UIBezierPath()
        let p    = handlePositions
        path.move(to: p[0]); path.addLine(to: p[1])
        path.addLine(to: p[2]); path.addLine(to: p[3]); path.close()
        borderLayer.path        = path.cgPath
        let active              = activeIdx >= 0
        borderLayer.strokeColor = (active ? kActive : kInactive).cgColor
        borderLayer.lineWidth   = active ? kActiveLineW : kLineW
    }

    private func drawGrid() {
        let p    = handlePositions
        let path = UIBezierPath()
        for i in 1...2 {
            let t   = CGFloat(i) / 3
            path.move(to: lerp(p[0], p[1], t: t)); path.addLine(to: lerp(p[3], p[2], t: t))
            path.move(to: lerp(p[0], p[3], t: t)); path.addLine(to: lerp(p[1], p[2], t: t))
        }
        gridLayer.path = path.cgPath
    }

    private func drawHandles() {
        for i in 0..<9 {
            let pos   = handlePositions[i]
            let l     = handleLayers[i]
            let isAct = (activeIdx == i)
            let r:     CGFloat
            let color: UIColor

            switch i {
            case 0...3:   // corners — largest
                r     = kHandleRadius
                color = isAct ? kActive : kInactive
            case 4...7:   // midpoints — medium
                r     = kHandleRadius * 0.65
                color = isAct ? kActive : kInactive.withAlphaComponent(0.80)
            default:      // centre — small
                r     = kHandleRadius * 0.50
                color = kInactive.withAlphaComponent(0.55)
            }

            l.path      = UIBezierPath(
                ovalIn: CGRect(x: pos.x - r, y: pos.y - r, width: r*2, height: r*2)
            ).cgPath
            l.fillColor = color.cgColor
        }
    }

    // MARK: - Pan gesture

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let loc = g.location(in: self)
        switch g.state {
        case .began:
            activeIdx         = nearestHandleIndex(to: loc)
            dragStartQuad     = quad
            dragStartLocation = loc
            didSnapEdge       = false
            impact.prepare(); selection.prepare()
            refresh()
            delegate?.cropOverlayDidBeginEditing()
            showLoupe(at: loc)

        case .changed:
            guard activeIdx >= 0 else { return }
            applyDrag(activeIdx, at: loc)
            moveLoupe(to: loc)

        case .ended, .cancelled:
            impact.impactOccurred()
            activeIdx = -1
            refresh()
            hideLoupe()
            delegate?.cropOverlayDidEndEditing()

        default: break
        }
    }

    private func nearestHandleIndex(to pt: CGPoint) -> Int {
        var best = -1, bestD = CGFloat.infinity
        for i in handlePositions.indices {
            let d = hypot(handlePositions[i].x - pt.x, handlePositions[i].y - pt.y)
            if d < kHandleTouchR && d < bestD { bestD = d; best = i }
        }
        return best
    }

    // MARK: - Drag geometry
    //
    // Corner indices moved per handle:
    //   0-3 (corners)    → one corner
    //   4   (top mid)    → corners 0, 1
    //   5   (right mid)  → corners 1, 2
    //   6   (bottom mid) → corners 2, 3
    //   7   (left mid)   → corners 3, 0
    //   8   (centre)     → all 4 corners (translation)

    private static let handleCorners: [[Int]] = [
        [0], [1], [2], [3],       // corners
        [0,1], [1,2], [2,3], [3,0], // midpoints
        [0,1,2,3],                // centre
    ]

    private func applyDrag(_ idx: Int, at loc: CGPoint) {
        guard imageDisplayRect != .zero, idx >= 0, idx < 9 else { return }
        let r     = imageDisplayRect
        let delta = CGPoint(x: loc.x - dragStartLocation.x,
                            y: loc.y - dragStartLocation.y)
        var newQuad = dragStartQuad

        for ci in Self.handleCorners[idx] {
            let startView = GeometryEngine.normalizedToView(dragStartQuad.corners[ci], in: r)
            var newView   = CGPoint(x: startView.x + delta.x, y: startView.y + delta.y)

            // Snap to image edges when within kSnapDist pt
            let (sx, didSnapX) = snapAxis(newView.x, lo: r.minX, hi: r.maxX)
            let (sy, didSnapY) = snapAxis(newView.y, lo: r.minY, hi: r.maxY)
            newView.x = sx; newView.y = sy
            if (didSnapX || didSnapY) && !didSnapEdge {
                selection.selectionChanged(); didSnapEdge = true
            } else if !didSnapX && !didSnapY { didSnapEdge = false }

            let norm = GeometryEngine.clamp01(GeometryEngine.viewToNormalized(newView, in: r))
            newQuad.setCorner(ci, to: norm)
        }

        // Convexity guard: only commit a valid non-self-intersecting quad
        guard GeometryEngine.isConvex(newQuad) else { return }
        quad = newQuad
    }

    private func snapAxis(_ v: CGFloat, lo: CGFloat, hi: CGFloat) -> (CGFloat, Bool) {
        if abs(v - lo) < kSnapDist { return (lo, true) }
        if abs(v - hi) < kSnapDist { return (hi, true) }
        return (v, false)
    }

    // MARK: - Loupe management

    private func showLoupe(at pt: CGPoint) {
        guard activeIdx >= 0, activeIdx < 8 else { return }  // skip centre handle
        loupe.isHidden = false
        positionLoupe(at: pt)
    }

    private func moveLoupe(to pt: CGPoint) {
        guard !loupe.isHidden else { return }
        loupe.focusPoint = pt
        positionLoupe(at: pt)
        loupe.setNeedsDisplay()
    }

    private func positionLoupe(at pt: CGPoint) {
        let lz = loupeSize
        // Appear above the finger; clamp to view bounds
        var lx = pt.x - lz / 2
        var ly = pt.y - lz - 28
        lx = max(4, min(bounds.width  - lz - 4, lx))
        ly = max(4, min(bounds.height - lz - 4, ly))
        loupe.frame = CGRect(x: lx, y: ly, width: lz, height: lz)
    }

    private func hideLoupe() { loupe.isHidden = true }

    /// Called by CropViewController to keep the loupe image current.
    func setLoupeImage(_ img: UIImage?, displayRect: CGRect) {
        loupe.image            = img
        loupe.imageDisplayRect = displayRect
    }
}

// MARK: - Geometry helpers (file-private)

private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

private func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

// MARK: - CropViewController

final class CropViewController: UIViewController, UIScrollViewDelegate, CropOverlayViewDelegate {

    // MARK: Dependencies
    private let image:   UIImage
    private let onCrop:  (UIImage) -> Void
    private let onClose: () -> Void

    // MARK: Sub-views
    private var scrollView:  UIScrollView!
    private var imageView:   UIImageView!
    private var overlayView: CropOverlayView!

    // MARK: Layout state
    private var hasSetInitialQuad = false

    // MARK: - Init

    init(image: UIImage, onCrop: @escaping (UIImage) -> Void, onClose: @escaping () -> Void) {
        self.image   = image
        self.onCrop  = onCrop
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildScrollView()
        buildOverlay()
        buildHUD()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
        // Set initial quad once, after imageDisplayRect is known
        if !hasSetInitialQuad, overlayView.imageDisplayRect != .zero {
            hasSetInitialQuad       = true
            overlayView.quad        = .inset(by: 0.03)
            print("[CropVC] initial quad set | imageDisplayRect:", overlayView.imageDisplayRect)
        }
    }

    // MARK: - View construction

    private func buildScrollView() {
        scrollView = UIScrollView()
        scrollView.delegate                       = self
        scrollView.minimumZoomScale               = 1.0
        scrollView.maximumZoomScale               = 8.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator   = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor                = .black
        scrollView.bouncesZoom                    = true
        view.addSubview(scrollView)

        imageView             = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
    }

    private func buildOverlay() {
        overlayView                      = CropOverlayView()
        overlayView.delegate             = self
        overlayView.isUserInteractionEnabled = true
        view.addSubview(overlayView)
    }

    private func buildHUD() {
        let cancelBtn = makeBarButton("Cancel", weight: .regular,
                                      color: .white, action: #selector(tappedCancel))
        let titleLbl  = UILabel()
        titleLbl.text          = "Crop"
        titleLbl.font          = .systemFont(ofSize: 17, weight: .semibold)
        titleLbl.textColor     = .white
        titleLbl.textAlignment = .center

        let doneBtn = makeBarButton("Done", weight: .semibold,
                                    color: UIColor(red: 0.20, green: 0.82, blue: 0.44, alpha: 1),
                                    action: #selector(tappedDone))

        let hud = UIView()
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        [cancelBtn, titleLbl, doneBtn].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            hud.addSubview($0)
        }
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hud.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hud.heightAnchor.constraint(equalToConstant: 48),

            cancelBtn.leadingAnchor.constraint(equalTo: hud.leadingAnchor, constant: 16),
            cancelBtn.centerYAnchor.constraint(equalTo: hud.centerYAnchor),

            titleLbl.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            titleLbl.centerYAnchor.constraint(equalTo: hud.centerYAnchor),

            doneBtn.trailingAnchor.constraint(equalTo: hud.trailingAnchor, constant: -16),
            doneBtn.centerYAnchor.constraint(equalTo: hud.centerYAnchor),
        ])

        let hint = UILabel()
        hint.text          = "Drag corners or edges  ·  Pinch to zoom"
        hint.font          = .systemFont(ofSize: 12.5)
        hint.textColor     = UIColor.white.withAlphaComponent(0.45)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    private func makeBarButton(_ title: String, weight: UIFont.Weight,
                                color: UIColor, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: weight)
        b.tintColor = color
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - Layout

    private func updateLayout() {
        let safe   = view.safeAreaInsets
        let hudH:  CGFloat = 48
        let hintH: CGFloat = 36
        let topY   = safe.top + hudH
        let availH = view.bounds.height - topY - hintH - safe.bottom
        let frame  = CGRect(x: 0, y: topY, width: view.bounds.width, height: max(1, availH))

        // Aspect-fit the image inside the available frame
        let fitRect = GeometryEngine.aspectFitRect(imageSize: image.size, in: frame.size)

        scrollView.frame       = frame
        imageView.frame        = CGRect(origin: .zero, size: fitRect.size)
        scrollView.contentSize = fitRect.size

        // Centre content with insets (handles zoomed-out state)
        let inX = max(0, (frame.width  - fitRect.width)  / 2)
        let inY = max(0, (frame.height - fitRect.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: inY, left: inX, bottom: inY, right: inX)

        overlayView.frame = view.bounds
        refreshOverlayRect()
    }

    /// Converts imageView frame → view coordinates and passes to overlay.
    private func refreshOverlayRect() {
        guard imageView != nil else { return }
        let rect = scrollView.convert(imageView.frame, to: view)
        overlayView.imageDisplayRect = rect
        overlayView.setLoupeImage(image, displayRect: rect)
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ sv: UIScrollView) {
        // Re-centre content while zooming
        let inX = max(0, (sv.bounds.width  - sv.contentSize.width)  / 2)
        let inY = max(0, (sv.bounds.height - sv.contentSize.height) / 2)
        sv.contentInset = UIEdgeInsets(top: inY, left: inX, bottom: inY, right: inX)
        refreshOverlayRect()
    }

    func scrollViewDidScroll(_ sv: UIScrollView) { refreshOverlayRect() }

    // MARK: - CropOverlayViewDelegate

    func cropOverlayDidBeginEditing() {}
    func cropOverlayDidEndEditing()   {}

    // MARK: - Actions

    @objc private func tappedCancel() {
        print("[CropVC] Cancelled")
        onClose()
    }

    @objc private func tappedDone() {
        let q = overlayView.quad
        print("[CropVC] Done | normalised quad:", q)
        let result = GeometryEngine.applyPerspectiveCorrection(to: image, quad: q) ?? image
        print("[CropVC] Output size:", result.size)
        onCrop(result)
        onClose()
    }
}

// MARK: - SwiftUI bridge

struct CropViewControllerRepresentable: UIViewControllerRepresentable {

    let image:            UIImage
    @Binding var isPresented: Bool
    let onCrop:           (UIImage) -> Void

    func makeUIViewController(context: Context) -> CropViewController {
        CropViewController(
            image:  image,
            onCrop: { result in
                onCrop(result)
                isPresented = false
            },
            onClose: { isPresented = false }
        )
    }

    func updateUIViewController(_ vc: CropViewController, context: Context) {}
}
