import UIKit
import CoreML
import Accelerate

enum SRPipeline {

    static func modelURL(name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mlmodel")
    }

    static func videoFrameEnhance(_ image: CIImage) -> CIImage {
        var out = image
        if let usm = CIFilter(name: "CIUnsharpMask") {
            usm.setValue(out, forKey: kCIInputImageKey)
            usm.setValue(1.0, forKey: kCIInputRadiusKey)
            usm.setValue(0.25, forKey: kCIInputIntensityKey)
            if let o = usm.outputImage { out = o }
        }
        return out
    }

    static func noiseLevel(forISO iso: Int) -> Int {
        switch iso {
        case ..<400: return 0
        case ..<1000: return 1
        case ..<2500: return 2
        default: return 3
        }
    }

    static func denoise(_ image: UIImage, iso: Int) -> UIImage? {
        let level = noiseLevel(forISO: iso)
        let name = "photo_noise\(level)_model"
        return runTile(image: image, modelName: name, scale: 1)
    }

    static func upscale2x(_ image: UIImage, iso: Int) -> UIImage? {
        let level = noiseLevel(forISO: iso)
        let name = "up_photo_noise\(level)_scale2x_model"
        return runTile(image: image, modelName: name, scale: 2)
    }

    static func runTile(image input: UIImage, modelName: String, scale: Int) -> UIImage? {
        guard let url = modelURL(name: modelName),
              let cg = input.fixOrientation().cgImage else { return nil }

        let limited = scale == 2 ? input.scaledToMaxSide(2048) : input.scaledToMaxSide(4096)
        guard let srcCG = limited.fixOrientation().cgImage else { return nil }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let mlModel = try? MLModel(contentsOf: url, configuration: config) else { return nil }

        let shrink = 7
        let inBlock = 142
        let outBlock = 128 * scale
        let cropOut = 7 * scale
        let strideOut = outBlock - 2 * cropOut

        let W = srcCG.width, H = srcCG.height
        let exW = W + 2 * shrink, exH = H + 2 * shrink

        var rgba = [UInt8](repeating: 0, count: W * H * 4)
        guard let ctx = CGContext(data: &rgba, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(srcCG, in: CGRect(x: 0, y: 0, width: W, height: H))

        var planes = [[Float]](repeating: [Float](repeating: 0, count: exW * exH), count: 3)
        let eta: Float = 0.00196078411
        for y in 0..<H {
            for x in 0..<W {
                let p = (W * y + x) * 4
                let xx = x + shrink, yy = y + shrink
                planes[0][yy * exW + xx] = Float(rgba[p]) / 255 + eta
                planes[1][yy * exW + xx] = Float(rgba[p + 1]) / 255 + eta
                planes[2][yy * exW + xx] = Float(rgba[p + 2]) / 255 + eta
            }
        }

        for c in 0..<3 {
            for y in 0..<exH {
                let srcX = min(max(shrink, 0), W - 1) + shrink
                for x in 0..<shrink { planes[c][y * exW + x] = planes[c][y * exW + srcX] }
                for x in (shrink + W)..<exW { planes[c][y * exW + x] = planes[c][y * exW + shrink + W - 1] }
            }
            for x in 0..<exW {
                for y in 0..<shrink { planes[c][y * exW + x] = planes[c][shrink * exW + x] }
                for y in (shrink + H)..<exH { planes[c][y * exW + x] = planes[c][(shrink + H - 1) * exW + x] }
            }
        }

        let outW = W * scale, outH = H * scale
        var outPlanes = [[Float]](repeating: [Float](repeating: 0, count: outW * outH), count: 3)

        let cols = (outW + strideOut - 1) / strideOut
        let rows = (outH + strideOut - 1) / strideOut

        for row in 0..<rows {
            for col in 0..<cols {
                autoreleasepool {

                    let ox = col * strideOut, oy = row * strideOut

                    let ix = ox / scale, iy = oy / scale
                    let shape: [NSNumber] = [1, 3, NSNumber(value: inBlock), NSNumber(value: inBlock)]
                    let inputArray: MLMultiArray
                    do {
                        inputArray = try MLMultiArray(shape: shape, dataType: .float32)
                    } catch { return }

                    for c in 0..<3 {
                        let cBase = c * inBlock * inBlock
                        let srcPlane = planes[c]
                        for y in 0..<inBlock {
                            let sy = min(max(iy + y, 0), exH - 1)
                            let rowBase = sy * exW
                            let dstBase = cBase + y * inBlock
                            for x in 0..<inBlock {
                                let sx = min(max(ix + x, 0), exW - 1)
                                inputArray[dstBase + x] = NSNumber(value: srcPlane[rowBase + sx])
                            }
                        }
                    }

                    guard let output = try? mlModel.prediction(input: inputArray) else { return }
                    let outCount = output.count / 3
                    let obw = Int(Double(outBlock))
                    for c in 0..<3 {
                        let cBase = c * outCount
                        for y in 0..<outBlock {
                            let dy = oy + y - cropOut
                            if dy < 0 || dy >= outH { continue }
                            let rowBase = y * obw
                            let dstRow = dy * outW
                            for x in 0..<outBlock {
                                let dx = ox + x - cropOut
                                if dx < 0 || dx >= outW { continue }
                                let v = output[cBase + rowBase + x].floatValue
                                outPlanes[c][dstRow + dx] = max(0, min(1, v))
                            }
                        }
                    }
                }
            }
        }

        var outRGBA = [UInt8](repeating: 0, count: outW * outH * 4)
        for i in 0..<(outW * outH) {
            outRGBA[i * 4] = UInt8(max(0, min(255, outPlanes[0][i] * 255)))
            outRGBA[i * 4 + 1] = UInt8(max(0, min(255, outPlanes[1][i] * 255)))
            outRGBA[i * 4 + 2] = UInt8(max(0, min(255, outPlanes[2][i] * 255)))
            outRGBA[i * 4 + 3] = 255
        }
        guard let outCtx = CGContext(data: &outRGBA, width: outW, height: outH, bitsPerComponent: 8,
                                     bytesPerRow: outW * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        guard let outCG = outCtx.makeImage() else { return nil }
        return UIImage(cgImage: outCG)
    }
}
