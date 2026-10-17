import SwiftUI
import PhotosUI
import Photos

enum AIAction: String, CaseIterable, Identifiable {
    case enhance = "AI 增强"
    case grade = "AI 调色"
    case retouch = "AI 精修"
    case erase = "AI 消除"
    case custom = "自由指令"

    var id: String { rawValue }

    var icon: AppIcon {
        switch self {
        case .enhance: return .sparkles
        case .grade: return .brush
        case .retouch: return .wand
        case .erase: return .eraser
        case .custom: return .check
        }
    }

    var subtitle: String {
        switch self {
        case .enhance: return "清晰度 · 细节"
        case .grade: return "色彩 · 氛围"
        case .retouch: return "人像 · 美化"
        case .erase: return "涂抹消除"
        case .custom: return "自由描述"
        }
    }
}

struct AIStudioView: View {
    @EnvironmentObject var vm: CameraViewModel
    @Environment(\.dismiss) var dismiss

    @State private var workingImage: UIImage?
    @State private var resultImage: UIImage?
    @State private var isProcessing = false
    @State private var errorText: String?
    @State private var quality: AgnesClient.Quality = .ultra2K
    @State private var processedSeconds = 0
    @State private var saveMessage: String?

    @State private var showCustomInput = false
    @State private var customText = ""
    @State private var showEraseEditor = false

    @State private var pickerItem: PhotosPickerItem?

    private let timerPub = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.spaceGradient(Theme.bg)

