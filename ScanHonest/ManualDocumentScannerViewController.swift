// ManualDocumentScannerViewController.swift
//
// Custom document scanner — AVFoundation + Vision.
// Unlike VNDocumentCameraViewController it NEVER auto-captures;
// the user must tap the shutter button to take a photo.
//
// Architecture: four-state machine
//   .scanning        — live view; Vision runs every frame; overlay tracks freely
//   .manualTriggered — shutter tapped; Vision KILLED; observation frozen; button green
//   .processing      — awaiting AVCapturePhotoCaptureDelegate callback
//   .completed       — image processed; briefly shown before returning to .scanning
//
// Jitter fix:
//   The first action in the .manualTriggered transition is setting isVisionEnabled = false.
//   This kills the Vision request loop on the visionQueue before capturePhoto fires.
//   Any in-flight observation that races to the main thread is dropped by the frozen
//   overlay coordinator — the quad the user saw at tap time is the quad that persists.
//
// Haptic contract:
//   • Tap confirmed  → UIImpactFeedbackGenerator(.light)
//   • Buffer arrives → UIImpactFeedbackGenerator(.heavy)  ← the "real" capture signal

import UIKit
import AVFoundation
import Vision

// MARK: - ScannerState

/// Four non-overlapping phases of a single manual capture cycle.
private enum ScannerState {
    /// Normal live-view.  Vision runs every frame; the overlay updates freely.
    case scanning
    /// Shutter tapped.  Vision killed, observation frozen, button turns green.
    case manualTriggered
    /// AVCapturePhotoCaptureDelegate is active.  UI waits for the image buffer.
    case processing
    /// Image processed.  Held briefly before returning to .scanning.
    case completed
}

// CameraOverlayCoordinator has been removed.
// Document detection overlay is now handled by DocumentCornerOverlayView
// (four independent L-bracket CAShapeLayers with low-pass smoothing).

// MARK: - PaddedLabel

private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width:  s.width  + insets.left + insets.right,
                      height: s.height + insets.top  + insets.bottom)
    }
}

// MARK: - ScannerCaptureFilter

/// Controls which Core Image enhancement stages run after perspective correction.
/// Set on the VC before the first shutter tap; the value is read on the
/// processingQueue and must not change mid-capture.
enum ScannerCaptureFilter {
    /// Full pipeline: luminance balance → exposure normalize → sharpen.
    /// Default for all new documents.
    case enhanced
    /// Same as .enhanced followed by CIPhotoEffectMono desaturation.
    /// Use when the user has selected a B&W scan mode.
    case blackWhite
    /// Perspective correction only — no tone or sharpness changes.
    /// Use when the caller will apply its own post-processing.
    case original
}

// Dedicated CIContext for off-main thumbnail generation (file scope = nonisolated).
private let scannerThumbnailCIContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .priorityRequestLow:   false,
    .cacheIntermediates:   false,
])

private struct UncheckedSendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

