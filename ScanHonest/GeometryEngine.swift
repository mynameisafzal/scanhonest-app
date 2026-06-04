// GeometryEngine.swift
// Pure geometry utilities: coordinate mapping, convexity, perspective correction.
// No UIKit dependencies except CGPoint/CGRect/UIImage.

import CoreImage
import UIKit

// MARK: - Quadrilateral
//
// Four corners of a crop quad in NORMALISED image space (0…1, top-left origin).
// Corner order: topLeft → topRight → bottomRight → bottomLeft  (clockwise on screen).

struct Quadrilateral: Equatable {
    var topLeft:     CGPoint
    var topRight:    CGPoint
    var bottomRight: CGPoint
    var bottomLeft:  CGPoint

    // MARK: Preset factories

    /// Full image bounds — no crop.
    static let unit = Quadrilateral(
        topLeft:     CGPoint(x: 0, y: 0),
        topRight:    CGPoint(x: 1, y: 0),
        bottomRight: CGPoint(x: 1, y: 1),
        bottomLeft:  CGPoint(x: 0, y: 1)
    )

    /// Rect inset by `m` on all four sides (m in 0…0.5).
    static func inset(by m: CGFloat) -> Quadrilateral {
        Quadrilateral(
            topLeft:     CGPoint(x: m,   y: m),
            topRight:    CGPoint(x: 1-m, y: m),
            bottomRight: CGPoint(x: 1-m, y: 1-m),
            bottomLeft:  CGPoint(x: m,   y: 1-m)
        )
    }

    // MARK: Accessors

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    mutating func setCorner(_ index: Int, to point: CGPoint) {
        switch index {
        case 0: topLeft     = point
        case 1: topRight    = point
        case 2: bottomRight = point
        case 3: bottomLeft  = point
        default: break
        }
    }
}

// MARK: - GeometryEngine

enum GeometryEngine {

    // MARK: Aspect-fit rect

    /// CGRect (in `containerSize` coordinate space) where an image of `imageSize`
    /// is displayed when using aspect-fit scaling.
    static func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width  > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width  / imageSize.width,
                        containerSize.height / imageSize.height)
        let w = imageSize.width  * scale
        let h = imageSize.height * scale
        return CGRect(x: (containerSize.width  - w) / 2,
                      y: (containerSize.height - h) / 2,
                      width: w, height: h)
    }

    // MARK: Coordinate mapping

    /// Normalised image point (0…1) → view point inside `rect`.
    static func normalizedToView(_ n: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + n.x * rect.width,
                y: rect.minY + n.y * rect.height)
    }

    /// View point → normalised image point (inverse of normalizedToView).
    static func viewToNormalized(_ pt: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: (pt.x - rect.minX) / rect.width,
                       y: (pt.y - rect.minY) / rect.height)
    }

    /// Clamp both axes of a normalised point to [0, 1].
    static func clamp01(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(1, pt.x)), y: max(0, min(1, pt.y)))
    }

    // MARK: Convexity check
    //
    // Uses cross-product sign consistency: for a convex polygon traversed in a
    // consistent winding order, all consecutive edge cross-products must share sign.

    static func isConvex(_ q: Quadrilateral) -> Bool {
        let pts = q.corners
        var sign: CGFloat = 0
        let n = pts.count
        for i in 0..<n {
            let a = pts[i], b = pts[(i+1) % n], c = pts[(i+2) % n]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-6 { continue }
            if sign == 0 { sign = cross > 0 ? 1 : -1 }
            else if (cross > 0 ? 1 : -1) != sign { return false }
        }
        return true
    }

    // MARK: Perspective correction
    //
    // Takes a NORMALISED quad (0…1 in UIImage point space) and rectifies the image
    // using CIPerspectiveCorrection, returning a top-down rectangular UIImage.
    //
    // Coordinate notes:
    //   UIImage / CGImage → y increases downward (top-left origin).
    //   CIImage            → y increases upward  (bottom-left origin, OpenGL convention).
    // We flip y when converting: ciY = imagePixelHeight - (normY × imagePixelHeight).

    static func applyPerspectiveCorrection(to image: UIImage,
                                            quad: Quadrilateral) -> UIImage? {
        // Flatten to .up orientation so CGImage pixel axes match UIImage display axes.
        let src = image.flattened
        guard let cg = src.cgImage else { return nil }

        let w  = CGFloat(cg.width)
        let h  = CGFloat(cg.height)
        let ci = CIImage(cgImage: cg)

        // Normalised → CIImage pixel space (y-flipped)
        func vec(_ n: CGPoint) -> CIVector {
            CIVector(x: n.x * w, y: h - n.y * h)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci,                 forKey: kCIInputImageKey)
        filter.setValue(vec(quad.topLeft),  forKey: "inputTopLeft")
        filter.setValue(vec(quad.topRight), forKey: "inputTopRight")
        filter.setValue(vec(quad.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vec(quad.bottomLeft),  forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgOut = ctx.createCGImage(output, from: output.extent) else { return nil }

        return UIImage(cgImage: cgOut)
    }
}

// MARK: - UIImage orientation normalisation

extension UIImage {
    /// Returns a copy redrawn at .up orientation so CGImage pixel axes match
    /// the UIImage display axes (required before feeding pixels to CIFilter).
    var flattened: UIImage {
        guard imageOrientation != .up else { return self }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
