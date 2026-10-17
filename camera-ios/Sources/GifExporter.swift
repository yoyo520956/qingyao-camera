import UIKit
import ImageIO
import Photos
import UniformTypeIdentifiers

// MARK: - GIF 动图导出 v4.8（延时/连拍序列 → 循环动图）
enum GifExporter {

    static func makeGIF(frames: [UIImage], delay: Double = 0.12, maxSide: Int = 720) -> Data? {
        guard frames.count >= 3 else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else {
            return nil
        }
        let fileProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: delay,
                kCGImagePropertyGIFUnclampedDelayTime as String: delay
            ]
        ]
        for frame in frames {
            let scaled = frame.scaledToMaxSide(maxSide).fixOrientation()
            guard let cg = scaled.cgImage else { continue }
            CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func saveToAlbum(_ gifData: Data, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = UTType.gif.identifier
            PHAssetCreationRequest.forAsset()
                .addResource(with: .photo, data: gifData, options: options)
        }) { success, _ in
            if !success {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = docs.appendingPathComponent("AG_\(Int(Date().timeIntervalSince1970)).gif")
                try? gifData.write(to: url)
            }
            DispatchQueue.main.async { completion(success) }
        }
    }
}
