import SwiftUI
import UIKit

final class PanoramaProcessor: ObservableObject {
    static let shared = PanoramaProcessor()

    @Published var isRunning = false
    @Published var stripeCount = 0
    @Published var progress: Float = 0

    var maxStrips = 26

    let stripFraction: CGFloat = 0.30

    let outputHeight: CGFloat = 1024

    private var strips: [UIImage] = []

    func start() {
        strips = []
        stripeCount = 0
        progress = 0
        isRunning = true
    }

    func addFrame(_ image: UIImage) {
        guard isRunning, strips.count < maxStrips else { return }
        let scaled = image.scaledToHeight(Int(outputHeight))
        guard let cg = scaled.fixOrientation().cgImage else { return }
        let stripW = Int(CGFloat(cg.width) * stripFraction)
        let x = (cg.width - stripW) / 2
        guard let cropped = cg.cropping(to: CGRect(x: x, y: 0, width: stripW, height: cg.height)) else { return }
        let strip = UIImage(cgImage: cropped)
        strips.append(strip)
        stripeCount = strips.count
        progress = Float(strips.count) / Float(maxStrips)
        if strips.count >= maxStrips {
            isRunning = false
        }
    }

    func stopAndStitch(completion: @escaping (UIImage?) -> Void) {
        isRunning = false
        let local = strips
        strips = []
        DispatchQueue.global(qos: .userInitiated).async {
            guard local.count >= 3 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let pano = self.stitch(local)
            DispatchQueue.main.async { completion(pano) }
        }
    }

    private func stitch(_ strips: [UIImage]) -> UIImage? {
        let h = outputHeight
        let stripW = strips[0].size.width
        let overlap = stripW * 0.08
        let step = stripW - overlap
        let totalW = step * CGFloat(strips.count - 1) + stripW

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        var acc = CIImage(cgImage: strips[0].fixOrientation().cgImage!)
        for (i, strip) in strips.enumerated().dropFirst() {
            guard let cg = strip.fixOrientation().cgImage else { continue }
            let next = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: step * CGFloat(i), y: 0))

            let start = step * CGFloat(i)
            let fadeEnd = start + overlap
            let mask = CIFilter(name: "CILinearGradient")!
            mask.setValue(CIVector(x: start, y: 0), forKey: "inputPoint0")
            mask.setValue(CIVector(x: fadeEnd, y: 0), forKey: "inputPoint1")
            mask.setValue(CIColor(red: 0, green: 0, blue: 0), forKey: "inputColor0")
            mask.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor1")
            guard let maskImg = mask.outputImage else { continue }

            let blend = CIFilter(name: "CIBlendWithMask")!
            blend.setValue(acc, forKey: kCIInputImageKey)
            blend.setValue(next, forKey: kCIInputBackgroundImageKey)
            blend.setValue(maskImg.cropped(to: next.extent), forKey: "inputMaskImage")
            if let blended = blend.outputImage { acc = blended }
        }
        let ext = CGRect(x: 0, y: 0, width: totalW, height: h)
        acc = acc.cropped(to: ext)
        guard let cgOut = ctx.createCGImage(acc, from: ext) else { return nil }
        return UIImage(cgImage: cgOut).fixOrientation()
    }
}

enum HDRPlusProcessor {

    static func merge(_ frames: [UIImage]) -> UIImage? {
        guard frames.count >= 4 else { return nil }

        let scaled = frames.map { $0.scaledToMaxSide(1536).fixOrientation() }
        guard let base = scaled[0].cgImage else { return nil }
        let w = base.width, h = base.height

        var acc = CIImage(cgImage: base)
        let ctx = CIContext()
        for (i, frame) in scaled.enumerated().dropFirst() {
            guard let cg = frame.cgImage else { continue }
            let next = CIImage(cgImage: cg)

            let wa = CGFloat(i) / CGFloat(i + 1)
            let wn = 1.0 - wa
            let scaleA = CIFilter(name: "CIColorMatrix")!
            scaleA.setValue(acc, forKey: kCIInputImageKey)
            scaleA.setValue(CIVector(x: wa, y: wa, z: wa, w: 1), forKey: "inputRVector")
            scaleA.setValue(CIVector(x: wa, y: wa, z: wa, w: 1), forKey: "inputGVector")
            scaleA.setValue(CIVector(x: wa, y: wa, z: wa, w: 1), forKey: "inputBVector")
            scaleA.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            let scaledA = scaleA.outputImage!

            let scaleN = CIFilter(name: "CIColorMatrix")!
            scaleN.setValue(next, forKey: kCIInputImageKey)
            scaleN.setValue(CIVector(x: wn, y: wn, z: wn, w: 1), forKey: "inputRVector")
            scaleN.setValue(CIVector(x: wn, y: wn, z: wn, w: 1), forKey: "inputGVector")
            scaleN.setValue(CIVector(x: wn, y: wn, z: wn, w: 1), forKey: "inputBVector")
            scaleN.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            let scaledN = scaleN.outputImage!

            let add = CIFilter(name: "CIAdditionCompositing")!
            add.setValue(scaledA, forKey: kCIInputImageKey)
            add.setValue(scaledN, forKey: kCIInputBackgroundImageKey)
            acc = add.outputImage ?? acc
        }
        guard let merged = ctx.createCGImage(acc, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
        var out = UIImage(cgImage: merged)

        out = HDRProcessor.tonemap(out)
        return out
    }
}

enum SlowShutterProcessor {

    static func average(_ frames: [UIImage]) -> UIImage? {
        guard !frames.isEmpty else { return nil }
        return HDRPlusProcessor.merge(frames)
    }
}

extension UIImage {
    func scaledToHeight(_ h: Int) -> UIImage {
        guard size.height > CGFloat(h) else { return self }
        let scale = CGFloat(h) / size.height
        let newSize = CGSize(width: size.width * scale, height: CGFloat(h))
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func scaledToMaxSide(_ maxSide: Int) -> UIImage {
        let m = max(size.width, size.height)
        guard m > CGFloat(maxSide) else { return self }
        let scale = CGFloat(maxSide) / m
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func fixOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
