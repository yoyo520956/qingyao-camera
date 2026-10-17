import CoreImage
import UIKit

enum BeautyProcessor {

    static func apply(_ image: CIImage, level: Float) -> CIImage {
        let l = CGFloat(min(max(level, 0), 1))
        guard l > 0.01 else { return image }

        var output = image

        if let maskImg = CIFilter(name: "CIConstantColorGenerator") {
            maskImg.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: kCIInputColorKey)
            let mask = maskImg.outputImage?.cropped(to: image.extent)
            if let smooth = CIFilter(name: "CIMaskedVariableBlur") {
                smooth.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
                smooth.setValue(mask, forKey: "inputMask")
                smooth.setValue(10.0 * l, forKey: kCIInputRadiusKey)
                if let smoothed = smooth.outputImage?.cropped(to: image.extent),
                   let mix = CIFilter(name: "CIDissolveTransition") {
                    mix.setValue(image, forKey: kCIInputImageKey)
                    mix.setValue(smoothed, forKey: "inputTargetImage")
                    mix.setValue(0.45 + 0.4 * l, forKey: "inputTime")
                    output = mix.outputImage ?? output
                }
            }
        }

        if let sharp = CIFilter(name: "CIUnsharpMask") {
            sharp.setValue(output, forKey: kCIInputImageKey)
            sharp.setValue(0.42, forKey: kCIInputIntensityKey)
            sharp.setValue(3.0, forKey: kCIInputRadiusKey)
            output = sharp.outputImage ?? output
        }

        output = FilterLibrary.apply("CIColorControls", to: output, params: [
            kCIInputBrightnessKey: 0.05 * l,
            kCIInputContrastKey: 1.0 - 0.06 * l,
            kCIInputSaturationKey: 1.02
        ])

        output = FilterLibrary.apply("CIColorMatrix", to: output, params: [
            "inputRVector": CIVector(x: 1.0 + 0.045 * l, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1.0 + 0.012 * l, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1.0 - 0.045 * l, w: 0)
        ])

        if let vib = CIFilter(name: "CIVibrance") {
            vib.setValue(output, forKey: kCIInputImageKey)
            vib.setValue(0.18 * CGFloat(l), forKey: "inputAmount")
            output = vib.outputImage ?? output
        }

        return output.cropped(to: image.extent)
    }
}

enum PhotoProcessor {

    static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    static func process(_ image: UIImage,
                        filter: FilterPreset,
                        beautyEnabled: Bool,
                        beautyLevel: Float) -> UIImage {
        guard var ci = CIImage(image: image,
                               options: [.applyOrientationProperty: true]) else {
            return image
        }

        if beautyEnabled {
            ci = BeautyProcessor.apply(ci, level: beautyLevel)
        }
        ci = filter.apply(ci)

        guard let cg = sharedContext.createCGImage(ci, from: ci.extent) else {
            return image
        }
        return UIImage(cgImage: cg)
    }
}
