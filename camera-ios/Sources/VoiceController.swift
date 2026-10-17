import Speech
import AVFoundation
import UIKit

final class VoiceController: NSObject, ObservableObject {

    static let shared = VoiceController()

    @Published var enabled = false
    @Published var lastHeard = ""
    @Published var listening = false

    private let speech = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    var onCommand: ((String) -> Void)?

    func toggle() {
        if enabled { stop() } else { start() }
    }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.lastHeard = "语音权限被拒"
                    return
                }
                self?.beginListening()
            }
        }
    }

    private func beginListening() {
        guard let recognizer = speech, recognizer.isAvailable else {
            lastHeard = "语音不可用"
            return
        }
        stopEngine()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            req.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            listening = true
            enabled = true
        } catch {
            lastHeard = "启动失败"
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                let last = text.split(separator: " ").suffix(3).joined(separator: " ")
                DispatchQueue.main.async {
                    self.lastHeard = last
                    self.dispatch(command: String(last))
                }
            }
            if error != nil || (result?.isFinal ?? false) {

                DispatchQueue.main.async {
                    if self.enabled { self.beginListening() }
                }
            }
        }
    }

    private func dispatch(command: String) {
        guard let handler = onCommand else { return }
        let cmds: [(keywords: [String], action: String)] = [
            (["拍照", "拍摄", "茄子", "snap"], "capture"),
            (["停止", "结束", "停"], "stop"),
            (["开始", "录制"], "record"),
            (["翻转", "切换"], "flip")
        ]
        for c in cmds where c.keywords.contains(where: { command.contains($0) }) {
            handler(c.action)
            break
        }
    }

    func stop() {
        enabled = false
        listening = false
        stopEngine()
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        listening = false
    }
}

enum PhotoStamper {

    static func stamp(_ image: UIImage, date: Date = Date()) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            let w = image.size.width
            let h = image.size.height

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let text = formatter.string(from: date)

            let fontSize = max(16, w * 0.028)
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let pad = fontSize * 0.6
            let bgRect = CGRect(x: w - size.width - pad * 3, y: h - size.height - pad * 2.2,
                                width: size.width + pad * 2, height: size.height + pad * 0.9)

            UIColor.black.withAlphaComponent(0.45).setFill()
            ctx.cgContext.fill(bgRect)

            (text as NSString).draw(in: CGRect(x: bgRect.minX + pad, y: bgRect.minY + pad * 0.45,
                                               width: size.width, height: size.height),
                                    withAttributes: attrs)
        }
    }
}
