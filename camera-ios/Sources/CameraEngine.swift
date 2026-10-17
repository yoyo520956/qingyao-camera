import AVFoundation
import Combine
import CoreMedia
import CoreImage
import UIKit
import Vision

final class CameraEngine: NSObject, ObservableObject {

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.youlong.camera.session")
    private let videoQueue = DispatchQueue(label: "com.youlong.camera.video")

    private var videoInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "com.youlong.camera.audio")

    let recorder = VideoRecorder()

    var nightFrames: [UIImage] = []
    private(set) var currentDevice: AVCaptureDevice?

    private var isConfiguredSync = false
    private var isManualExposureActiveSync = false
    private var observers: [NSObjectProtocol] = []

    @Published var isConfigured = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var zoomFactor: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 6.0

    @Published var isoRange: ClosedRange<Float> = 100...1600
    @Published var shutterRange: ClosedRange<Double> = (1.0 / 1000.0)...(1.0 / 30.0)
    @Published var biasRange: ClosedRange<Float> = -3...3
    @Published var isManualExposureActive = false

    private(set) var flashMode: AVCaptureDevice.FlashMode = .off
    var isFlashAvailable: Bool { currentDevice?.hasFlash ?? false }

    var onVideoFrame: ((CVPixelBuffer) -> Void)?
    var onPhotoCaptured: ((UIImage) -> Void)?
    var onRawPhotoCaptured: ((Data) -> Void)?

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppForeground()
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        requestPermissionAndStart()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func handleAppForeground() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            NotificationCenter.default.post(
                name: .cameraPermissionResult, object: nil,
                userInfo: ["granted": true])
            configureAndStart()
        }
    }

    private func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .cameraPermissionResult, object: nil,
                        userInfo: ["granted": granted])
                    if granted {
                        self?.configureAndStart()
                    }
                }
            }

        default:
            NotificationCenter.default.post(
                name: .cameraPermissionResult, object: nil,
                userInfo: ["granted": false])
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.isConfiguredSync {
                self.configureSessionSync()
                self.isConfiguredSync = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isConfigured = running
                self.refreshCapabilities()
            }
        }
    }

    private func configureSessionSync() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        livePhotoCapable = photoOutput.isLivePhotoCaptureSupported
        if livePhotoCapable {
            photoOutput.isLivePhotoCaptureEnabled = true
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            currentDevice = device
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if #available(iOS 16.0, *) {
            let dims = device.activeFormat.supportedMaxPhotoDimensions
            if let maxDim = dims.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) {
                photoOutput.maxPhotoDimensions = maxDim
            }
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic) {
            audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
            if session.canAddInput(micInput) && session.canAddOutput(audioOutput) {
                session.addInput(micInput)
                session.addOutput(audioOutput)
            }
        }

        session.commitConfiguration()
    }

    private func refreshCapabilities() {
        guard let d = currentDevice else { return }
        isoRange = d.activeFormat.minISO...d.activeFormat.maxISO
        let minDur = CMTimeGetSeconds(d.activeFormat.minExposureDuration)
        let maxDur = CMTimeGetSeconds(d.activeFormat.maxExposureDuration)
        let lo = min(max(minDur, 1.0 / 8000.0), 1.0 / 60.0)
        let hi = max(min(maxDur, 1.0), 1.0 / 15.0)
        if lo < hi { shutterRange = lo...hi }
        biasRange = d.minExposureTargetBias...d.maxExposureTargetBias
        maxZoom = min(max(d.activeFormat.videoMaxZoomFactor, 1.0), 8.0)
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, let oldInput = self.videoInput else { return }
            let newPosition: AVCaptureDevice.Position =
                (self.currentDevice?.position == .back) ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }

            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoInput = newInput
                self.currentDevice = newDevice
                DispatchQueue.main.async {
                    self.cameraPosition = newPosition
                    self.flashMode = .off
                    self.zoomFactor = 1.0
                    self.isManualExposureActive = false
                    self.refreshCapabilities()
                }
            } else {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()

            if wasRunning && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        let f = max(1.0, min(factor, maxZoom))
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                d.videoZoomFactor = f
                d.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = f }
            } catch {}
        }
    }

    func cycleFlashMode() {
        guard isFlashAvailable else { return }
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        case .on: flashMode = .off
        @unknown default: flashMode = .off
        }
        objectWillChange.send()
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusPointOfInterestSupported {
                    d.focusPointOfInterest = devicePoint
                    if d.isFocusModeSupported(.autoFocus) {
                        d.focusMode = .autoFocus
                    }
                }
                if d.isExposurePointOfInterestSupported && !self.isManualExposureActiveSync {
                    d.exposurePointOfInterest = devicePoint
                    if d.isExposureModeSupported(.autoExpose) {
                        d.exposureMode = .autoExpose
                    }
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func setManualExposure(iso: Float, duration: Double) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            let clampedISO = max(d.activeFormat.minISO, min(iso, d.activeFormat.maxISO))
            let minDur = CMTimeGetSeconds(d.activeFormat.minExposureDuration)
            let maxDur = CMTimeGetSeconds(d.activeFormat.maxExposureDuration)
            let clampedDur = max(minDur, min(duration, maxDur))
            let cmDur = CMTime(seconds: clampedDur, preferredTimescale: 1_000_000)
            do {
                try d.lockForConfiguration()
                if d.isExposureModeSupported(.custom) {
                    d.setExposureModeCustom(duration: cmDur, iso: clampedISO, completionHandler: nil)
                    self.isManualExposureActiveSync = true
                    DispatchQueue.main.async { self.isManualExposureActive = true }
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func resetAutoExposure() {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.isExposureModeSupported(.continuousAutoExposure) {
                    d.exposureMode = .continuousAutoExposure
                }
                self.isManualExposureActiveSync = false
                DispatchQueue.main.async { self.isManualExposureActive = false }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            let b = max(d.minExposureTargetBias, min(bias, d.maxExposureTargetBias))
            do {
                try d.lockForConfiguration()
                d.setExposureTargetBias(b, completionHandler: nil)
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func capturePhoto(nightMode: Bool = false, raw: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            guard self.session.isRunning else { return }

            if raw {
                let rawTypes = self.photoOutput.availableRawPhotoPixelFormatTypes
                if let rawType = rawTypes.first {
                    let settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
                    if #available(iOS 13.0, *) {
                        settings.photoQualityPrioritization = .quality
                    }
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                    return
                }
            }

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            if #available(iOS 13.0, *) {
                settings.photoQualityPrioritization = nightMode ? .quality : .balanced
            }

            if livePhotoCapable, photoOutput.isLivePhotoCaptureEnabled, livePhotoEnabled {
                let tmpMovie = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LP_\(Int(Date().timeIntervalSince1970 * 1000)).mov")
                if photoOutput.availableLivePhotoVideoCodecTypes.contains(.hevc) {
                    settings.livePhotoVideoCodecType = .hevc
                }
                settings.livePhotoMovieFileURL = tmpMovie
                pendingLivePhotoMovieURL = tmpMovie
            } else {
                pendingLivePhotoMovieURL = nil
            }
            if nightMode {
                do {
                    try d.lockForConfiguration()
                    if d.exposureMode != .custom { d.exposureMode = .continuousAutoExposure }
                    let duration = CMTime(value: 1, timescale: 12)
                    let iso = min(d.activeFormat.maxISO, max(d.iso, d.activeFormat.maxISO * 0.75))
                    d.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
                    d.unlockForConfiguration()
                } catch {}
                settings.flashMode = .off
            } else if d.hasFlash && d.position == .back {
                settings.flashMode = self.flashMode
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private let recordCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private var lutCache: [String: (Data, Int)] = [:]

    var activeLUT: CubeLUT?
    var activeLUTIntensity: Double = 1.0

    var videoSharpenEnabled = true
    var livePhotoCapable = false
    var livePhotoEnabled = true
    var pendingLivePhotoMovieURL: URL?

    var onPhotoWithLiveMovie: ((UIImage, URL?) -> Void)?

    var faceDetectionEnabled = true
    var faceSkip = 0
    @Published var faceBoxes: [CGRect] = []
    @Published var torchOn = false

    func startRecording(beautyEnabled: Bool, beautyLevel: Float, filter: FilterPreset) -> Bool {
        let isFront = cameraPosition == .front
        recorder.frameProvider = { [weak self] raw in
            self?.makeVideoFrame(raw, beauty: beautyEnabled, level: beautyLevel, filter: filter, isFront: isFront)
        }
        return recorder.startRecording()
    }
    func pauseRecording() { recorder.pause() }
    func resumeRecording() { recorder.resume() }
    func stopRecording(completion: @escaping (Bool) -> Void) {
        recorder.finishRecording(completion: completion)
    }
    var isRecording: Bool { recorder.isRecording }
    var isRecordingPaused: Bool { recorder.isPaused }

    private func makeVideoFrame(_ raw: CVPixelBuffer, beauty: Bool, level: Float, filter: FilterPreset, isFront: Bool) -> CVPixelBuffer? {
        var image = CIImage(cvPixelBuffer: raw).oriented(isFront ? .leftMirrored : .right)
        if beauty { image = BeautyProcessor.apply(image, level: level) }
        image = filter.apply(image)
        if let lut = activeLUT {
            image = CubeLUTParser.apply(image, lut: lut, cache: &lutCache, intensity: activeLUTIntensity)
        }
        if videoSharpenEnabled { image = SRPipeline.videoFrameEnhance(image) }
        let ext = image.extent
        guard ext.width > 2, ext.height > 2 else { return nil }
        let w = Int(ext.width / 2) * 2
        let h = Int(ext.height / 2) * 2
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard let outBuf = out else { return nil }
        recordCIContext.render(image, to: outBuf)
        return outBuf
    }

    @Published var liveISO: Int = 0
    @Published var liveShutter: Double = 0
    private var hudTimer: Timer?

    func startParameterHUD() {
        guard hudTimer == nil else { return }
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                guard let self = self, let d = self.currentDevice else { return }
                let iso = Int(d.iso)
                let dur = CMTimeGetSeconds(d.exposureDuration)
                DispatchQueue.main.async {
                    self.liveISO = iso
                    self.liveShutter = dur
                }
            }
        }
    }

    var isoText: String {
        liveISO >= 1000 ? String(liveISO / 1000) + "k" : String(liveISO)
    }

    var shutterText: String {
        if liveShutter <= 0 { return "—" }
        if liveShutter >= 1 { return String(format: "%.0fs", liveShutter) }
        return String(format: "1/%.0f", 1.0 / liveShutter)
    }

    func setFrontMirror(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            var conns: [AVCaptureConnection] = []
            if let c = self.photoOutput.connection(with: .video) { conns.append(c) }
            if let c = self.videoOutput.connection(with: .video) { conns.append(c) }
            for conn in conns where conn.isVideoMirroringSupported {
                conn.isVideoMirrored = on && conn.inputPorts.first?.sourceDevicePosition == .front
            }
        }
    }

    func setManualFocus(_ position: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice,
                  d.isFocusModeSupported(.locked) else { return }
            do {
                try d.lockForConfiguration()
                if d.focusMode != .locked { d.focusMode = .locked }
                d.setFocusModeLocked(lensPosition: position, completionHandler: nil)
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func resumeAutoFocus() {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusModeSupported(.continuousAutoFocus) {
                    d.focusMode = .continuousAutoFocus
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice, d.hasTorch else { return }
            do {
                try d.lockForConfiguration()
                d.torchMode = on ? .on : .off
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func setVideoStabilization() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.videoOutput.connection(with: .video)?.isVideoStabilizationSupported == true {
                self.videoOutput.connection(with: .video)?.preferredVideoStabilizationMode = .auto
            }
        }
    }

    func detectFaces(in buffer: CVPixelBuffer) {
        guard faceDetectionEnabled else { return }
        faceSkip += 1
        guard faceSkip % 15 == 0 else { return }
        let ci = CIImage(cvPixelBuffer: buffer).oriented(.right)
        let handler = VNImageRequestHandler(ciImage: ci, options: [:])
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            guard let results = req.results as? [VNFaceObservation] else { return }
            let boxes = results.map { f -> CGRect in
                let b = f.boundingBox

                return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            }
            DispatchQueue.main.async { self?.faceBoxes = boxes }
        }
        try? handler.perform([request])
    }

    func lockExposure() {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.exposureMode == .continuousAutoExposure || d.exposureMode == .autoExpose {
                    d.exposureMode = .locked
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func unlockExposure() {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.exposureMode == .locked && !self.isManualExposureActiveSync {
                    if d.isExposureModeSupported(.continuousAutoExposure) {
                        d.exposureMode = .continuousAutoExposure
                    }
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func applyVideoFrameRate(high: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            let target: Int32 = high ? 60 : 30
            let supported = d.activeFormat.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(target) }
            guard supported else { return }
            do {
                try d.lockForConfiguration()
                d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: target)
                d.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: target)
                d.unlockForConfiguration()
            } catch {}
        }
    }

    func setVideoResolution(ultraHD: Bool) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if ultraHD {

                if let d = self.currentDevice,
                   let fmt = d.formats.first(where: { f in
                       let dims = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                       return dims.width >= 3840 && dims.height >= 2160
                   }) {
                    self.session.sessionPreset = .inputPriority
                    _ = fmt
                }
            } else {
                self.session.sessionPreset = .high
            }
            self.session.commitConfiguration()
        }
    }

    func addNightFrame(_ image: UIImage) {
        nightFrames.append(image)
    }

    func resetNightFrames() {
        nightFrames.removeAll()
    }

    func setWhiteBalanceKelvin(_ kelvin: CGFloat) {
        let k = Float(kelvin)
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            guard d.isWhiteBalanceModeSupported(.locked) else { return }
            do {
                try d.lockForConfiguration()
                let tt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: k, tint: Float(0))
                let g = d.deviceWhiteBalanceGains(for: tt)
                let hi = d.maxWhiteBalanceGain
                let clamped = AVCaptureDevice.WhiteBalanceGains(
                    redGain: min(max(g.redGain, 1.0), hi),
                    greenGain: min(max(g.greenGain, 1.0), hi),
                    blueGain: min(max(g.blueGain, 1.0), hi))
                d.setWhiteBalanceModeLocked(with: clamped)
                d.unlockForConfiguration()
            } catch {
            }
        }
    }

    func resetWhiteBalance() {
        sessionQueue.async { [weak self] in
            guard let self = self, let d = self.currentDevice else { return }
            do {
                try d.lockForConfiguration()
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    d.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                d.unlockForConfiguration()
            } catch {}
        }
    }

    var hasUltraWide: Bool {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    private var isOnUltraWide = false

    func switchToUltraWide() {
        sessionQueue.async { [weak self] in
            guard let self = self, let oldInput = self.videoInput, !self.isOnUltraWide else { return }
            guard let uw = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: uw) else { return }
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
                self.currentDevice = uw
                self.isOnUltraWide = true
                DispatchQueue.main.async {
                    self.zoomFactor = 1.0
                    self.refreshCapabilities()
                }
            } else {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()
            if wasRunning && !self.session.isRunning { self.session.startRunning() }
        }
    }

    func switchToWide() {
        sessionQueue.async { [weak self] in
            guard let self = self, let oldInput = self.videoInput, self.isOnUltraWide else { return }
            guard let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: wide) else { return }
            let wasRunning = self.session.isRunning
            if wasRunning { self.session.stopRunning() }
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
                self.currentDevice = wide
                self.isOnUltraWide = false
                DispatchQueue.main.async {
                    self.zoomFactor = 1.0
                    self.refreshCapabilities()
                }
            } else {
                self.session.addInput(oldInput)
            }
            self.session.commitConfiguration()
            if wasRunning && !self.session.isRunning { self.session.startRunning() }
        }
    }
}