private func makeScannerThumbnail(from pb: CVPixelBuffer, targetSize: CGSize) -> UIImage? {
    let ci    = CIImage(cvPixelBuffer: pb).oriented(.right)
    let scale = min(targetSize.width / ci.extent.width,
                    targetSize.height / ci.extent.height)
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cg = scannerThumbnailCIContext.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

// MARK: - ManualDocumentScannerViewController

final class ManualDocumentScannerViewController: UIViewController {

    // MARK: Callbacks
    var onFinish: ([UIImage]) -> Void = { _ in }
    var onCancel: () -> Void          = {}

    // MARK: Scanner state — all transitions via the setter
    private var scannerState: ScannerState = .scanning {
        didSet { applyStateTransition(to: scannerState) }
    }

    // MARK: AVFoundation
    // Owned exclusively by sessionQueue — nonisolated(unsafe) opts out of
    // @MainActor UIViewController isolation for strict-concurrency compliance.
    nonisolated(unsafe) private let session      = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput  = AVCapturePhotoOutput()
    nonisolated(unsafe) private let videoOutput  = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "mds.session", qos: .userInitiated)
    // Elevated to .userInteractive so Vision pre-empts background work and delivers
    // detection results before the next camera frame arrives.
    private let visionQueue  = DispatchQueue(label: "mds.vision",  qos: .userInteractive)

    // MARK: CADisplayLink — 30 fps UI throttle
    // Vision fires at camera frame rate (up to 60 fps). Dispatching a UI update for
    // every frame floods the main thread and causes burst-rendering jitter. The
    // displayLink ticks at 30 fps and consumes the latest buffered observation,
    // decoupling detection rate from render rate.
    private var displayLink: CADisplayLink?

    // Written on visionQueue, read on the display-link (main) thread.
    // NSLock guards the slot; Vision always overwrites the previous pending value
    // so only the freshest observation reaches the overlay.
    private let pendingObsLock                             = NSLock()
    nonisolated(unsafe) private var _pendingObservation:   VNRectangleObservation? = nil
    nonisolated(unsafe) private var _pendingNoDetection:   Bool = false
    /// Stored during setupSession; used to query max photo dimensions on iOS 16+.
    nonisolated(unsafe) private var captureDevice: AVCaptureDevice?

    // MARK: Vision kill-switch
    // Written on the main thread (in applyStateTransition) and read on visionQueue.
    // nonisolated(unsafe) opts out of actor-isolation checking; the documented
    // memory ordering of the state machine (main→dispatch→visionQueue) is the
    // practical safety guarantee — the worst-case race lets one extra Vision frame
    // through, which the frozen overlay coordinator silently discards.
    nonisolated(unsafe) private var isVisionEnabled: Bool = true

    // MARK: Pixel-buffer cache
    private let bufferLock = NSLock()
    nonisolated(unsafe) private var _latestPixelBuffer: CVPixelBuffer?

    /// Portrait aspect ratio (width / height) of the live video frames, used to map
    /// Vision-normalised coordinates onto the `.resizeAspectFill` preview layer.
    /// Updated whenever a new sample buffer arrives. Defaults to 3:4 portrait
    /// (0.75) — the standard `.photo`-preset aspect — until the first frame lands.
    private let aspectLock = NSLock()
    nonisolated(unsafe) private var _videoPortraitAspect: CGFloat = 3.0 / 4.0
    private var videoPortraitAspect: CGFloat {
        aspectLock.lock(); defer { aspectLock.unlock() }
        return _videoPortraitAspect
    }

    private var latestPixelBuffer: CVPixelBuffer? {
        bufferLock.lock(); defer { bufferLock.unlock() }
        return _latestPixelBuffer
    }

    // MARK: Detection debounce
    private var noDetectionTickCount = 0
    private let kNoDetectionGraceTicks = 5

    // MARK: Observation ring-buffer (main thread only)
    private var observationRing: [VNRectangleObservation] = []
    private var frozenObservation: VNRectangleObservation?
    private let kRingCapacity = 5

    // MARK: Haptics
    private let captureHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: CIContext
    // Single shared context — creation allocates a Metal command queue; reusing it
    // eliminates per-capture allocation overhead.
    // .useSoftwareRenderer: false  → always use the GPU (Metal)
    // .priorityRequestLow: false   → schedule on the high-priority GPU queue
    // .cacheIntermediates: false   → one-shot pipeline; don't cache filter outputs
    private lazy var ciContext = CIContext(options: [
        .useSoftwareRenderer:  false,
        .priorityRequestLow:   false,
        .cacheIntermediates:   false,
    ])

    // MARK: Image-processing queue
    // Serial queue dedicated to Core Image work.  Using a named serial queue (not
    // the AVFoundation callback thread) isolates heavy GPU work, keeps backpressure
    // predictable, and prevents AVFoundation from starving on the shared global pool.
    private let processingQueue = DispatchQueue(
        label: "com.scanhonest.imageProcessing",
        qos:   .userInitiated
    )

    // MARK: Mode — set by the SwiftUI bridge before first use
    /// When `true` the VC behaves like `VNDocumentCameraViewController`:
    /// it auto-fires the shutter after `kAutoCaptureTriggerCount` consecutive
    /// stable detections without any user tap.
    var isAutoCapture: Bool = false

    // MARK: Capture filter
    /// Controls the enhancement applied to every captured frame.
    var captureFilter: ScannerCaptureFilter = .enhanced

    // MARK: Flash state
    private var flashEnabled: Bool = false   // false = off, true = auto

    // MARK: Auto-capture tracking (main thread only)
    private var consecutiveDetectionCount = 0
    /// Number of consecutive 30-fps display-link frames a document must be
    /// detected before the shutter fires automatically.
    /// 20 frames × 33 ms = ~0.66 s — gives the user a moment to steady the phone.
    private let kAutoCaptureTriggerCount  = 20

    /// Wall-clock timestamp of the last auto-capture.  Enforces a hard minimum
    /// gap between captures so the user isn't flooded with rapid-fire shots.
    private var lastAutoCaptureDate: Date = .distantPast
    /// Minimum seconds that must elapse between two consecutive auto-captures.
    private let kAutoCaptureMinInterval: TimeInterval = 2.5

    // MARK: Preview
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        return l
    }()

    // MARK: Overlay + smoothing filter
    private let docOverlay      = DocumentOverlayView()
    private let smoothingFilter = CoordinateSmoothingFilter()

    // MARK: Freeze-frame snapshot
    private var freezeSnapshotView: UIImageView?

    // MARK: Captured data
    /// Stores processed page images as compressed JPEG data rather than full
    /// UIImage objects.  A 12 MP scan at 0.85 quality ≈ 1-2 MB vs ~48 MB as
    /// an uncompressed BGRA UIImage.  This keeps 20+ page sessions well within
    /// memory limits and prevents OOM crashes on older devices.
    private var capturedImageData: [Data] = []

    /// Lazily decoded from capturedImageData. The caller (ScanReviewView) never
    /// holds all pages simultaneously, so decoding on-demand is safe.
    private var capturedImages: [UIImage] {
        capturedImageData.compactMap { UIImage(data: $0) }
    }
    private var thumbnailPlaceholders: [Int: UIImageView] = [:]
    private var pendingCaptureIndex: Int = 0
    private(set) var lastCapturedObservation: VNRectangleObservation?

    /// Geometrically-sorted corners (Vision normalised [TL,TR,BR,BL]) captured
    /// at shutter-tap time.  Passed to ManualCaptureDelegate so the crop matches
    /// exactly what the user saw — not a potentially mis-labelled raw observation.
    private var frozenSortedCorners: [CGPoint]? = nil

    /// Holds strong references to in-flight ManualCaptureDelegate instances.
    /// AVFoundation retains delegates internally until the callback completes,
    /// but we also keep a reference here so the completion handler can safely
    /// remove the entry even if AVFoundation's release races with the async work.
    private var activeCaptureDelegates: [ManualCaptureDelegate] = []

    // MARK: UI elements
    private let cancelButton    = UIButton(type: .system)
    private let doneButton      = UIButton(type: .system)
    private let hintLabel       = PaddedLabel()
    private let shutterRing     = UIView()
    private let shutterButton   = UIButton(type: .custom)
    private let thumbnailScroll = UIScrollView()
    private let countLabel      = UILabel()
    // Top pill bar — matches screens.jsx design
    private let topPill         = UIView()
    private let flashButton     = UIButton(type: .custom)
    private let filterButton    = UIButton(type: .custom)

    // Design tokens
    // Design spec (screens.jsx): inner circle = SH.accent (#74C69D) with a glow.
    // .locked is a deeper shade (#52B788) to signal "capture in progress".
    private let kShutterIdle   = UIColor(red: 0.455, green: 0.776, blue: 0.616, alpha: 1) // #74C69D
    private let kShutterLocked = UIColor(red: 0.32,  green: 0.72,  blue: 0.53,  alpha: 1) // #52B788

    private let thumbSize: CGFloat    = 60
    private let thumbSpacing: CGFloat = 8

    // MARK: - Init
    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        configureOutlineLayer()
        setupSession()
        captureHaptic.prepare()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }
        stopDisplayLink()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer.frame  = view.bounds
        docOverlay.frame    = view.bounds
        orientPreviewConnection()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - State machine

    private func applyStateTransition(to state: ScannerState) {
        switch state {

        case .scanning:
            isVisionEnabled = true
            consecutiveDetectionCount = 0
            noDetectionTickCount = 0
            frozenSortedCorners = nil
            smoothingFilter.reset()
            docOverlay.unlock()
            shutterButton.isEnabled = true
            UIView.animate(withDuration: 0.20) {
                self.shutterButton.backgroundColor        = self.kShutterIdle
                self.shutterButton.layer.shadowColor      = self.kShutterIdle.cgColor
                self.shutterButton.layer.shadowOpacity    = 0.55
                self.shutterButton.transform              = .identity
            }
            dismissFreezeFrame()

        case .manualTriggered:
            // ── Step 1: Kill Vision FIRST ──────────────────────────────────────
            // This is the jitter fix. Any captureOutput call that has already
            // entered the method will finish harmlessly; subsequent calls skip
            // Vision entirely. The frozen overlay coordinator discards any
            // residual main-thread dispatches from in-flight frames.
            isVisionEnabled = false

            // ── Step 2: Lock geometry ──────────────────────────────────────────
            frozenObservation = bestBufferedObservation()
            // Snapshot sorted corners from the filter — these are the exact corners
            // the user saw on screen. Fall back to sorting the raw observation if
            // the filter has no history yet.
            if let locked = smoothingFilter.currentSmoothed {
                frozenSortedCorners = locked
            } else if let obs = frozenObservation {
                frozenSortedCorners = sortedCorners(from: obs)
            } else {
                frozenSortedCorners = nil
            }
            // Lock filter and overlay AFTER snapshotting.
            smoothingFilter.lock()
            docOverlay.lock()

            // ── Step 3: Visual state — deeper green "capture in progress" ────
            shutterButton.isEnabled = false
            UIView.animate(withDuration: 0.12) {
                self.shutterButton.transform              = .identity
                self.shutterButton.backgroundColor        = self.kShutterLocked
                self.shutterButton.layer.shadowColor      = self.kShutterLocked.cgColor
                self.shutterButton.layer.shadowOpacity    = 0.70   // brighter glow at capture
            }
            showFreezeFrame()

        case .processing:
            break   // freeze-frame and green button remain in place

        case .completed:
            // Manual mode: short 0.3 s pause so the freeze-frame is visible.
            // Auto-capture mode: longer 1.5 s pause so the user can see the
            // captured result before the scanner re-arms for the next page.
            let resumeDelay: UInt64 = isAutoCapture ? 1_500_000_000 : 300_000_000
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: resumeDelay)
                self?.scannerState = .scanning
            }
        }
    }

    // MARK: - Observation ring-buffer

    private func pushObservation(_ obs: VNRectangleObservation) {
        observationRing.append(obs)
        if observationRing.count > kRingCapacity { observationRing.removeFirst() }
    }

    private func bestBufferedObservation() -> VNRectangleObservation? {
        observationRing.max(by: { $0.confidence < $1.confidence })
    }

    // MARK: - Freeze-frame

    private func showFreezeFrame() {
        guard let pb = latestPixelBuffer else { return }

        let ci = CIImage(cvPixelBuffer: pb).oriented(.right)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return }

        let iv = UIImageView(image: UIImage(cgImage: cg))
        iv.frame         = view.bounds
        iv.contentMode   = .scaleAspectFill
        iv.clipsToBounds = true
        // Insert below all UIView controls but above the CALayer sublayers
        view.insertSubview(iv, at: 0)
        freezeSnapshotView = iv

        // Brief white flash — simulates the physical shutter closing
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.07, animations: { flash.alpha = 0.5 }) { _ in
            UIView.animate(withDuration: 0.16, animations: { flash.alpha = 0 }) { _ in
                flash.removeFromSuperview()
            }
        }
    }

    private func dismissFreezeFrame() {
        guard let iv = freezeSnapshotView else { return }
        freezeSnapshotView = nil
        UIView.animate(withDuration: 0.22, delay: 0.04, options: .curveEaseOut,
                       animations: { iv.alpha = 0 }) { _ in iv.removeFromSuperview() }
    }

    // MARK: - CADisplayLink (30 fps UI throttle)

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        dl.preferredFramesPerSecond = 30   // decouple from camera's 60 fps
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Fires at ~30 fps on the main thread.  Drains the latest pending Vision
    /// observation and pushes it through the smoothing filter → overlay.
    @objc private func displayLinkTick(_ link: CADisplayLink) {
        // Drain the pending slot (take snapshot and clear).
        pendingObsLock.lock()
        let obs          = _pendingObservation
        let noDetection  = _pendingNoDetection
        _pendingObservation  = nil
        _pendingNoDetection  = false
        pendingObsLock.unlock()

        // Nothing new since the last tick — skip.
        guard obs != nil || noDetection else { return }

        if let obs {
            noDetectionTickCount = 0
            pushObservation(obs)
            let sorted  = sortedCorners(from: obs)
            let screenW = view.bounds.width

            if let result = smoothingFilter.process(sorted, referenceWidth: screenW) {
                let layerPts = result.corners.map(visionPointToLayer)
                // Extract curved edge points from VNDocumentObservation (iOS 16+)
                // so the green overlay follows the actual paper boundary including
                // page curl and staple distortion.
                let edgePts  = extractEdgePoints(from: obs, corners: result.corners)
                let layerEdge = edgePts.map { ep -> DocumentEdgePoints in
                    DocumentEdgePoints(
                        top:    ep.top.map(visionPointToLayer),
                        right:  ep.right.map(visionPointToLayer),
                        bottom: ep.bottom.map(visionPointToLayer),
                        left:   ep.left.map(visionPointToLayer)
                    )
                }
                isCurvedDetection = layerEdge?.hasCurvature == true
                docOverlay.update(
                    corners:    layerPts,
                    edgePoints: layerEdge,
                    isStable:   result.isStable || smoothingFilter.isStable
                )
            } else if smoothingFilter.isStable,
                      let last = smoothingFilter.currentSmoothed {
                let layerPts = last.map(visionPointToLayer)
                docOverlay.update(corners: layerPts, isStable: true)
            }

            // Auto-capture
            if isAutoCapture && scannerState == .scanning && obs.confidence >= 0.85 {
                consecutiveDetectionCount += 1
                if consecutiveDetectionCount >= kAutoCaptureTriggerCount {
                    consecutiveDetectionCount = 0
                    let now = Date()
                    if now.timeIntervalSince(lastAutoCaptureDate) >= kAutoCaptureMinInterval {
                        lastAutoCaptureDate = now
                        triggerCapture()
                    }
                }
            } else if isAutoCapture {
                consecutiveDetectionCount = 0
            }
        } else {
            // No detection this tick
            consecutiveDetectionCount = 0
            noDetectionTickCount += 1
            if noDetectionTickCount >= kNoDetectionGraceTicks {
                smoothingFilter.reset()
                docOverlay.fadeOut()
            }
        }

        updateHint(
            documentDetected: obs != nil || noDetectionTickCount < kNoDetectionGraceTicks,
            isCurved: isCurvedDetection
        )
    }

    // Tracks whether the last detection had meaningful curvature
    private var isCurvedDetection = false

    // MARK: - Curved contour extraction
    //
    // On iOS 16+ VNDetectDocumentSegmentationRequest returns a VNDocumentObservation
    // whose normalizedPath contains the full document boundary as a CGPath.
    // We sample that path to get intermediate points along each edge, which
    // DocumentOverlayView uses to draw a bezier spline that follows the actual
    // paper boundary — including page curl, staple bulge, and fold distortions.
    //
    // On iOS <16 we return nil (straight-line overlay used as fallback).

    private func extractEdgePoints(from obs: VNRectangleObservation,
                                    corners: [CGPoint]) -> DocumentEdgePoints? {
        // iOS 17 baseline: VNDetectDocumentSegmentationRequest always available.
        // VNDocumentObservation is not publicly exposed as a Swift type name,
        // so we access normalizedPath via ObjC runtime inspection.

        let nsObs = obs as AnyObject
        guard nsObs.responds(to: NSSelectorFromString("normalizedPath")) else {
            return nil
        }
        guard let path = nsObs.value(forKey: "normalizedPath") as! CGPath? else {
            return nil
        }

        // Collect all contour points by walking the CGPath elements
        var allPoints: [CGPoint] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint:
                allPoints.append(element.pointee.points[0])
            case .addLineToPoint:
                allPoints.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                let cp = element.pointee.points[0]
                let ep = element.pointee.points[1]
                if let last = allPoints.last {
                    for t in stride(from: 0.25, through: 1.0, by: 0.25) {
                        let mt = 1.0 - CGFloat(t)
                        let x = mt*mt*last.x + 2*mt*CGFloat(t)*cp.x + CGFloat(t)*CGFloat(t)*ep.x
                        let y = mt*mt*last.y + 2*mt*CGFloat(t)*cp.y + CGFloat(t)*CGFloat(t)*ep.y
                        allPoints.append(CGPoint(x: x, y: y))
                    }
                }
            case .addCurveToPoint:
                let cp1 = element.pointee.points[0]
                let cp2 = element.pointee.points[1]
                let ep  = element.pointee.points[2]
                if let last = allPoints.last {
                    for t in stride(from: 1.0/6.0, through: 1.0, by: 1.0/6.0) {
                        let mt = 1.0 - CGFloat(t)
                        let x = mt*mt*mt*last.x + 3*mt*mt*CGFloat(t)*cp1.x + 3*mt*CGFloat(t)*CGFloat(t)*cp2.x + CGFloat(t)*CGFloat(t)*CGFloat(t)*ep.x
                        let y = mt*mt*mt*last.y + 3*mt*mt*CGFloat(t)*cp1.y + 3*mt*CGFloat(t)*CGFloat(t)*cp2.y + CGFloat(t)*CGFloat(t)*CGFloat(t)*ep.y
                        allPoints.append(CGPoint(x: x, y: y))
                    }
                }
            case .closeSubpath: break
            @unknown default:  break
            }
        }

        guard allPoints.count >= 4 else { return nil }

        let tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3]

        func closestIndex(_ target: CGPoint) -> Int {
            allPoints.indices.min(by: {
                hypot(allPoints[$0].x - target.x, allPoints[$0].y - target.y) <
                hypot(allPoints[$1].x - target.x, allPoints[$1].y - target.y)
            }) ?? 0
        }

        let iTL = closestIndex(tl)
        let iTR = closestIndex(tr)
        let iBR = closestIndex(br)
        let iBL = closestIndex(bl)

        func slice(from: Int, to: Int) -> [CGPoint] {
            let n = allPoints.count
            if from == to { return [] }
            var pts: [CGPoint] = []
            var i = from
            while i != to { pts.append(allPoints[i]); i = (i + 1) % n }
            return pts.count > 2 ? Array(pts.dropFirst().dropLast()) : []
        }

        return DocumentEdgePoints(
            top:    slice(from: iTL, to: iTR),
            right:  slice(from: iTR, to: iBR),
            bottom: slice(from: iBR, to: iBL),
            left:   slice(from: iBL, to: iTL)
        )
    }

    // MARK: - Vision → layer coordinate mapping

    /// Converts a Vision-normalised point into the exact on-screen preview space.
    /// Vision runs with orientation `.right`, so its points are already in portrait
    /// image space with origin at bottom-left. The preview is `.resizeAspectFill`,
    /// so we map into the fitted video rect and include the crop offsets.
    private func visionPointToLayer(_ vp: CGPoint) -> CGPoint {
        let bounds = previewLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let videoAspect = max(videoPortraitAspect, 0.001) // portrait width / height
        let viewAspect = bounds.width / bounds.height

        let videoSize: CGSize
        if viewAspect > videoAspect {
            let width = bounds.width
            videoSize = CGSize(width: width, height: width / videoAspect)
        } else {
            let height = bounds.height
            videoSize = CGSize(width: height * videoAspect, height: height)
        }

        let origin = CGPoint(
            x: bounds.midX - videoSize.width / 2,
            y: bounds.midY - videoSize.height / 2
        )

        return CGPoint(
            x: origin.x + vp.x * videoSize.width,
            y: origin.y + (1.0 - vp.y) * videoSize.height
        )
    }

    // MARK: - Geometric point sorting (anti-ghosting)

    /// Sorts 4 Vision-normalised corners into stable [TL, TR, BR, BL] order
    /// using sum/difference axes, regardless of how Vision labels them.
    ///
    /// In UIKit space (y = 0 at top):
    ///   TL = min(x + y),  BR = max(x + y)
    ///   TR = min(y − x),  BL = max(y − x)
    ///
    /// Vision coordinates (y = 0 at bottom) are flipped to UIKit space for
    /// sorting, then flipped back so the returned array is still Vision-space.
    ///
    /// This eliminates the "ghosting" where Vision relabels its corners when
    /// the phone tilts, causing a TL bracket to jump to TR.
    func sortedCorners(from obs: VNRectangleObservation) -> [CGPoint] {
        let visionPts = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        // Flip y: Vision y=0-bottom → UIKit y=0-top
        let ui = visionPts.map { CGPoint(x: $0.x, y: 1.0 - $0.y) }

        guard let tl = ui.min(by: { $0.x + $0.y < $1.x + $1.y }),
              let br = ui.max(by: { $0.x + $0.y < $1.x + $1.y }),
              let tr = ui.min(by: { $0.y - $0.x < $1.y - $1.x }),
              let bl = ui.max(by: { $0.y - $0.x < $1.y - $1.x })
        else { return visionPts }

        // Flip back to Vision space
        return [tl, tr, br, bl].map { CGPoint(x: $0.x, y: 1.0 - $0.y) }
    }

    // MARK: - Hint label

    private func updateHint(documentDetected: Bool, isCurved: Bool = false) {
        let text: String
        if !documentDetected {
            text = "Position document in frame"
        } else if isCurved {
            text = "\u{21BA}  Curved page \u{2014} tap to capture"
        } else {
            text = "\u{2713}  Document detected"
        }
        hintLabel.text = text
        UIView.animate(withDuration: 0.15) {
            if documentDetected {
                self.hintLabel.backgroundColor = UIColor(red: 0.455, green: 0.776, blue: 0.616, alpha: 0.95)
                self.hintLabel.textColor       = UIColor(red: 0.11,  green: 0.26,  blue: 0.20,  alpha: 1)
            } else {
                self.hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.50)
                self.hintLabel.textColor       = .white
            }
        }
    }

    private func updateFlashButtonUI() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let name = flashEnabled ? "bolt.fill" : "bolt.slash.fill"
        flashButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        flashButton.tintColor = .white
    }

    private func updateFilterButtonUI() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        flashButton.tintColor = .white
        let (icon, label): (String, String)
        switch captureFilter {
        case .enhanced:   icon = "wand.and.stars";        label = "AUTO"
        case .original:   icon = "circle.fill";           label = "COLOR"
        case .blackWhite: icon = "circle.lefthalf.filled"; label = "B&W"
        }
        filterButton.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
        filterButton.setTitle(" \(label)", for: .normal)
        filterButton.tintColor  = .white
        filterButton.setTitleColor(.white, for: .normal)
    }

    // MARK: - Session setup

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video, position: .back),
                let input  = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else { self.session.commitConfiguration(); return }

            self.session.addInput(input)
            self.captureDevice = device   // stored for maxPhotoDimensions query

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                // iOS 17 baseline: maxPhotoDimensions is always available
                if let maxDims = device.activeFormat.supportedMaxPhotoDimensions.last {
                    self.photoOutput.maxPhotoDimensions = maxDims
                }
            }

            self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    // MARK: - Photo settings

    /// Returns a fully-optimised AVCapturePhotoSettings for manual document capture.
    ///
    /// Format priority:
    ///   1. kCVPixelFormatType_32BGRA — uncompressed pixel buffer; zero decode
    ///      overhead in didFinishProcessingPhoto since no HEIF/JPEG decompression.
    ///   2. Default (HEIF on A-series, JPEG on older) — safe fallback.
    ///
    /// Speed config:
    ///   • .photoQualityPrioritization = .speed — fires the ISP immediately;
    ///     avoids the 200–500 ms multi-frame bracketing that .balanced/.quality add.
    ///   • .isHighResolutionPhotoEnabled = true — full-sensor pixels for accurate
    ///     perspective correction (low-res crops introduce sub-pixel quad error).
    ///   • .flashMode = .off — pre-flash sequencing adds ~100 ms and causes
    ///     the frozen quad to misalign with the lit-flash image.
    private func preparePhotoSettings() -> AVCapturePhotoSettings {
        // Prefer BGRA: eliminates JPEG/HEIF decode in the delegate, shaving
        // 20–80 ms off the time between buffer delivery and perspective crop.
        let bgraType: OSType = kCVPixelFormatType_32BGRA
        let settings: AVCapturePhotoSettings

        if photoOutput.availablePhotoPixelFormatTypes.contains(bgraType) {
            settings = AVCapturePhotoSettings(
                format: [kCVPixelBufferPixelFormatTypeKey as String: bgraType]
            )
        } else {
            settings = AVCapturePhotoSettings()
        }

        // .speed: shutter fires immediately; ISP defers noise-reduction to a
        // background pass rather than blocking the capture pipeline.
        settings.photoQualityPrioritization = .speed

        // iOS 17 baseline: maxPhotoDimensions always available
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        // Flash: user-controlled toggle.  When off (default) we skip the pre-flash
        // entirely — the ~100 ms strobe occurs during the shutter-lag window and
        // causes quad jitter.  When on, .auto lets the ISP decide.
        settings.flashMode = flashEnabled ? .auto : .off

        return settings
    }

    // MARK: - Orientation

    private func orientPreviewConnection() {
        guard let conn = previewLayer.connection else { return }
        // iOS 17 baseline: videoRotationAngle always available
        if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
    }

    // MARK: - Outline layer

    private func configureOutlineLayer() {
        docOverlay.frame                    = view.bounds
        docOverlay.isUserInteractionEnabled = false
        view.addSubview(docOverlay)
    }

    // MARK: - UI construction
    //
    // Layout (matches screens.jsx):
    //
    //  ┌──────────────────────────────────────────┐
    //  │  [topPill: × cancel | ⚡ flash | ✨ filter] │  ← translucent pill
    //  │                                            │
    //  │   [hintLabel — guidance pill]              │
    //  │          (centre of frame)                 │
    //  │                                            │
    //  │  [thumbnails]  [ ● shutter ]  [count/done] │  ← bottom bar
    //  └──────────────────────────────────────────┘

    private func buildUI() {
        view.layer.addSublayer(previewLayer)

        // ── Top pill bar ─────────────────────────────────────────────────────
        // Design: background rgba(0,0,0,0.5), borderRadius 22, height 44
        topPill.backgroundColor     = UIColor.black.withAlphaComponent(0.50)
        topPill.layer.cornerRadius  = 22
        topPill.layer.masksToBounds = true
        topPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topPill)

        // Cancel (×) — left side of pill
        let xCfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cancelButton.setImage(UIImage(systemName: "xmark", withConfiguration: xCfg), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        topPill.addSubview(cancelButton)

        // Flash toggle (⚡) — centre-left of pill
        flashButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        topPill.addSubview(flashButton)

        // Filter cycle — centre-right of pill
        filterButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        filterButton.addTarget(self, action: #selector(filterTapped), for: .touchUpInside)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        topPill.addSubview(filterButton)

        // Initialise button appearances
        updateFlashButtonUI()
        updateFilterButtonUI()

        // Done — white bottom-right pill, visible after first capture
        doneButton.setImage(nil, for: .normal)
        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(UIColor(red: 0.106, green: 0.263, blue: 0.196, alpha: 1), for: .normal)
        doneButton.titleLabel?.font   = .systemFont(ofSize: 14, weight: .semibold)
        doneButton.backgroundColor    = .white
        doneButton.layer.cornerRadius = 24
        doneButton.isHidden           = true
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)

        // Hint label (guidance pill — bottom of viewfinder)
        hintLabel.text                = "Position document in frame"
        hintLabel.textColor           = .white
        hintLabel.font                = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textAlignment       = .center
        hintLabel.backgroundColor     = UIColor(red: 0.455, green: 0.776, blue: 0.616, alpha: 0.95) // #74C69D95
        hintLabel.textColor           = UIColor(red: 0.11, green: 0.26, blue: 0.20, alpha: 1)       // SH.primary dark
        hintLabel.layer.cornerRadius  = 14
        hintLabel.layer.masksToBounds = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // Shutter ring (outer white border, 76×76)
        shutterRing.layer.borderColor  = UIColor.white.cgColor
        shutterRing.layer.borderWidth  = 4
        shutterRing.layer.cornerRadius = 38
        shutterRing.backgroundColor    = .clear
        shutterRing.isUserInteractionEnabled = false
        shutterRing.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterRing)

        // Shutter button (inner circle — SH.accent #74C69D, inset 6px = 64×64 diameter)
        // glow: shadowRadius 12, opacity 0.55
        shutterButton.backgroundColor    = kShutterIdle
        shutterButton.layer.cornerRadius = 32
        shutterButton.layer.shadowColor   = kShutterIdle.cgColor
        shutterButton.layer.shadowRadius  = 12
        shutterButton.layer.shadowOpacity = 0.55
        shutterButton.layer.shadowOffset  = .zero
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(shutterDown),      for: .touchDown)
        shutterButton.addTarget(self, action: #selector(shutterTapped),    for: .touchUpInside)
        shutterButton.addTarget(self, action: #selector(shutterCancelled), for: [.touchUpOutside, .touchCancel])
        view.addSubview(shutterButton)

        // Thumbnail scroll (left of shutter)
        thumbnailScroll.showsHorizontalScrollIndicator = false
        thumbnailScroll.isUserInteractionEnabled = true
        thumbnailScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailScroll)

        // Page count label — top-right inside the pill
        countLabel.text          = "Page 1"
        countLabel.textColor     = .white
        countLabel.font          = .systemFont(ofSize: 14, weight: .semibold)
        countLabel.textAlignment = .center
        countLabel.isHidden      = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        topPill.addSubview(countLabel)

        NSLayoutConstraint.activate([
            // Top pill
            topPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            topPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            topPill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            topPill.heightAnchor.constraint(equalToConstant: 44),

            // Cancel inside pill
            cancelButton.leadingAnchor.constraint(equalTo: topPill.leadingAnchor, constant: 6),
            cancelButton.centerYAnchor.constraint(equalTo: topPill.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            // Flash — centred slightly left of pill centre
            flashButton.centerXAnchor.constraint(equalTo: topPill.centerXAnchor, constant: -40),
            flashButton.centerYAnchor.constraint(equalTo: topPill.centerYAnchor),
            flashButton.heightAnchor.constraint(equalToConstant: 44),

            // Filter — centred slightly right of pill centre
            filterButton.centerXAnchor.constraint(equalTo: topPill.centerXAnchor, constant: 40),
            filterButton.centerYAnchor.constraint(equalTo: topPill.centerYAnchor),
            filterButton.heightAnchor.constraint(equalToConstant: 44),

            // Page count — top-right inside pill
            countLabel.trailingAnchor.constraint(equalTo: topPill.trailingAnchor, constant: -16),
            countLabel.centerYAnchor.constraint(equalTo: topPill.centerYAnchor),

            // Done button — bottom-right pill
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            doneButton.centerYAnchor.constraint(equalTo: shutterRing.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 74),
            doneButton.heightAnchor.constraint(equalToConstant: 38),

            // Hint label (guidance pill, above bottom bar)
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -118),

            // Shutter (76×76 ring, 64×64 button)
            shutterRing.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterRing.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterRing.widthAnchor.constraint(equalToConstant: 76),
            shutterRing.heightAnchor.constraint(equalToConstant: 76),

            shutterButton.centerXAnchor.constraint(equalTo: shutterRing.centerXAnchor),
            shutterButton.centerYAnchor.constraint(equalTo: shutterRing.centerYAnchor),
            shutterButton.widthAnchor.constraint(equalToConstant: 64),
            shutterButton.heightAnchor.constraint(equalToConstant: 64),

            // Thumbnail scroll (left side of bottom bar)
            thumbnailScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            thumbnailScroll.trailingAnchor.constraint(equalTo: shutterRing.leadingAnchor, constant: -12),
            thumbnailScroll.centerYAnchor.constraint(equalTo: shutterRing.centerYAnchor),
            thumbnailScroll.heightAnchor.constraint(equalToConstant: 66),
        ])
    }
}

