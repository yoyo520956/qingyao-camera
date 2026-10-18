import CoreImage
import UIKit

enum HDRProcessor {

    static func mergeHDR(dark: UIImage, base: UIImage, bright: UIImage) -> UIImage? {
        guard let cgD = dark.cgImage, let cgB = base.cgImage, let cgL = bright.cgImage else { return nil }

        let maxDim: CGFloat = 1536
        let w0 = CGFloat(cgB.width), h0 = CGFloat(cgB.height)
        let scale = min(1.0, maxDim / max(w0, h0))
        let tw = max(2, Int(w0 * scale / 2) * 2)
        let th = max(2, Int(h0 * scale / 2) * 2)

        guard let d = rasterize(cgD, tw, th),
              let b = rasterize(cgB, tw, th),
              let l = rasterize(cgL, tw, th) else { return nil }

        let n = tw * th * 4
        var out = [UInt8](repeating: 0, count: n)

        for i in stride(from: 0, to: n, by: 4) {

            let y = Float(b[i]) * 0.2126 + Float(b[i+1]) * 0.7152 + Float(b[i+2]) * 0.0722
            let yl = y / 255.0

            let alpha = max(0, min(1, (abs(yl - 0.5) * 2.0 - 0.18) * 1.6))
            for c in 0..<3 {
                let baseV = Float(b[i+c])
                let altV = yl < 0.5 ? Float(l[i+c]) : Float(d[i+c])
                let v = baseV * (1 - alpha) + altV * alpha
                out[i+c] = UInt8(max(0, min(255, v)))
            }
            out[i+3] = 255
        }

        guard let img = makeImage(&out, tw, th) else { return nil }

        var ci = CIImage(cgImage: img)
        ci = autoLevels(ci)
        ci = adjust(ci, contrast: 1.04, saturation: 1.08, gamma: 1.0)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let final = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: final)
    }

    static func tonemap(_ input: UIImage) -> UIImage {
        guard let cg = input.cgImage else { return input }
        var ci = CIImage(cgImage: cg)
        ci = autoLevels(ci)
        ci = adjust(ci, contrast: 1.04, saturation: 1.08, gamma: 1.0)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let final = ctx.createCGImage(ci, from: ci.extent) else { return input }
        return UIImage(cgImage: final)
    }

    static func dro(_ input: UIImage) -> UIImage? {
        guard let cg = input.cgImage else { return nil }
        var ci = CIImage(cgImage: cg)

        if let shadow = CIFilter(name: "CIHighlightShadowAdjust") {
            shadow.setValue(ci, forKey: kCIInputImageKey)
            shadow.setValue(0.72, forKey: "inputShadowAmount")
            shadow.setValue(0.92, forKey: "inputHighlightAmount")
            ci = shadow.outputImage ?? ci
        }

        if let clarity = CIFilter(name: "CIUnsharpMask") {
            clarity.setValue(ci, forKey: kCIInputImageKey)
            clarity.setValue(0.55, forKey: kCIInputIntensityKey)
            clarity.setValue(18.0, forKey: kCIInputRadiusKey)
            ci = clarity.outputImage ?? ci
        }

        ci = adjust(ci, contrast: 1.03, saturation: 1.06, gamma: 0.94)

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let final = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: final)
    }

    private static func rasterize(_ cg: CGImage, _ tw: Int, _ th: Int) -> UnsafeMutablePointer<UInt8>? {
        guard let ctx = CGContext(data: nil, width: tw, height: th,
                                  bitsPerComponent: 8, bytesPerRow: tw * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.data?.bindMemory(to: UInt8.self, capacity: tw * th * 4)
    }

    private static func makeImage(_ buf: inout [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let ctx = CGContext(data: &buf, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        return ctx.makeImage()
    }

    private static func autoLevels(_ ci: CIImage) -> CIImage {
        guard let et = CIFilter(name: "CIExposureAdjust") else { return ci }
        et.setValue(ci, forKey: kCIInputImageKey)
        et.setValue(0.0, forKey: kCIInputEVKey)
        return et.outputImage ?? ci
    }

    private static func adjust(_ ci: CIImage, contrast: CGFloat, saturation: CGFloat, gamma: CGFloat) -> CIImage {
        var out = ci
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(out, forKey: kCIInputImageKey)
            f.setValue(contrast, forKey: kCIInputContrastKey)
            f.setValue(saturation, forKey: kCIInputSaturationKey)
            out = f.outputImage ?? out
        }
        if let g = CIFilter(name: "CIGammaAdjust") {
            g.setValue(out, forKey: kCIInputImageKey)
            g.setValue(gamma, forKey: "inputPower")
            out = g.outputImage ?? out
        }
        return out
    }
}
