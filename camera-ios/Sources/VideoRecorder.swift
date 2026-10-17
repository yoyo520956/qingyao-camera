import AVFoundation
import Photos
import UIKit

final class VideoRecorder: NSObject {

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var videoAdapter: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?

    private var timeOffset: CMTime = .zero
    private var lastVideoTS: CMTime = .invalid
    private var lastAudioTS: CMTime = .invalid
    private var sessionStarted = false

    private let ioLock = NSLock()
    private(set) var isRecording = false
    private(set) var isPaused = false

    var frameProvider: ((CVPixelBuffer) -> CVPixelBuffer?)?

    var slowMoFactor: Int = 1

    func startRecording() -> Bool {
        slowMoFactor = 1
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("REC_\(Int(Date().timeIntervalSince1970)).mov")
        outputURL = url

        guard let writer = try? AVAssetWriter(url: url, fileType: .mov) else { return false }
        self.writer = writer
        timeOffset = .zero
        lastVideoTS = .invalid
        lastAudioTS = .invalid
        sessionStarted = false
        isPaused = false
        isRecording = true
        return true
    }

    func startSlowMoRecording() -> Bool {
        let ok = startRecording()
        if ok { slowMoFactor = 4 }
        return ok
    }

    private func setupWriterIfNeeded(width: Int, height: Int, formatHint: CMFormatDescription?) {
        guard let writer = writer, videoInput == nil else { return }
        let w = width % 2 == 0 ? width : width - 1
        let h = height % 2 == 0 ? height : height - 1

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 14_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings, sourceFormatHint: formatHint)
        vi.expectsMediaDataInRealTime = true
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h
        ]
        videoAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vi, sourcePixelBufferAttributes: attrs)
        writer.add(vi)
        videoInput = vi

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96000
        ]
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        ai.expectsMediaDataInRealTime = true
        writer.add(ai)
        audioInput = ai

        writer.startWriting()
    }
}

extension VideoRecorder {

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard isRecording, !isPaused,
              CMSampleBufferDataIsReady(sampleBuffer) == true else { return }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let stretched = CMTimeMultiplyByFloat64(ts, multiplier: Float64(slowMoFactor))
        if lastVideoTS.isValid && CMTimeCompare(stretched, lastVideoTS) > 0 {
            let gap = CMTimeSubtract(stretched, lastVideoTS)
            if gap.seconds > 0.25 { timeOffset = CMTimeAdd(timeOffset, gap) }
        }
        lastVideoTS = stretched

        let raw = CMSampleBufferGetImageBuffer(sampleBuffer)
        guard let rawBuffer = raw else { return }
        let processed = frameProvider?(rawBuffer) ?? rawBuffer

        setupWriterIfNeeded(width: CVPixelBufferGetWidth(processed),
                            height: CVPixelBufferGetHeight(processed),
                            formatHint: CMSampleBufferGetFormatDescription(sampleBuffer))

        guard let adapter = videoAdapter, let input = videoInput, input.isReadyForMoreMediaData else { return }
        let t = CMTimeSubtract(stretched, timeOffset)
        if !sessionStarted {
            writer?.startSession(atSourceTime: t)
            sessionStarted = true
        }
        adapter.append(processed, withPresentationTime: t)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard isRecording, !isPaused,
              CMSampleBufferDataIsReady(sampleBuffer) == true,
              let input = audioInput, input.isReadyForMoreMediaData,
              sessionStarted else { return }

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastAudioTS.isValid {
            let gap = CMTimeSubtract(ts, lastAudioTS)
            if gap.seconds > 0.5 { timeOffset = CMTimeAdd(timeOffset, gap) }
        }
        lastAudioTS = ts

        let t = CMTimeSubtract(ts, timeOffset)
        input.append(sampleBuffer)
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func finishRecording(completion: @escaping (Bool) -> Void) {
        isRecording = false
        guard let writer = writer else { completion(false); return }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            let ok = writer.status == .completed
            let url = self?.outputURL
            guard ok, let url = url else {
                try? FileManager.default.removeItem(at: url ?? URL(fileURLWithPath: "/dev/null"))
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { saved, _ in
                    if saved { try? FileManager.default.removeItem(at: url) }
                    DispatchQueue.main.async { completion(true) }
                }
            }
        }
    }
}