// MARK: - Shutter interaction

extension ManualDocumentScannerViewController {

    @objc private func shutterDown() {
        // Design annotation: "shutter: scale 0.92 · haptic medium"
        UIView.animate(withDuration: 0.06) {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc private func shutterCancelled() {
        // Only revert if we are still in .scanning — after a confirmed tap the
        // button is owned by the .manualTriggered state transition.
        guard scannerState == .scanning else { return }
        UIView.animate(withDuration: 0.10) {
            self.shutterButton.transform       = .identity
            self.shutterButton.backgroundColor = self.kShutterIdle
        }
    }

    @objc private func shutterTapped() {
        // Delegate to the shared trigger — identical behaviour for manual and auto.
        triggerCapture()
    }

    // MARK: - Flash & filter controls

    @objc private func flashTapped() {
        flashEnabled.toggle()
        updateFlashButtonUI()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func filterTapped() {
        // Cycle: enhanced → original → blackWhite → enhanced
        switch captureFilter {
        case .enhanced:   captureFilter = .original
        case .original:   captureFilter = .blackWhite
        case .blackWhite: captureFilter = .enhanced
        }
        updateFilterButtonUI()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Done / Cancel

    @objc private func doneTapped() {
        guard !capturedImageData.isEmpty else { return }
        sessionQueue.async { self.session.stopRunning() }
        onFinish(capturedImages)
    }

    @objc private func cancelTapped() {
        sessionQueue.async { self.session.stopRunning() }
        onCancel()
    }

    // MARK: - Shared capture trigger
    //
    // Called by both the manual shutter tap and the auto-capture timer.
    // Encapsulating here prevents code duplication and ensures identical
    // state transitions regardless of how capture was initiated.

    func triggerCapture() {
        guard scannerState == .scanning else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        pendingCaptureIndex = capturedImageData.count
        let pendingIndex    = pendingCaptureIndex

        if let pb = latestPixelBuffer {
            let thumbTarget = CGSize(width: thumbSize * 2, height: thumbSize * 3)
            let pixelBuffer = UncheckedSendablePixelBuffer(pb)
            processingQueue.async { [weak self] in
                let placeholder = makeScannerThumbnail(from: pixelBuffer.buffer, targetSize: thumbTarget)
                Task { @MainActor [weak self] in
                    self?.insertThumbnail(image: placeholder, atIndex: pendingIndex)
                }
            }
        }

        scannerState = .manualTriggered
        // frozenSortedCorners and frozenObservation are both captured inside
        // applyStateTransition(.manualTriggered) before this line runs.
        let sortedCrn = frozenSortedCorners
        let settings  = preparePhotoSettings()

        weak var weakDelegate: ManualCaptureDelegate?
        let delegate = ManualCaptureDelegate(
            sortedCorners:   sortedCrn,      // geometrically-sorted; matches exact on-screen display
            captureFilter:   captureFilter,
            ciContext:       ciContext,
            processingQueue: processingQueue
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image):
                self.captureHaptic.impactOccurred()
                // Compress immediately — store JPEG data, not the full UIImage.
                // This releases the 48 MB uncompressed buffer right away and keeps
                // memory footprint flat across 20+ page batch sessions.
                if let jpeg = image.jpegData(compressionQuality: 0.88) {
                    self.capturedImageData.append(jpeg)
                }
                self.insertThumbnail(image: image, atIndex: pendingIndex)
                self.doneButton.isHidden     = false
                self.lastCapturedObservation = self.frozenObservation
                self.scannerState = .completed
                self.captureHaptic.prepare()
            case .failure:
                self.scannerState = .scanning
            }
            if let d = weakDelegate {
                self.activeCaptureDelegates.removeAll { $0 === d }
            }
        }
        weakDelegate = delegate
        activeCaptureDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        captureHaptic.prepare()
    }
}

// MARK: - Thumbnail management

extension ManualDocumentScannerViewController {

    private func insertThumbnail(image: UIImage?, atIndex index: Int) {
        if let existing = thumbnailPlaceholders[index] {
            UIView.transition(with: existing, duration: 0.20,
                              options: .transitionCrossDissolve) { existing.image = image }
            return
        }

        let x       = CGFloat(index) * (thumbSize + thumbSpacing)
        let wrapper = UIView(frame: CGRect(x: x, y: 3, width: thumbSize, height: thumbSize))
        wrapper.layer.cornerRadius  = 6
        wrapper.layer.masksToBounds = true
        wrapper.layer.borderColor   = UIColor.white.withAlphaComponent(0.40).cgColor
        wrapper.layer.borderWidth   = 1

        let iv = UIImageView(frame: wrapper.bounds)
        iv.image         = image
        iv.contentMode   = .scaleAspectFill
        iv.clipsToBounds = true
        wrapper.addSubview(iv)

        // Tap to preview the full captured image
        wrapper.tag = index
        wrapper.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(thumbnailTapped(_:)))
        wrapper.addGestureRecognizer(tap)

        thumbnailScroll.addSubview(wrapper)
        thumbnailPlaceholders[index] = iv

        let n      = index + 1
        let totalW = CGFloat(n) * (thumbSize + thumbSpacing) - thumbSpacing
        thumbnailScroll.contentSize = CGSize(width: totalW, height: 66)
        thumbnailScroll.scrollRectToVisible(wrapper.frame, animated: true)

        countLabel.text = "Page \(n)"
    }

    @objc private func thumbnailTapped(_ gesture: UITapGestureRecognizer) {
        guard let wrapper = gesture.view else { return }
        let index = wrapper.tag
        guard index < capturedImageData.count,
              let image = UIImage(data: capturedImageData[index]) else { return }
        showImagePreview(image)
    }

    /// Shows a full-screen, dismissible preview of the captured image.
    /// Tap anywhere or the × button to dismiss. Does not alter the scanner UI.
    private func showImagePreview(_ image: UIImage) {
        // Dim backdrop
        let backdrop = UIView(frame: view.bounds)
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        backdrop.alpha = 0
        view.addSubview(backdrop)

        // Image view — centred, fitted, preserving aspect ratio
        let iv = UIImageView(image: image)
        iv.contentMode   = .scaleAspectFit
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 12),
            iv.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -12),
            iv.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 60),
            iv.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -100),
        ])

        // Close button — top-right corner
        let closeBtn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        closeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        closeBtn.tintColor          = .white
        closeBtn.backgroundColor    = UIColor.white.withAlphaComponent(0.18)
        closeBtn.layer.cornerRadius = 20
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: backdrop.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -16),
            closeBtn.widthAnchor.constraint(equalToConstant: 40),
            closeBtn.heightAnchor.constraint(equalToConstant: 40),
        ])

        let dismiss: () -> Void = {
            UIView.animate(withDuration: 0.22, animations: { backdrop.alpha = 0 }) { _ in
                backdrop.removeFromSuperview()
            }
        }
        closeBtn.addAction(UIAction { _ in dismiss() }, for: .touchUpInside)

        // Tap anywhere on backdrop to dismiss
        let tap = UITapGestureRecognizer()
        tap.addTarget(self, action: #selector(previewBackdropTapped))
        backdrop.addGestureRecognizer(tap)
        // Store dismiss closure on the backdrop view via associated object workaround:
        // simpler — just use the tag to identify the backdrop
        backdrop.tag = 9999

        UIView.animate(withDuration: 0.22) { backdrop.alpha = 1 }
    }

    @objc private func previewBackdropTapped(_ gesture: UITapGestureRecognizer) {
        guard let backdrop = gesture.view, backdrop.tag == 9999 else { return }
        UIView.animate(withDuration: 0.22, animations: { backdrop.alpha = 0 }) { _ in
            backdrop.removeFromSuperview()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
//
// Runs Vision on every frame to detect a document rectangle.
// NEVER triggers a capture — detection only drives the overlay and hint text.
//
// isVisionEnabled is the kill-switch: set to false by the .manualTriggered
// transition so this loop is effectively paused during the shutter-lag window.

extension ManualDocumentScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Cache unconditionally — the freeze-frame mechanism needs the latest buffer
        // even after Vision is disabled.
        bufferLock.lock()
        _latestPixelBuffer = pixelBuffer
        bufferLock.unlock()

        // Record the portrait aspect ratio of the frame for overlay coordinate
        // mapping. The sensor buffer is landscape, so the displayed PORTRAIT frame
        // aspect (width / height) is the buffer's height / width.
        let bufW = CVPixelBufferGetWidth(pixelBuffer)
        let bufH = CVPixelBufferGetHeight(pixelBuffer)
        if bufW > 0, bufH > 0 {
            aspectLock.lock()
            _videoPortraitAspect = CGFloat(bufH) / CGFloat(bufW)
            aspectLock.unlock()
        }

        // ── Vision kill-switch ──────────────────────────────────────────────────
        // isVisionEnabled is set to false in applyStateTransition(.manualTriggered)
        // before capturePhoto fires. This eliminates the 100–200 ms shutter-lag
        // window during which new observations would otherwise race against the
        // frozen geometry and cause the bounding box to jitter.
        guard isVisionEnabled else { return }

        // iOS 17 baseline: VNDetectDocumentSegmentationRequest always available.
        // Neural-network model trained on documents — handles low-contrast,
        // cluttered backgrounds, curved/stapled pages better than the
        // geometric VNDetectRectanglesRequest fallback.
        let request: VNRequest
        let bufferHandler = { [weak self] (req: VNRequest, _: Error?) in
            guard let self else { return }
            let obs = req.results?.first as? VNRectangleObservation
            self.pendingObsLock.lock()
            self._pendingObservation  = obs
            self._pendingNoDetection  = (obs == nil)
            self.pendingObsLock.unlock()
        }

        let docReq = VNDetectDocumentSegmentationRequest(completionHandler: bufferHandler)
        request = docReq

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([request])
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
//
// The VC no longer conforms to AVCapturePhotoCaptureDelegate directly.
// Each shutter tap creates a ManualCaptureDelegate instance (see ManualCaptureDelegate.swift)
// that owns the frozen observation and runs the full shadow-removal + enhancement
// pipeline independently.  The VC receives the final UIImage via the completion handler.


// MARK: - SwiftUI bridge

import SwiftUI

struct ManualDocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScan: ([UIImage]) -> Void
    /// When `true` the scanner auto-fires after stable document detection —
    /// same behaviour as `VNDocumentCameraViewController` but with our UI.
    var isAutoCapture: Bool = false
    /// Initial capture filter; the user can change it via the in-camera toggle.
    var captureFilter: ScannerCaptureFilter = .enhanced

    func makeUIViewController(context: Context) -> ManualDocumentScannerViewController {
        let vc = ManualDocumentScannerViewController()
        vc.isAutoCapture = isAutoCapture
        vc.captureFilter = captureFilter
        vc.onFinish = { images in
            Task { @MainActor in onScan(images) }
        }
        vc.onCancel = {
            Task { @MainActor in isPresented = false }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: ManualDocumentScannerViewController,
                                context: Context) {
        uiViewController.isAutoCapture = isAutoCapture
        uiViewController.captureFilter = captureFilter
    }
}