extension CameraEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onVideoFrame?(pixelBuffer)
        FrameAnalyzer.shared.analyze(pixelBuffer)
        detectFaces(in: pixelBuffer)
        if recorder.isRecording {
            recorder.appendVideo(sampleBuffer)
        }
    }
}

extension CameraEngine: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureAudioDataOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if recorder.isRecording {
            recorder.appendAudio(sampleBuffer)
        }
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil else { return }

        if photo.isRawPhoto {
            guard let data = photo.fileDataRepresentation() else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onRawPhotoCaptured?(data)

                if let ci = CIImage(data: data) {
                    let ctx = CIContext(options: [.useSoftwareRenderer: false])
                    if let cg = ctx.createCGImage(ci, from: ci.extent),
                       let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.92),
                       let jpgImg = UIImage(data: jpg) {
                        self?.onPhotoCaptured?(jpgImg)
                    }
                }
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let liveURL = self.pendingLivePhotoMovieURL
        self.pendingLivePhotoMovieURL = nil
        DispatchQueue.main.async { [weak self] in
            self?.onPhotoCaptured?(image)
            self?.onPhotoWithLiveMovie?(image, liveURL)
        }
    }
}

extension Notification.Name {
    static let cameraPermissionResult = Notification.Name("QingyaoCameraPermissionResult")
}