            VStack(spacing: 12) {
                header
                imageArea
                if let err = errorText { errorBanner(err) }
                if let msg = saveMessage { saveBanner(msg) }
                if workingImage != nil && resultImage == nil && !isProcessing {
                    actionGrid
                    modeToggle
                }
                bottomButtons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .onAppear { workingImage = vm.aiSourceImage ?? vm.lastPhoto }
        .onReceive(timerPub) { _ in
            if isProcessing { processedSeconds += 1 }
        }
        .alert("自由指令", isPresented: $showCustomInput) {
            TextField("例如：变成赛博朋克夜景", text: $customText)
            Button("执行") { run(.custom) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("描述你想要的修图效果")
        }
        .fullScreenCover(isPresented: $showEraseEditor) {
            if let img = workingImage {
                EraseMaskEditor(image: img) { marked in
                    runErase(marked: marked)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("AI STUDIO")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.cyan)
                .kerning(2)
            Spacer()
            Button {
                dismiss()
            } label: {
                AppIconView(name: .close, size: 20, lineWidth: 2.2, color: Theme.textDim)
                    .frame(width: 38, height: 38)
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var imageArea: some View {
        if let result = resultImage, let input = workingImage {
            VStack(spacing: 6) {
                CompareSlider(before: input, after: result)
                    .frame(maxHeight: 420)
                MonoLabel(text: "◀ 处理前 · 处理后 ▶（拖动对比）", size: 10, color: Theme.cyanDim)
            }
        } else if let input = workingImage {
            ZStack {
                Image(uiImage: input)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 420)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.hairline, lineWidth: 0.8)
                    )
                if isProcessing {
                    processingOverlay
                }
            }
        } else {
            pickerArea
        }
    }

    private var processingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.cyan)
            MonoLabel(text: "AI 处理中… \(processedSeconds)s", size: 13, color: Theme.cyan)
            MonoLabel(text: quality == .ultra2K ? "超清 2K · 约需 25~50 秒" : "快速模式 · 约需 15~30 秒",
                      size: 10, color: Theme.textDim)
        }
        .padding(24)
        .background(.ultraThinMaterial.opacity(0.9))
        .cornerRadius(16)
    }

    private var pickerArea: some View {
        VStack(spacing: 16) {
            AppIconView(name: .wand, size: 40, lineWidth: 1.5, color: Theme.cyan)
            MonoLabel(text: "选择一张照片开始 AI 修图", size: 13, color: Theme.textDim)

            if vm.lastPhoto != nil {
                Button {
                    workingImage = vm.lastPhoto
                } label: {
                    labelChip("使用最近拍摄")
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                labelChip("从相册选择")
            }
            .onChange(of: pickerItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { workingImage = img }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(Theme.panelBackground())
    }

    private func labelChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.cyan)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.cyan.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.cyan.opacity(0.4), lineWidth: 0.8)
                    )
            )
    }

    private var actionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(AIAction.allCases) { action in
                Button {
                    switch action {
                    case .erase:
                        showEraseEditor = true
                    case .custom:
                        customText = ""
                        showCustomInput = true
                    default:
                        run(action)
                    }
                } label: {
                    VStack(spacing: 5) {
                        AppIconView(name: action.icon, size: 19, lineWidth: 1.6, color: .white)
                        Text(action.rawValue.replacingOccurrences(of: "AI ", with: ""))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                        Text(action.subtitle)
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundColor(Theme.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.panel.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.hairline, lineWidth: 0.7)
                            )
                    )
                }
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 8) {
            MonoLabel(text: "画质", size: 11, color: Theme.textDim)
            modeButton("超清 2K", active: quality == .ultra2K) { quality = .ultra2K }
            modeButton("快速", active: quality == .fast) { quality = .fast }
            Spacer()
            MonoLabel(text: quality == .ultra2K ? "默认 · 输出约 5.6MP" : "省时 · 输出约 0.8MP",
                      size: 9, color: Theme.textFaint)
        }
    }

    private func modeButton(_ title: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : Theme.textDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(active ? Theme.cyan : Theme.panel)
                )
        }
    }

    @ViewBuilder
    private var bottomButtons: some View {
        if resultImage != nil {
            HStack(spacing: 10) {
                studioButton("保存到相册", icon: .download, accent: true) { saveResult() }
                studioButton("继续处理", icon: .rotateCCW, accent: false) {
                    workingImage = resultImage
                    resultImage = nil
                    errorText = nil
                    saveMessage = nil
                }
                studioButton("换一张", icon: .photo, accent: false) {
                    workingImage = nil
                    resultImage = nil
                    errorText = nil
                    saveMessage = nil
                }
            }
        }
    }

    private func studioButton(_ title: String, icon: AppIcon, accent: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 6) {
                AppIconView(name: icon, size: 14, lineWidth: 2, color: accent ? .black : .white)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(accent ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent ? Theme.cyan : Theme.panel)
            )
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.12))
            )
    }

    private func saveBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundColor(Theme.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.cyan.opacity(0.1))
            )
    }

    private func buildPrompt(action: AIAction) -> String {
        switch action {
        case .enhance:
            return "Greatly enhance the clarity, sharpness and fine details of this photo. Make it crisp, clean and vivid with natural HDR-like depth. Reduce noise and blur, recover micro-details. Keep the subject, content and composition completely unchanged. High resolution, professional photography quality."
        case .grade:
            return "Professionally color grade this photo with refined natural colors inspired by Hasselblad medium-format color science: rich yet realistic tones, luminous natural skin, smooth highlight roll-off, slightly lifted shadows, subtle cinematic warmth. Enhance clarity and micro-contrast. Keep the subject, content and composition completely unchanged. High quality, elegant, timeless."
        case .retouch:
            return "Professionally retouch this portrait: natural skin smoothing while preserving realistic skin texture, even out skin tone, brighten and refine the eyes, subtle facial light sculpting, healthy glow. Enhance overall clarity and details. Keep the person's facial features, identity, body, clothing and composition completely unchanged. High-end editorial quality."
        case .erase:
            return "The second image has red painted markings showing exactly what the user wants removed. Remove the object covered by the red markings from the first image completely, and naturally fill that area with the surrounding background and texture, as if the object was never there. Keep everything else (people, faces, clothing, lighting, colors, composition) completely unchanged. High quality, seamless, natural."
        case .custom:
            return "\(customText). Enhance the clarity and quality of the result. Keep the main subject and composition recognizable. High quality."
        }
    }

    private func run(_ action: AIAction) {
        guard let input = workingImage else { return }
        isProcessing = true
        errorText = nil
        saveMessage = nil
        processedSeconds = 0
        let prompt = buildPrompt(action: action)
        let q = quality

        AgnesClient.shared.editImage(inputs: [input], prompt: prompt, quality: q) { result in
            isProcessing = false
            switch result {
            case .success(let img):
                withAnimation(.easeOut(duration: 0.25)) {
                    resultImage = img
                }
            case .failure(let err):
                errorText = err.localizedDescription
            }
        }
    }

    private func runErase(marked: UIImage) {
        guard let input = workingImage else { return }
        isProcessing = true
        errorText = nil
        saveMessage = nil
        processedSeconds = 0
        let prompt = buildPrompt(action: .erase)
        let q = quality

        AgnesClient.shared.editImage(inputs: [input, marked], prompt: prompt, quality: q) { result in
            isProcessing = false
            switch result {
            case .success(let img):
                withAnimation(.easeOut(duration: 0.25)) {
                    resultImage = img
                }
            case .failure(let err):
                errorText = err.localizedDescription
            }
        }
    }

    private func saveResult() {
        guard let img = resultImage, let data = img.jpegData(compressionQuality: 0.95) else { return }
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }) { success, _ in
            DispatchQueue.main.async {
                saveMessage = success ? "已保存到相册" : "保存失败，请检查相册权限"
            }
        }
    }
}

struct CompareSlider: View {
    let before: UIImage
    let after: UIImage
    @State private var position: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: size.width * position)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                Rectangle()
                    .fill(Theme.cyan)
                    .frame(width: 1.5, height: size.height)
                    .position(x: size.width * position, y: size.height / 2)

                Circle()
                    .fill(Theme.cyan)
                    .frame(width: 22, height: 22)
                    .overlay(
                        AppIconView(name: .arrowLR, size: 12, lineWidth: 2.4, color: .black)
                    )
                    .position(x: size.width * position, y: size.height / 2)

                Text("BEFORE")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(5)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(5)
                    .padding(8)

                Text("AFTER")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(5)
                    .background(Theme.cyan.opacity(0.9))
                    .cornerRadius(5)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = value.location.x / max(size.width, 1)
                        position = min(max(p, 0.03), 0.97)
                    }
            )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.hairline, lineWidth: 0.8)
        )
    }

    private var aspectRatio: CGFloat {
        let w = before.size.width
        let h = before.size.height
        guard w > 0, h > 0 else { return 1 }
        return w / h
    }
}
