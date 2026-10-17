import CoreImage
import UIKit

enum NightModeProcessor {

    static let frameCount = 4

    static func stitch(_ images: [UIImage]) -> UIImage? {
        guard images.count >= 2, let first = images.first,
              let cg0 = first.cgImage else { return nil }

        let maxDim: CGFloat = 1536
        let w = CGFloat(cg0.width), h = CGFloat(cg0.height)
        let scale = min(1.0, maxDim / max(w, h))
        let tw = max(2, Int(w * scale / 2) * 2)
        let th = max(2, Int(h * scale / 2) * 2)

        var acc = [Float](repeating: 0, count: tw * th * 4)
        var count: Float = 0

        for img in images {
            guard let cg = img.cgImage else { continue }
            guard let ctx = CGContext(data: nil, width: tw, height: th,
                                      bitsPerComponent: 8, bytesPerRow: tw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
            guard let data = ctx.data else { continue }
            let px = data.bindMemory(to: UInt8.self, capacity: tw * th * 4)
            for i in 0..<(tw * th * 4) {
                acc[i] += Float(px[i])
            }
            count += 1
        }
        guard count > 0 else { return nil }

        let gamma: Float = 0.62
        let lift: Float = 14.0
        for i in stride(from: 0, to: acc.count, by: 4) {
            for c in 0..<3 {
                var v = acc[i + c] / count
                v = (v / 255.0 + lift / 255.0)
                v = pow(max(0, min(1, v)), gamma) * 255.0
                acc[i + c] = v
            }
            acc[i + 3] = 255
        }

        guard let outCtx = CGContext(data: &acc, width: tw, height: th,
                                     bitsPerComponent: 8, bytesPerRow: tw * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outCG = outCtx.makeImage() else { return nil }

        var ci = CIImage(cgImage: outCG)
        if let cl = CIFilter(name: "CIColorControls") {
            cl.setValue(ci, forKey: kCIInputImageKey)
            cl.setValue(1.12, forKey: kCIInputContrastKey)
            cl.setValue(0.06, forKey: kCIInputSaturationKey)
            cl.setValue(0.02, forKey: kCIInputBrightnessKey)
            ci = cl.outputImage ?? ci
        }
        if let sh = CIFilter(name: "CIUnsharpMask") {
            sh.setValue(ci, forKey: kCIInputImageKey)
            sh.setValue(0.5, forKey: kCIInputIntensityKey)
            sh.setValue(2.5, forKey: kCIInputRadiusKey)
            ci = sh.outputImage ?? ci
        }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let finalCG = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: finalCG)
    }
}
