import AVFoundation
import Photos
import UIKit

final class TimeLapseRecorder: ObservableObject {

    @Published var isRunning = false
    @Published var frameCount = 0
    @Published var elapsedSeconds: Int = 0

    var interval: Double = 1.0

    private var tempDir: URL?
    private var lastShotAt: Date?
    private var startedAt: Date?
    private var lastElapsedTick: Date?

    func start() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tl_\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        frameCount = 0
        elapsedSeconds = 0
        lastShotAt = nil
        startedAt = Date()
        lastElapsedTick = Date()
        isRunning = true
    }

    func shouldCapture() -> Bool {
        guard isRunning else { return false }
        if let last = lastShotAt, Date().timeIntervalSince(last) < interval { return false }
        lastShotAt = Date()
        return true
    }

    func tickElapsed() {
        guard isRunning, let start = startedAt else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
    }

    func addFrame(_ image: UIImage) {
        guard isRunning, let dir = tempDir else { return }

        guard let jpeg = image.agnesCompressed(maxDimension: 1280, quality: 0.88) else { return }
        let url = dir.appendingPathComponent(String(format: "f_%05d.jpg", frameCount))
        try? jpeg.write(to: url)
        frameCount += 1
    }

    func cancel() {
        isRunning = false
        cleanup()
    }

    private static func loadFrames(dir: URL, count: Int, step: Int) -> [UIImage] {
        var frames: [UIImage] = []
        guard step >= 1 else { return frames }
        for i in stride(from: 0, to: count, by: step) {
            let url = dir.appendingPathComponent(String(format: "f_%05d.jpg", i))
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                frames.append(img)
            }
        }
        return frames
    }

    func stopAndRender(withGif: Bool = true, completion: @escaping (Bool) -> Void) {
        isRunning = false
        let dir = tempDir
        let count = frameCount
        guard let dir = dir, count >= 4 else {
            cleanup()
            DispatchQueue.main.async { completion(false) }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("TL_\(Int(Date().timeIntervalSince1970)).mp4")
            let ok = Self.renderSequence(dir: dir, count: count, fps: 30, outputURL: outURL)
            guard ok else {
                try? FileManager.default.removeItem(at: outURL)
                DispatchQueue.main.async {
                    self.cleanup()
                    completion(false)
                }
                return
            }
            if withGif {
                let frames = Self.loadFrames(dir: dir, count: count, step: 2)
                if !frames.isEmpty, let gif = GifExporter.makeGIF(frames: frames, delay: 0.15) {
                    GifExporter.saveToAlbum(gif) { _ in }
                }
            }
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        self.cleanup()
                        completion(true)
                    }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outURL)
                }) { saved, _ in
                    if saved { try? FileManager.default.removeItem(at: outURL) }
                    DispatchQueue.main.async {
                        self.cleanup()
                        completion(true)
                    }
                }
            }
        }
    }

    private func cleanup() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        frameCount = 0
    }

    private static func renderSequence(dir: URL, count: Int, fps: Int, outputURL: URL) -> Bool {
        guard let first = UIImage(contentsOfFile: dir.appendingPathComponent("f_00000.jpg").path),
              let firstCG = first.cgImage else { return false }

        let w = firstCG.width / 2 * 2
        let h = firstCG.height / 2 * 2
        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .mp4) else { return false }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h
        ]
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        var frameIdx = 0
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "tl.render")

        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData && frameIdx < count {
                guard frameIdx < count else {
                    input.markAsFinished()
                    return
                }
                let url = dir.appendingPathComponent(String(format: "f_%05d.jpg", frameIdx))
                guard let img = UIImage(contentsOfFile: url.path), let cg = img.cgImage,
                      let pb = Self.pixelBuffer(from: cg, width: w, height: h) else {
                    frameIdx += 1
                    continue
                }
                let t = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps))
                adapter.append(pb, withPresentationTime: t)
                frameIdx += 1
            }
            if frameIdx >= count && !input.isReadyForMoreMediaData {
                input.markAsFinished()
                group.enter()
                writer.finishWriting {
                    group.leave()
                }
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        group.notify(queue: .global()) { semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 120)
        return writer.status == .completed
    }

    static func pixelBuffer(from cg: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                               width: width, height: height,
                               bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }
}
