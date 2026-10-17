import SwiftUI
import Combine
import AVFoundation
import Photos

enum CaptureStyle: String, CaseIterable {
    case normal = "标准"
    case hdrPlus = "HDR+"
    case ultra = "超清Pro"
    case hdr = "HDR"
    case dro = "DRO"
}

enum CaptureMode: String, CaseIterable {
    case photo = "照片"
    case video = "视频"
    case night = "夜视"
    case timelapse = "延时"
    case panorama = "全景"
}

enum PhotoRatio: String, CaseIterable {
    case r4x3 = "4:3"
    case r16x9 = "16:9"
    case r1x1 = "1:1"

    var value: CGFloat {
        switch self {
        case .r4x3: return 4.0 / 3.0
        case .r16x9: return 16.0 / 9.0
        case .r1x1: return 1.0
        }
    }

    var viewfinderAspect: CGFloat {
        return 1.0 / value
    }
}

enum CaptureTimer: String, CaseIterable {
    case off = "OFF"
    case s3 = "3s"
    case s10 = "10s"

    var seconds: Int {
        switch self {
        case .off: return 0
        case .s3: return 3
        case .s10: return 10
        }
    }
}

final class CameraViewModel: ObservableObject {

    let engine = CameraEngine()

    @Published var selectedFilterIndex = 0
    @Published var beautyEnabled = false
    @Published var beautyLevel: Float = 0.5

    @Published var proExpanded = false
    @Published var beautyPanelExpanded = false
    @Published var gridEnabled = true
    @Published var showPhotoViewer = false
    @Published var aiSourceImage: UIImage?
    @Published var showAIStudio = false
    @Published var lastPhoto: UIImage?
    @Published var isProcessing = false
    @Published var permissionDenied = false
    @Published var focusIndicator: CGPoint?
    @Published var flashHighlight = false

    @Published var mode: CaptureMode = .photo
    @Published var isRecording = false
    @Published var isRecordingPaused = false
    @Published var recordingSeconds = 0
    private var recordTimer: Timer?
    private var pendingNightFrames = 0

    @Published var captureStyle: CaptureStyle = .normal
    @Published var rawEnabled = false
    @Published var whiteBalanceK: Double = 5600
    private var hdrFrames: [UIImage] = []
    private var hdrStep = -1
    private var burstRemaining = 0

    @Published var showSettings = false
    @Published var gridStyle: GridStyle = .thirds
    @Published var exposureLocked = false
    @Published var timestampEnabled = false
    @Published var screenFlashEnabled = false
    @Published var slowMoEnabled = false
    @Published var highFrameRate = false
    @Published var voiceEnabled = false
    @Published var motionEnabled = false
    @Published var histogramEnabled = true
    @Published var zebraEnabled = true
    @Published var timelapseRunning = false
    @Published var timelapseInterval: Double = 1.0
    private var tlTickTimer: Timer?

    @Published var panoramaRunning = false
    @Published var volumeShutterEnabled = true
    @Published var slowShutterSeconds: Double = 0
    private var hdrPlusFrames: [UIImage] = []
    private var hdrPlusRemaining = 0
    private var ultraFrames: [UIImage] = []
    private var ultraRemaining = 0
    @Published var detailEnhanceEnabled = true
    @Published var focusPeakingEnabled = false

    @Published var fullScreenViewfinder = true

    @Published var video4K = false

    @Published var smartAuto = true

    @Published var aiSuperResolution = true {
        didSet { DetailEnhancer.aiSuperEnabled = aiSuperResolution }
    }
    @Published var videoSharpen = true {
        didSet { engine.videoSharpenEnabled = videoSharpen }
    }
    // 人像模式（v4.9：Vision 分割 + 背景虚化）
    @Published var portraitBlurEnabled = false
    @Published var portraitDepth: PortraitProcessor.Depth = .medium

    @Published var livePhotoEnabled = true {
        didSet { engine.livePhotoEnabled = livePhotoEnabled }
    }
    var pendingLiveMovie: URL?

    @Published var selectedLUTName: String? = UserDefaults.standard.string(forKey: "v8_lut")
    @Published var showLUTPanel = false
    static let allLUTs: [CubeLUT] = LUTStore.all()

    var activeLUT: CubeLUT? {
        guard let n = selectedLUTName else { return nil }
        return CameraViewModel.allLUTs.first { $0.file == n }
    }

