import SwiftUI
import Vision
import CoreImage

// MARK: - 人像模式（背景虚化）
// Vision 系统内置人像分割 + 背景高斯虚化 + mask 合成
enum PortraitProcessor {

    /// 浅/中/深 景深
    enum Depth: Int, CaseIterable {
        case light, medium, deep
        var sigma: Double {
            switch self {
            case .light: return 6
            case .medium: return 12
            case .deep: return 22
            }
        }
        var label: String {
            switch self {
            case .light: return "浅"
            case .medium: return "中"
            case .deep: return "深"
            }
        }
    }

    /// 拍照时处理：无人像则原样返回（不阻塞）
    static func blur(_ image: UIImage, depth: Depth) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let original = CIImage(cgImage: cg)

        // 1. Vision 人像分割
        guard let seg = segment(original) else { return image }
        let mask = seg

        // 2. 背景虚化
        let blurred = original.applyingGaussianBlur(sigma: depth.sigma)

        // 3. 尺寸对齐（分割可能降采样）
        let m2 = mask.scaleToMatch(original.extent)

        // 4. 合成：mask 白=前景清晰，黑=背景虚化
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(original, forKey: kCIInputImageKey)
        blend.setValue(blurred, forKey: kCIInputBackgroundImageKey)
        blend.setValue(m2, forKey: "inputMaskImage")
        guard let out = blend.outputImage else { return image }

        // 羽化边缘（mask 轻模糊，减少割裂）
        let soft = out.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.8])
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let clamped = soft.clampedToExtent()
        guard let cgOut = ctx.createCGImage(clamped, from: original.extent) else { return image }
        return UIImage(cgImage: cgOut)
    }

    /// Vision 分割 → 灰度 mask CIImage
    private static func segment(_ ci: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        let handler = VNImageRequestHandler(ciImage: ci, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let obs = request.results?.first else { return nil }
        let px = obs.pixelBuffer
        // 人像=白、背景=黑，直接作为 CIBlendWithMask 的 mask
        var ci2 = CIImage(cvPixelBuffer: px)
        // 提升对比，使分割边界更实
        ci2 = ci2.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.6, kCIInputSaturationKey: 0.0])
        return ci2
    }

}

// MARK: - mask 尺寸对齐（文件级 extension）
private extension CIImage {
    func scaleToMatch(_ target: CGRect) -> CIImage {
        guard abs(extent.width - target.width) > 1 || abs(extent.height - target.height) > 1 else {
            return self.cropped(to: target)
        }
        let sx = target.width / extent.width
        let sy = target.height / extent.height
        var t = self.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        t = t.cropped(to: target)
        return t
    }
}
