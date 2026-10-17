import SwiftUI
import CoreImage

enum DetailEnhancer {

    static func enhance(_ input: UIImage) -> UIImage {
        if aiSuperEnabled, let denoised = SRPipeline.denoise(input, iso: currentISOHint) {
            return traditionalEnhance(denoised)
        }
        return traditionalEnhance(input)
    }

    private static func traditionalEnhance(_ input: UIImage) -> UIImage {
        guard let cg = input.cgImage else { return input }
        var ci = CIImage(cgImage: cg)

        if let median = CIFilter(name: "CIMedianFilter") {
            median.setValue(ci, forKey: kCIInputImageKey)

            if let med = median.outputImage {
                guard let mix = CIFilter(name: "CISourceOverCompositing"),
                      let half = CIFilter(name: "CIColorMatrix") else { return input }
                half.setValue(med, forKey: kCIInputImageKey)
                half.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                half.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                half.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                half.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.5), forKey: "inputAVector")
                half.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.5), forKey: "inputBiasVector")
                mix.setValue(half.outputImage ?? med, forKey: kCIInputImageKey)
                mix.setValue(ci, forKey: kCIInputBackgroundImageKey)
                ci = mix.outputImage ?? ci
            }
        }

        ci = unsharp(ci, radius: 1.2, intensity: 0.45)
        ci = unsharp(ci, radius: 4.5, intensity: 0.28)

        ci = clarity(ci)

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let out = ctx.createCGImage(ci, from: ci.extent) else { return input }
        return UIImage(cgImage: out, scale: input.scale, orientation: input.imageOrientation)
    }

    static func alignMerge(_ frames: [UIImage], upscale2x: Bool = true) -> UIImage? {
        guard frames.count >= 3 else { return frames.first }
        let scaled = frames.map { $0.scaledToMaxSide(2048).fixOrientation() }
        guard let base = scaled[0].cgImage else { return nil }
        let w = base.width, h = base.height

        var aligned: [CGImage] = []
        for frame in scaled.dropFirst() {
            guard let cg = frame.cgImage,
                  let off = estimateShift(base: base, other: cg) else { continue }
            if abs(off.x) < 1 && abs(off.y) < 1 {
                aligned.append(cg)
            } else {

                let t = CGAffineTransform(translationX: -off.x, y: -off.y)
                let ext = CGRect(x: 0, y: 0, width: w, height: h)
                let shifted = CIImage(cgImage: cg).transformed(by: t).cropped(to: ext)
                let ctx = CIContext(options: [.useSoftwareRenderer: false])
                if let img = ctx.createCGImage(shifted, from: ext) {
                    aligned.append(img)
                }

                if let shifts = refineBlocks(base: base, other: cg, global: off), !shifts.isEmpty {
                    let sortedX = shifts.map { $0.x }.sorted()
                    let sortedY = shifts.map { $0.y }.sorted()
                    let medianX = sortedX[sortedX.count / 2]
                    let medianY = sortedY[sortedY.count / 2]
                    if abs(medianX - off.x) > 0.5 || abs(medianY - off.y) > 0.5 {
                        let t2 = CGAffineTransform(translationX: -(medianX - off.x), y: -(medianY - off.y))
                        let ext2 = CGRect(x: 0, y: 0, width: w, height: h)
                        let shifted2 = CIImage(cgImage: cg).transformed(by: t2).cropped(to: ext2)
                        let ctx2 = CIContext(options: [.useSoftwareRenderer: false])
                        if let img2 = ctx2.createCGImage(shifted2, from: ext2) {
                            aligned[aligned.count - 1] = img2
                        }
                    }
                }
            }
        }

        guard let merged = averageCG([base] + aligned, w: w, h: h) else { return nil }
        var out = UIImage(cgImage: merged)

        out = enhance(out)

        if aiSuperEnabled {
            if let sr = SRPipeline.upscale2x(out, iso: currentISOHint) {
                out = sr
            } else if upscale2x {
                out = lanczos2x(out)
            }
        } else if upscale2x {
            out = lanczos2x(out)
        }
        return out
    }

    static var aiSuperEnabled = false
    static var currentISOHint = 100

    static func lanczos2x(_ input: UIImage) -> UIImage {
        guard let cg = input.cgImage else { return input }
        var ci = CIImage(cgImage: cg)
        if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(ci, forKey: kCIInputImageKey)
            lanczos.setValue(2.0, forKey: kCIInputScaleKey)
            if let up = lanczos.outputImage { ci = up }
        }
        if let usm = CIFilter(name: "CIUnsharpMask") {
            usm.setValue(ci, forKey: kCIInputImageKey)
            usm.setValue(1.0, forKey: kCIInputRadiusKey)
            usm.setValue(0.35, forKey: kCIInputIntensityKey)
            if let sharp = usm.outputImage { ci = sharp }
        }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        if let outCG = ctx.createCGImage(ci, from: ci.extent) {
            return UIImage(cgImage: outCG)
        }
        return input
    }

    private static func estimateShift(base: CGImage, other: CGImage) -> CGPoint? {

        guard let b8 = downsample(base, f: 8), let o8 = downsample(other, f: 8),
              let coarse = search(base: b8, other: o8, range: 6) else { return nil }

        guard let b4 = downsample(base, f: 4), let o4 = downsample(other, f: 4),
              let fine = search(base: b4, other: o4, range: 2, center: coarse) else { return nil }

        return CGPoint(x: fine.x * 4, y: fine.y * 4)
    }

    private static func downsample(_ cg: CGImage, f: Int) -> CGImage? {
        let w = max(16, cg.width / f), h = max(16, cg.height / f)
        let ci = CIImage(cgImage: cg).transformed(
            by: CGAffineTransform(scaleX: CGFloat(w) / CGFloat(cg.width), y: CGFloat(h) / CGFloat(cg.height)))
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h))
    }

    private static func refineBlocks(base: CGImage, other: CGImage, global: CGPoint) -> [CGPoint]? {
        guard let b = toGray(base), let o = toGray(other) else { return nil }
        let w = base.width, h = base.height
        let bw = 8, bh = 8
        let cols = w / bw, rows = h / bh
        guard cols > 0, rows > 0 else { return nil }
        var shifts = [CGPoint](repeating: .zero, count: rows * cols)
        let gx = Int(global.x), gy = Int(global.y)

        for row in 0..<rows {
            for col in 0..<cols {
                let x0 = col * bw, y0 = row * bh
                var best = CGPoint.zero
                var bestScore = Float.greatestFiniteMagnitude
                for dy in -2...2 {
                    for dx in -2...2 {
                        let ox = gx + dx, oy = gy + dy
                        var sum: Float = 0
                        var n = 0
                        var y = y0
                        while y < y0 + bh && (y + oy) >= 0 && (y + oy) < h {
                            var x = x0
                            while x < x0 + bw && (x + ox) >= 0 && (x + ox) < w {
                                sum += abs(b[y * w + x] - o[(y + oy) * w + (x + ox)])
                                n += 1
                                x += 2
                            }
                            y += 2
                        }
                        if n > 0 {
                            let s = sum / Float(n)
                            if s < bestScore { bestScore = s; best = CGPoint(x: CGFloat(ox), y: CGFloat(oy)) }
                        }
                    }
                }
                shifts[row * cols + col] = best
            }
        }
        return shifts
    }

    private static func search(base: CGImage, other: CGImage, range: Int, center: CGPoint = .zero) -> CGPoint? {
        guard let b = toGray(base), let o = toGray(other) else { return nil }
        let w = base.width, h = base.height
        let step = max(2, min(w, h) / 48)
        var best = CGPoint.zero
        var bestScore = Float.greatestFiniteMagnitude
        let cx = Int(center.x), cy = Int(center.y)
        for dy in -range...range {
            for dx in -range...range {
                let ox = cx + dx, oy = cy + dy
                if abs(ox) >= w || abs(oy) >= h { continue }
                var sum: Float = 0
                var n = 0
                var y = max(0, oy); if oy < 0 { y = 0 }
                while y < h - max(0, oy) && y < h {
                    var x = max(0, ox); if ox < 0 { x = 0 }
                    while x < w - max(0, ox) && x < w {
                        let bv = b[y * w + x]
                        let ov = o[(y - oy) * w + (x - ox)]
                        sum += abs(bv - ov)
                        n += 1
                        x += step
                    }
                    y += step
                }
                if n > 0 {
                    let score = sum / Float(n)
                    if score < bestScore {
                        bestScore = score
                        best = CGPoint(x: CGFloat(ox), y: CGFloat(oy))
                    }
                }
            }
        }
        return best
    }

    private static func toGray(_ cg: CGImage) -> [Float]? {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var gray = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            gray[i] = Float(px[i * 4]) * 0.2126 + Float(px[i * 4 + 1]) * 0.7152 + Float(px[i * 4 + 2]) * 0.0722
        }
        return gray
    }

    private static func averageCG(_ images: [CGImage], w: Int, h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var acc = [Float](repeating: 0, count: w * h * 4)
        for cg in images {
            guard let ictx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ictx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let data = ictx.data {
                let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
                for i in 0..<(w * h * 4) { acc[i] += Float(px[i]) }
            }
        }
        let n = Float(images.count)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h * 4) { out[i] = UInt8(max(0, min(255, acc[i] / n))) }
        ctx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4).update(from: out, count: w * h * 4)
        return ctx.makeImage()
    }

    private static func unsharp(_ ci: CIImage, radius: Double, intensity: Double) -> CIImage {
        guard let f = CIFilter(name: "CIUnsharpMask") else { return ci }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        f.setValue(intensity, forKey: kCIInputIntensityKey)
        return f.outputImage ?? ci
    }

    private static func clarity(_ ci: CIImage) -> CIImage {
        unsharp(ci, radius: 18, intensity: 0.16)
    }
}