    func selectLUT(_ lut: CubeLUT?) {
        selectedLUTName = lut?.file
        UserDefaults.standard.set(lut?.file, forKey: "v8_lut")
        Haptics.selection()
    }
    private var slowShutterFrames: [UIImage] = []
    private var slowShutterEnd: Date?
    private var volumeKVO: NSKeyValueObservation?
    private var panoTickTimer: Timer?

    @Published var photoRatio: PhotoRatio = .r4x3
    @Published var timerSetting: CaptureTimer = .off
    @Published var countdown: Int?
    @Published var capturedPhotos: [UIImage] = []

    @Published var proModeEnabled = false
    @Published var manualISO: Float = 100
    @Published var manualShutter: Double = 1.0 / 120.0
    @Published var manualBias: Float = 0

    var currentFilter: FilterPreset {
        FilterLibrary.presets[min(selectedFilterIndex, FilterLibrary.presets.count - 1)]
    }

    private var gestureBaseZoom: CGFloat = 1.0
    private var isZooming = false
    private var permissionObserver: NSObjectProtocol?

    init() {
        engine.onPhotoCaptured = { [weak self] image in
            self?.handleCaptured(image)
        }

        permissionObserver = NotificationCenter.default.addObserver(
            forName: .cameraPermissionResult,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let granted = note.userInfo?["granted"] as? Bool {
                self?.permissionDenied = !granted
            }
        }

        engine.onRawPhotoCaptured = { [weak self] data in
            self?.saveDNG(data)
            DispatchQueue.main.async { self?.isProcessing = false }
        }

        engine.onPhotoWithLiveMovie = { [weak self] _, movieURL in
            self?.pendingLiveMovie = movieURL
        }

        engine.startParameterHUD()
        DetailEnhancer.aiSuperEnabled = aiSuperResolution

        tlTickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.timelapseTick()
        }

        panoTickTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.panoramaTick()
        }

        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetooth])
        try? AVAudioSession.sharedInstance().setActive(true)
        volumeKVO = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, self.volumeShutterEnabled,
                  let new = change.newValue, new > 0.06 else { return }
            DispatchQueue.main.async {
                guard self.countdown == nil, !self.isProcessing else { return }
                self.capture()
            }
        }
    }

    deinit {
        if let observer = permissionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        engine.start()
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }

    func stop() {
        engine.stop()
    }

    func openAIStudio(with image: UIImage?) {
        aiSourceImage = image ?? lastPhoto
        showAIStudio = true
    }

    func capture() {
        switch mode {
        case .video:
            toggleRecording()
        case .timelapse:
            guard !isProcessing else { return }
            toggleTimelapse()
        case .panorama:
            togglePanorama()
        case .night:
            guard !isProcessing, countdown == nil else { return }
            startNightCapture()
        case .photo:
            guard !isProcessing, countdown == nil else { return }
            if rawEnabled {

                isProcessing = true
                performCapture(night: false, raw: true)
            } else if captureStyle == .hdrPlus || (smartAuto && captureStyle == .normal && engine.liveISO > 900) {

                startHDRPlus()
            } else if captureStyle == .ultra {

                startUltraCapture()
            } else if captureStyle == .hdr {
                startHDRCapture()
            } else if slowShutterSeconds > 0 {

                isProcessing = true
                startSlowShutter()
            } else if timerSetting == .off {
                performCapture(night: false)
            } else {
                countdown = timerSetting.seconds
                tickCountdown()
            }
        }
    }

    private func performCapture(night: Bool, raw: Bool = false) {
        flashHighlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.flashHighlight = false
        }
        engine.capturePhoto(nightMode: night, raw: raw)
    }

    private func startHDRCapture() {
        isProcessing = true
        hdrFrames.removeAll()
        hdrStep = 0
        engine.setExposureBias(-1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performCapture(night: false)
        }
    }

    func startBurst() {
        guard !isProcessing else { return }
        burstRemaining = 10
        flashHighlight = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.flashHighlight = false
        }
        fireBurst()
    }

    private func fireBurst() {
        guard burstRemaining > 0 else { return }
        burstRemaining -= 1
        engine.capturePhoto(nightMode: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.fireBurst()
        }
    }

    func applyWhiteBalance() {
        engine.setWhiteBalanceKelvin(CGFloat(whiteBalanceK))
    }

    func autoWhiteBalance() {
        engine.resetWhiteBalance()
    }

    @Published var onUltraWide = false

    func cycleStyle() {
        switch captureStyle {
        case .normal: captureStyle = .hdrPlus
        case .hdrPlus: captureStyle = .ultra
        case .ultra: captureStyle = .hdr
        case .hdr: captureStyle = .dro
        case .dro: captureStyle = .normal
        }
        Haptics.selection()
    }

    func toggleUltraWide() {
        if onUltraWide {
            engine.switchToWide()
            onUltraWide = false
        } else {
            engine.switchToUltraWide()
            onUltraWide = true
        }
    }

    func goWideZoom(_ x: Int) {
        if onUltraWide {
            engine.switchToWide()
            onUltraWide = false
        }
        if x >= 2 {
            engine.setZoom(CGFloat(x))
        } else {
            engine.setZoom(1.0)
        }
    }

    private func startNightCapture() {
        isProcessing = true
        engine.resetNightFrames()
        pendingNightFrames = NightModeProcessor.frameCount
        for i in 0..<NightModeProcessor.frameCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) { [weak self] in
                self?.performCapture(night: true)
            }
        }
    }

    let panorama = PanoramaProcessor()

    private func togglePanorama() {
        if panoramaRunning {
            panoramaRunning = false
            panorama.stopAndStitch { [weak self] pano in
                guard let self = self, let pano = pano else { return }
                self.savePanorama(pano)
            }
        } else {
            panorama.start()
            panoramaRunning = true
        }
    }

    private func panoramaTick() {
        guard panoramaRunning else { return }
        engine.capturePhoto(nightMode: false)
    }

    private func savePanorama(_ pano: UIImage) {
        guard let jpeg = pano.jpegData(compressionQuality: 0.95) else { return }
        savePhoto(jpeg)
        DispatchQueue.main.async {
            self.lastPhoto = pano
            Haptics.capture()
            self.capturedPhotos.insert(pano, at: 0)
        }
    }

    private func startHDRPlus() {
        hdrPlusFrames = []
        hdrPlusRemaining = 8
        engine.capturePhoto(nightMode: false)
    }

    private func startUltraCapture() {
        ultraFrames = []
        ultraRemaining = 4
        DetailEnhancer.currentISOHint = engine.liveISO
        engine.capturePhoto(nightMode: false)
    }

    private func startSlowShutter() {
        guard slowShutterSeconds > 0 else { return }
        slowShutterFrames = []
        slowShutterEnd = Date().addingTimeInterval(slowShutterSeconds)
        engine.capturePhoto(nightMode: false)
    }

    private func slowShutterTick() {
        guard let end = slowShutterEnd else { return }
        if Date() < end {
            engine.capturePhoto(nightMode: false)
        } else {
            slowShutterEnd = nil
            let frames = slowShutterFrames
            slowShutterFrames = []
            isProcessing = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let out = SlowShutterProcessor.average(frames) ?? frames.first
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    guard let img = out else { return }
                    var processed = img.fixOrientation()
                    if let r = self?.photoRatio { processed = processed.cropped(toRatio: r.value) }
                    if let jpeg = processed.jpegData(compressionQuality: 0.95) {
                        self?.savePhoto(jpeg)
                    }
                    self?.lastPhoto = processed
                    Haptics.capture()
                        self?.capturedPhotos.insert(processed, at: 0)
                }
            }
        }
    }

    let timelapse = TimeLapseRecorder()

    private func toggleTimelapse() {
        if timelapseRunning {
            timelapseRunning = false
            timelapse.stopAndRender { ok in

            }
        } else {
            timelapse.interval = timelapseInterval
            timelapse.start()
            timelapseRunning = true
        }
    }

    private func timelapseTick() {
        guard timelapseRunning else { return }
        timelapse.tickElapsed()
        guard timelapse.shouldCapture() else { return }
        engine.capturePhoto(nightMode: false)
    }

    func handleVoiceCommand(_ cmd: String) {
        switch cmd {
        case "capture":
            capture()
        case "record":
            if mode != .video { mode = .video }
            capture()
        case "stop":
            if engine.isRecording { finishRecording() }
            if timelapseRunning { toggleTimelapse() }
        case "flip":
            engine.switchCamera()
        default:
            break
        }
    }

    func applyVideoFrameRate() {
        engine.applyVideoFrameRate(high: highFrameRate)
    }

    func toggleExposureLock() {
        exposureLocked.toggle()
        Haptics.medium()
        if exposureLocked {
            engine.lockExposure()
        } else {
            engine.unlockExposure()
        }
    }

    private var longPressBurstOn = false
    private var longPressTimer: Timer?

    func startLongPressBurst() {
        guard !longPressBurstOn, mode == .photo, !isProcessing,
              captureStyle == .normal || captureStyle == .hdrPlus || captureStyle == .ultra else { return }
        longPressBurstOn = true
        Haptics.medium()
        engine.capturePhoto(nightMode: false)
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { [weak self] _ in
            guard let self = self, self.longPressBurstOn else { return }
            self.engine.capturePhoto(nightMode: false)
        }
    }

    func stopLongPressBurst() {
        guard longPressBurstOn else { return }
        longPressBurstOn = false
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    @Published var manualFocus: Double = -1
    @Published var lutIntensity: Double = (UserDefaults.standard.double(forKey: "v8_lut_int") == 0 ? 1.0 : UserDefaults.standard.double(forKey: "v8_lut_int"))
    @Published var cinematicEnabled = false

    func setManualFocus(_ position: Double) {
        manualFocus = position
        engine.setManualFocus(Float(position))
    }

    func resetFocus() {
        manualFocus = -1
        engine.resumeAutoFocus()
    }

    func setLUTIntensity(_ v: Double) {
        lutIntensity = v
        UserDefaults.standard.set(v, forKey: "v8_lut_int")
    }

    @Published var evBias: Float = 0
    @Published var showEVSlider = false
    @Published var mirrorFront = false

    func setEV(_ bias: Float) {
        evBias = bias
        engine.setExposureBias(bias)
    }

    func toggleTorch() {
        engine.torchOn.toggle()
        Haptics.light()
        engine.setTorch(engine.torchOn)
    }

    func setFrontMirror(_ on: Bool) {
        mirrorFront = on
        engine.setFrontMirror(on)
    }

    func captureDuringRecording() {
        engine.capturePhoto(nightMode: false)
    }

    func resetAllSettings() {
        captureStyle = .normal
        rawEnabled = false
        whiteBalanceK = 5600
        gridStyle = .thirds
        timestampEnabled = false
        screenFlashEnabled = false
        slowMoEnabled = false
        highFrameRate = false
        voiceEnabled = false
        motionEnabled = false
        histogramEnabled = true
        zebraEnabled = true
        volumeShutterEnabled = true
        slowShutterSeconds = 0
        detailEnhanceEnabled = true
        focusPeakingEnabled = false
        fullScreenViewfinder = true
        video4K = false
        smartAuto = true
        livePhotoEnabled = true
        selectedLUTName = nil
        evBias = 0
        Haptics.warning()
    }

    private func toggleRecording() {
        if engine.isRecording {
            finishRecording()
        } else {
            let ok = slowMoEnabled
                ? engine.recorder.startSlowMoRecording()
                : engine.startRecording(beautyEnabled: beautyEnabled,
                                        beautyLevel: beautyLevel,
                                        filter: currentFilter)
            engine.activeLUT = activeLUT
            engine.activeLUTIntensity = lutIntensity
            if ok {
                isRecording = true
                Haptics.heavy()
                isRecordingPaused = false
                recordingSeconds = 0
                recordTimer?.invalidate()
                recordTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    self?.recordingSeconds += 1
                }
            }
        }
    }

    func togglePauseRecording() {
        if engine.isRecordingPaused {
            engine.resumeRecording()
            isRecordingPaused = false
        } else if engine.isRecording {
            engine.pauseRecording()
            isRecordingPaused = true
        }
    }

    func finishRecording() {
        guard engine.isRecording else { return }
        recordTimer?.invalidate()
        recordTimer = nil
        engine.stopRecording { [weak self] _ in
            Haptics.medium()
                    self?.isRecording = false
            self?.isRecordingPaused = false
            self?.recordingSeconds = 0
        }
    }

    private func tickCountdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, let c = self.countdown else { return }
            if c <= 1 {
                self.countdown = nil
                self.performCapture(night: false)
            } else {
                self.countdown = c - 1
                self.tickCountdown()
            }
        }
    }

    private func handleCaptured(_ image: UIImage) {

        if mode == .timelapse && timelapseRunning {
            timelapse.addFrame(image)
            return
        }

        if mode == .panorama && panoramaRunning {
            panorama.addFrame(image)
            return
        }

        if hdrPlusRemaining > 0 {
            hdrPlusFrames.append(image)
            hdrPlusRemaining -= 1
            if hdrPlusRemaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.engine.capturePhoto(nightMode: false)
                }
            } else {
                let frames = hdrPlusFrames
                hdrPlusFrames = []
                isProcessing = true
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let merged = HDRPlusProcessor.merge(frames)
                    DispatchQueue.main.async {
                        self?.isProcessing = false
                        guard let img = merged else { return }
                        if let jpeg = img.jpegData(compressionQuality: 0.95) {
                            self?.savePhoto(jpeg)
                        }
                        self?.lastPhoto = img
                        Haptics.capture()
                        self?.capturedPhotos.insert(img, at: 0)
                    }
                }
            }
            return
        }

        if ultraRemaining > 0 {
            ultraFrames.append(image)
            ultraRemaining -= 1
            if ultraRemaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.engine.capturePhoto(nightMode: false)
                }
            } else {
                let frames = ultraFrames
                ultraFrames = []
                isProcessing = true
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let merged = DetailEnhancer.alignMerge(frames)
                    DispatchQueue.main.async {
                        self?.isProcessing = false
                        guard let img = merged else { return }
                        if let jpeg = img.jpegData(compressionQuality: 0.98) {
                            self?.savePhoto(jpeg)
                        }
                        self?.lastPhoto = img
                        Haptics.capture()
                        self?.capturedPhotos.insert(img, at: 0)
                    }
                }
            }
            return
        }

        if slowShutterEnd != nil {
            slowShutterFrames.append(image)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.slowShutterTick()
            }
            return
        }

        if captureStyle == .hdr && hdrStep >= 0 {
            hdrFrames.append(image)
            hdrStep += 1
            if hdrStep == 1 {
                engine.setExposureBias(0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.performCapture(night: false)
                }
            } else if hdrStep == 2 {
                engine.setExposureBias(1.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.performCapture(night: false)
                }
            } else {

                engine.setExposureBias(0)
                hdrStep = -1
                isProcessing = true
                let dark = hdrFrames.count > 0 ? hdrFrames[0] : image
                let base = hdrFrames.count > 1 ? hdrFrames[1] : image
                let bright = hdrFrames.count > 2 ? hdrFrames[2] : image
                hdrFrames.removeAll()
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    var result = HDRProcessor.mergeHDR(dark: dark, base: base, bright: bright) ?? base
                    let ratio = self?.photoRatio ?? .r4x3
                    result = result.cropped(toRatio: ratio.value)
                    if let jpeg = result.jpegData(compressionQuality: 0.95) {
                        self?.savePhoto(jpeg)
                    }
                    DispatchQueue.main.async {
                        self?.lastPhoto = result
                        Haptics.capture()
                        self?.capturedPhotos.insert(result, at: 0)
                        self?.isProcessing = false
                    }
                }
            }
            return
        }

        if mode == .night {
            engine.addNightFrame(image)
            pendingNightFrames -= 1
            if pendingNightFrames <= 0 {
                isProcessing = true
                let frames = engine.nightFrames
                engine.resetNightFrames()
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let stitched = NightModeProcessor.stitch(frames) else {
                        DispatchQueue.main.async { self?.isProcessing = false }
                        return
                    }
                    if let jpeg = stitched.jpegData(compressionQuality: 0.95) {
                        self?.savePhoto(jpeg)
                    }
                    DispatchQueue.main.async {
                        self?.lastPhoto = stitched
                        Haptics.capture()
                        self?.capturedPhotos.insert(stitched, at: 0)
                        self?.isProcessing = false
                    }
                }
            }
            return
        }

        isProcessing = true
        let filter = currentFilter
        let beautyOn = beautyEnabled
        let beautyLv = beautyLevel
        let ratio = photoRatio

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var processed = PhotoProcessor.process(
                image,
                filter: filter,
                beautyEnabled: beautyOn,
                beautyLevel: beautyLv
            )
            processed = processed.cropped(toRatio: ratio.value)

            if self?.captureStyle == .dro {
                if let dro = HDRProcessor.dro(processed) { processed = dro }
            }

            if self?.detailEnhanceEnabled == true {
                processed = DetailEnhancer.enhance(processed)
                if self?.aiSuperResolution == true, engine.liveISO > 300 {
                    if let sr = SRPipeline.denoise(processed, iso: engine.liveISO) {
                        processed = sr
                    }
                }
            }

            // 人像模式（v4.9：Vision 分割 + 背景虚化）
            if self?.portraitBlurEnabled == true {
                processed = PortraitProcessor.blur(processed, depth: self?.portraitDepth ?? .medium)
            }

            if let lut = self?.activeLUT {
                var ci = CIImage(image: processed) ?? CIImage()
                var cache: [String: (Data, Int)] = [:]
                ci = CubeLUTParser.apply(ci, lut: lut, cache: &cache, intensity: self?.lutIntensity ?? 1.0)
                let ctx = CIContext(options: [.useSoftwareRenderer: false])
                if let cg = ctx.createCGImage(ci, from: ci.extent) {
                    processed = UIImage(cgImage: cg, scale: processed.scale, orientation: processed.imageOrientation)
                }
            }

            if self?.timestampEnabled == true {
                processed = PhotoStamper.stamp(processed)
            }

            if let jpeg = processed.jpegData(compressionQuality: 0.95) {
                self?.savePhoto(jpeg)
            }

            DispatchQueue.main.async {
                self?.lastPhoto = processed
                Haptics.capture()
                        self?.capturedPhotos.insert(processed, at: 0)
                self?.isProcessing = false
            }
        }
    }

    private func savePhoto(_ jpeg: Data) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()

            if let movieURL = pendingLiveMovie,
               FileManager.default.fileExists(atPath: movieURL.path) {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .photo, data: jpeg, options: nil)
                request.addResource(with: .pairedVideo, fileURL: movieURL, options: options)
                pendingLiveMovie = nil
            } else {
                request.addResource(with: .photo, data: jpeg, options: nil)
            }
        }) { success, _ in
            if !success {

                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = docs.appendingPathComponent("IMG_\(Int(Date().timeIntervalSince1970)).jpg")
                try? jpeg.write(to: url)
            }
        }
    }

    private func saveDNG(_ data: Data) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }) { success, _ in
            if !success {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = docs.appendingPathComponent("IMG_\(Int(Date().timeIntervalSince1970)).dng")
                try? data.write(to: url)
            }
        }
    }

    func cycleRatio() {
        switch photoRatio {
        case .r4x3: photoRatio = .r16x9
        case .r16x9: photoRatio = .r1x1
        case .r1x1: photoRatio = .r4x3
        }
    }

    func cycleTimer() {
        switch timerSetting {
        case .off: timerSetting = .s3
        case .s3: timerSetting = .s10
        case .s10: timerSetting = .off
        }
    }

    func handleZoomGesture(_ scale: CGFloat) {
        if !isZooming {
            isZooming = true
            gestureBaseZoom = engine.zoomFactor
        }
        engine.setZoom(gestureBaseZoom * scale)
    }

    func endZoomGesture(_ scale: CGFloat) {
        isZooming = false
        gestureBaseZoom = engine.zoomFactor
    }

    func handleTapToFocus(at viewPoint: CGPoint, in viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let nx = min(max(viewPoint.x / viewSize.width, 0), 1)
        let ny = min(max(viewPoint.y / viewSize.height, 0), 1)

        let devicePoint: CGPoint
        if engine.cameraPosition == .front {
            devicePoint = CGPoint(x: ny, y: nx)
        } else {
            devicePoint = CGPoint(x: ny, y: 1.0 - nx)
        }
        engine.focus(at: devicePoint)

        focusIndicator = CGPoint(x: nx, y: ny)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.focusIndicator = nil
        }

        Haptics.light()
        showEVSlider = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            withAnimation(DS.easeOut) { self?.showEVSlider = false }
        }
    }

    func applyManualExposure() {
        engine.setManualExposure(iso: manualISO, duration: manualShutter)
    }

    func applyBias() {
        engine.setExposureBias(manualBias)
    }

    func resetProExposure() {
        proModeEnabled = false
        manualISO = 100
        manualShutter = 1.0 / 120.0
        manualBias = 0
        engine.resetAutoExposure()
        engine.setExposureBias(0)
    }
}
