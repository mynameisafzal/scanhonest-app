import UIKit
import CoreImage

// MARK: - ScanFilter

enum ScanFilter: String, CaseIterable {
    case original   = "Color"
    case grayscale  = "Grayscale"
    case blackWhite = "B&W"
    case enhanced   = "Enhanced"
}

// MARK: - ScanFilterProcessor
//
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor is set project-wide.
// Marking this enum and its static method nonisolated overrides that
// so Task.detached can call apply(_:to:) freely without a concurrency error.

nonisolated
enum ScanFilterProcessor {
    nonisolated
    static func apply(_ filter: ScanFilter, to image: UIImage) -> UIImage {
        switch filter {
        case .original:    return image
        case .grayscale:   return image.applyingGrayscale()     ?? image
        case .blackWhite:  return image.applyingBlackAndWhite() ?? image
        case .enhanced:    return image.applyingAutoEnhance()   ?? image
        }
    }
}

// MARK: - UIImage filter extensions
//
// Declared in this file (no SwiftUI, no @MainActor types) so they inherit
// nonisolated status from the file context and can be called from
// Task.detached inside ScanFilterProcessor.apply.

extension UIImage {

    func applyingGrayscale() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let f = CIFilter(name: "CIColorControls")
        f?.setValue(ci, forKey: kCIInputImageKey)
        f?.setValue(0,  forKey: kCIInputSaturationKey)
        guard let out = f?.outputImage,
              let cg  = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func applyingBlackAndWhite() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        let f = CIFilter(name: "CIPhotoEffectNoir")
        f?.setValue(ci, forKey: kCIInputImageKey)
        guard let out = f?.outputImage,
              let cg  = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func applyingAutoEnhance() -> UIImage? {
        guard let ci = CIImage(image: self) else { return nil }
        guard let tone = CIFilter(name: "CIToneCurve") else { return nil }
        tone.setValue(ci, forKey: kCIInputImageKey)
        tone.setValue(CIVector(x: 0,    y: 0),    forKey: "inputPoint0")
        tone.setValue(CIVector(x: 0.17, y: 0),    forKey: "inputPoint1")
        tone.setValue(CIVector(x: 0.55, y: 0.46), forKey: "inputPoint2")
        tone.setValue(CIVector(x: 0.92, y: 1.0),  forKey: "inputPoint3")
        tone.setValue(CIVector(x: 1.0,  y: 1.0),  forKey: "inputPoint4")
        guard let toned = tone.outputImage else { return nil }
        guard let cc = CIFilter(name: "CIColorControls") else { return nil }
        cc.setValue(toned, forKey: kCIInputImageKey)
        cc.setValue(1.25,  forKey: kCIInputContrastKey)
        cc.setValue(0,     forKey: kCIInputBrightnessKey)
        cc.setValue(1.0,   forKey: kCIInputSaturationKey)
        guard let out = cc.outputImage,
              let cg  = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    func rotated(by degrees: CGFloat) -> UIImage? {
        let rad = degrees * .pi / 180
        var s = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: rad)).size
        s.width  = floor(s.width)
        s.height = floor(s.height)
        UIGraphicsBeginImageContextWithOptions(s, false, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.translateBy(x: s.width / 2, y: s.height / 2)
        ctx.rotate(by: rad)
        draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                        width: size.width, height: size.height))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
}
