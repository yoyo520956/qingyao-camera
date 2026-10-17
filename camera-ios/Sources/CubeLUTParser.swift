import SwiftUI
import CoreImage

struct CubeLUT: Identifiable, Equatable {
    let name: String
    let file: String
    let category: String
    let size: Int

    var id: String { file }

    var categoryDisplay: String {
        switch category {
        case "bw": return "黑白胶片"
        case "colorslide": return "彩色反转"
        case "fujixtransiii": return "富士"
        case "instant_consumer": return "拍立得"
        case "instant_pro": return "专业宝丽来"
        case "negative_color": return "彩色负片"
        case "negative_new": return "现代胶片"
        case "negative_old": return "复古胶片"
        case "print": return "印刷相纸"
        default: return category
        }
    }
}

enum LUTStore {
    static let categoryOrder = ["negative_color", "negative_new", "negative_old",
                                "colorslide", "fujixtransiii",
                                "instant_consumer", "instant_pro",
                                "bw", "print"]

    static func all() -> [CubeLUT] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "cube", subdirectory: nil) else { return [] }
        return urls.map { url in
            let file = url.lastPathComponent
            let parts = file.replacingOccurrences(of: ".cube", with: "").components(separatedBy: "__")
            let cat = parts.count > 1 ? parts[0] : "misc"
            let rawName = parts.count > 1 ? parts[1] : parts[0]
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return CubeLUT(name: rawName.replacingOccurrences(of: "_", with: " "),
                           file: file, category: cat, size: size)
        }
        .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    static func inCategory(_ cat: String, from luts: [CubeLUT]) -> [CubeLUT] {
        luts.filter { $0.category == cat }
    }
}

enum CubeLUTParser {

    static func parse(_ text: String) -> (data: Data, dimension: Int)? {
        var gridSize = 0
        var values: [Float] = []
        var haveDomain = false
        var dmin: [Float] = [0, 0, 0]
        var dmax: [Float] = [1, 1, 1]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tokens[0] == "LUT_3D_SIZE" {
                gridSize = Int(tokens[1]) ?? 0
            } else if tokens[0] == "DOMAIN_MIN" {
                dmin = tokens.dropFirst().compactMap { Float($0) }
                haveDomain = true
            } else if tokens[0] == "DOMAIN_MAX" {
                dmax = tokens.dropFirst().compactMap { Float($0) }
                haveDomain = true
            } else if tokens[0] == "TITLE" || tokens[0] == "LUT_1D_SIZE" || tokens[0] == "LUT_1D_INPUT_LENGTH" {
                continue
            } else if let r = Float(tokens[0]), let g = Float(tokens[1]), let b = Float(tokens[2]) {
                values.append(r); values.append(g); values.append(b)
            }
        }
        guard gridSize > 1, values.count >= gridSize * gridSize * gridSize * 3 else { return nil }

        let n = Float(gridSize)
        var out = [Float](repeating: 0, count: gridSize * gridSize * gridSize * 4)

        for bi in 0..<gridSize {
            for gi in 0..<gridSize {
                for ri in 0..<gridSize {
                    let src = ((ri * gridSize) + gi) * gridSize + bi
                    let rr = normalize(values[src * 3], dmin[0], dmax[0])
                    let gg = normalize(values[src * 3 + 1], dmin[1], dmax[1])
                    let bb = normalize(values[src * 3 + 2], dmin[2], dmax[2])
                    let dst = ((bi * gridSize) + gi) * gridSize + ri
                    out[dst * 4] = rr
                    out[dst * 4 + 1] = gg
                    out[dst * 4 + 2] = bb
                    out[dst * 4 + 3] = 1.0
                }
            }
        }
        let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
        _ = n; _ = haveDomain
        return (data, gridSize)
    }

    private static func normalize(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        if hi - lo < 0.0001 { return v }
        return max(0, min(1, (v - lo) / (hi - lo)))
    }

    static func apply(_ image: CIImage, lut: CubeLUT, cache: inout [String: (Data, Int)], intensity: Double = 1.0) -> CIImage {
        if cache[lut.file] == nil {
            guard let url = Bundle.main.url(forResource: lut.file.replacingOccurrences(of: ".cube", with: ""),
                                            withExtension: "cube") ,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = parse(text) else { return image }
            cache[lut.file] = parsed
        }
        guard let (data, dim) = cache[lut.file] else { return image }
        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(Float(dim), forKey: "inputCubeDimension")
        guard let graded = filter.outputImage else { return image }

        guard intensity < 0.999 else { return graded }
        guard let mix = CIFilter(name: "CISourceOverCompositing") else { return graded }
        let alpha = CIFilter(name: "CIColorMatrix")!
        alpha.setValue(graded, forKey: kCIInputImageKey)
        let w = CGFloat(intensity)
        alpha.setValue(CIVector(x: w, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alpha.setValue(CIVector(x: 0, y: w, z: 0, w: 0), forKey: "inputGVector")
        alpha.setValue(CIVector(x: 0, y: 0, z: w, w: 0), forKey: "inputBVector")
        alpha.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        mix.setValue(alpha.outputImage ?? graded, forKey: kCIInputImageKey)
        mix.setValue(image, forKey: kCIInputBackgroundImageKey)
        return mix.outputImage ?? graded
    }
}
