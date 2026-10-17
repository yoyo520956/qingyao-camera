import SwiftUI
import AVFoundation

struct TopBar: View {
    @EnvironmentObject var vm: CameraViewModel
    @ObservedObject var engine: CameraEngine

    var body: some View {
        HStack(spacing: isCompactScreen ? 5 : 10) {

            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isConfigured ? Theme.cyan : Theme.orange)
                    .frame(width: 6, height: 6)
                    .shadow(color: (engine.isConfigured ? Theme.cyan : Theme.orange).opacity(0.8), radius: 3)
                if !isCompactScreen {
                    Text(engine.isConfigured ? "就绪" : "启动中")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassPill()

            Spacer()

            ExposureHUD(isoText: engine.isoText, shutterText: engine.shutterText)

            Spacer()

            Button {
                vm.toggleExposureLock()
            } label: {
                Text("AE-L")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.exposureLocked ? .black : .white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(Circle().fill(vm.exposureLocked ? Theme.orange : .white.opacity(0.10)))
                    .glassPill()
                    .scaleEffect(vm.exposureLocked ? 1.06 : 1.0)
                    .animation(DS.spring, value: vm.exposureLocked)
            }
            .buttonStyle(.plain)

            if vm.mode == .video || vm.mode == .night {
                Button {
                    vm.toggleTorch()
                } label: {
                    AppIconView(name: vm.engine.torchOn ? .zap : .zapOff, size: isCompactScreen ? 13 : 16, lineWidth: 2,
                                color: vm.engine.torchOn ? .yellow : .white.opacity(0.8))
                        .frame(width: isCompactScreen ? 29 : 34, height: isCompactScreen ? 29 : 34)
                        .background(Circle().fill(.white.opacity(0.10)))
                        .glassPill()
                }
                .buttonStyle(.plain)
            }

            GlassIconButton(icon: .sparkles) { vm.openAIStudio(with: vm.lastPhoto) }
            GlassIconButton(icon: .grid, active: vm.gridEnabled) { vm.gridEnabled.toggle() }
            GlassIconButton(icon: flashIcon, active: engine.flashMode == .on, color: flashColor) { engine.cycleFlashMode() }
                .opacity(engine.isFlashAvailable ? 1 : 0.35)
            GlassIconButton(icon: .settings) { vm.showSettings = true }
        }
        .padding(.horizontal, isCompactScreen ? 7 : 10)
        .padding(.top, 6)
        .padding(.bottom, isCompactScreen ? 6 : 8)
    }

    private var flashIcon: AppIcon {
        engine.flashMode == .off ? .zapOff : .zap
    }

    private var flashColor: Color {
        switch engine.flashMode {
        case .on: return Theme.orange
        case .auto: return .yellow
        default: return .white
        }
    }
}

struct FilterStrip: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {

                Button {
                    Haptics.light()
                    vm.showLUTPanel = true
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(vm.selectedLUTName != nil ? Theme.orange.opacity(0.9) : Theme.orange.opacity(0.30))
                                .frame(width: 34, height: 34)
                            AppIconView(name: .film, size: 15, lineWidth: 2.0, color: .white)
                        }
                        .overlay(
                            Circle()
                                .stroke(vm.selectedLUTName != nil ? Theme.orange : Color.clear, lineWidth: 1.8)
                        )
                        Text(vm.selectedLUTName != nil
                             ? (vm.activeLUT?.name ?? "胶片") : "胶片库")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(vm.selectedLUTName != nil ? Theme.orange : Theme.textDim)
                            .lineLimit(1)
                            .frame(maxWidth: 60)
                    }
                }
                .buttonStyle(.plain)

                ForEach(FilterLibrary.presets) { preset in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            vm.selectedFilterIndex = preset.id
                        }
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(preset.accent.opacity(vm.selectedFilterIndex == preset.id ? 0.95 : 0.30))
                                    .frame(width: 34, height: 34)
                                if vm.selectedFilterIndex == preset.id {
                                    AppIconView(name: .check, size: 14, lineWidth: 2.2, color: .white)
                                }
                            }
                            .overlay(
                                Circle()
                                    .stroke(vm.selectedFilterIndex == preset.id ? Theme.cyan : Color.clear, lineWidth: 1.8)
                            )
                            .shadow(color: vm.selectedFilterIndex == preset.id ? Theme.cyan.opacity(0.5) : .clear, radius: 6)

                            Text(preset.name)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(vm.selectedFilterIndex == preset.id ? Theme.cyan : Theme.textDim)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .background(Theme.bg)
    }
}

struct BottomBar: View {
    @EnvironmentObject var vm: CameraViewModel
    @ObservedObject var engine: CameraEngine

    var body: some View {
        HStack(alignment: .center) {

            Button {
                if vm.lastPhoto != nil { vm.showPhotoViewer = true }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.panel)
                        .frame(width: 50, height: 50)
                    if let photo = vm.lastPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    } else {
                        AppIconView(name: .photo, size: 17, lineWidth: 1.7, color: Theme.textFaint)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    vm.beautyPanelExpanded.toggle()
                    if vm.beautyPanelExpanded { vm.proExpanded = false }
                }
            } label: {
                VStack(spacing: 3) {
                    AppIconView(name: .beauty, size: 19, lineWidth: 1.7,
                                color: vm.beautyPanelExpanded ? Theme.cyan : .white.opacity(0.85))
                    MonoLabel(text: "美颜", size: 8.5, color: vm.beautyEnabled ? Theme.orange : Theme.textFaint)
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)

            Spacer()

            if vm.isRecording {
                Button {
                    Haptics.light()
                    vm.captureDuringRecording()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }

            ShutterButton {
                vm.capture()
            }

            Spacer()

            Button {
                engine.switchCamera()
            } label: {
                VStack(spacing: 3) {
                    AppIconView(name: .switchCamera, size: 20, lineWidth: 1.7,
                                color: .white.opacity(0.85))
                    MonoLabel(text: engine.cameraPosition == .back ? "后置" : "前置", size: 8.5)
                }
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    vm.proExpanded.toggle()
                    if vm.proExpanded { vm.beautyPanelExpanded = false }
                }
            } label: {
                Text("PRO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.proExpanded ? .black : Theme.cyan)
                    .frame(width: 46, height: 30)
                    .background(
                        Capsule().fill(vm.proExpanded ? Theme.cyan : Theme.cyan.opacity(0.10))
                    )
                    .overlay(
                        Capsule().stroke(Theme.cyan.opacity(0.5), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }
}

struct ShutterButton: View {
    var action: () -> Void
    @EnvironmentObject var vm: CameraViewModel
    @State private var pressed = false

    private var modeColor: Color {
        switch vm.mode {
        case .photo: return Theme.cyan
        case .night: return Theme.orange
        case .video: return .red
        case .timelapse, .panorama: return Theme.orange
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {

                Circle()
                    .stroke(
                        AngularGradient(colors: [modeColor.opacity(0.9), modeColor.opacity(0.35),
                                                 modeColor.opacity(0.9), modeColor.opacity(0.35),
                                                 modeColor.opacity(0.9)],
                                        center: .center),
                        lineWidth: 2.5
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: modeColor.opacity(0.4), radius: vm.isRecording ? 14 : 9)
                    .opacity(pressed ? 0.75 : 1.0)
                    .animation(vm.isRecording
                               ? Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                               : DS.easeOut,
                               value: vm.isRecording)

                if vm.mode == .video && vm.isRecording {

                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                        .scaleEffect(pressed ? 0.82 : (vm.isRecordingPaused ? 0.9 : 1.0))
                        .opacity(vm.isRecordingPaused ? 0.45 : 1.0)
                        .animation(DS.spring, value: vm.isRecordingPaused)
                        .transition(.scale.combined(with: .opacity))
                } else if vm.mode == .night || vm.mode == .timelapse || vm.mode == .panorama {

                    AppIconView(name: .timer, size: 30, lineWidth: 2.2, color: Theme.orange)
                        .scaleEffect(pressed ? 0.88 : 1.0)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white, Color(white: 0.80)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 60, height: 60)
                        .scaleEffect(pressed ? 0.86 : 1.0)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(DS.spring, value: vm.mode)
            .animation(DS.spring, value: vm.isRecording)
            .scaleEffect(pressed ? 0.94 : 1.0)
            .animation(DS.spring, value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        withAnimation(.easeOut(duration: 0.1)) { pressed = true }
                        Haptics.light()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            if pressed { vm.startLongPressBurst() }
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.16)) { pressed = false }
                    vm.stopLongPressBurst()
                }
        )
    }
}

struct ProPanel: View {
    @EnvironmentObject var vm: CameraViewModel
    @ObservedObject var engine: CameraEngine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle(isOn: $vm.proModeEnabled) {
                    MonoLabel(text: "手动曝光", size: 12, color: .white.opacity(0.85))
                }
                .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                .onChange(of: vm.proModeEnabled) { enabled in
                    if enabled {
                        vm.applyManualExposure()
                    } else {
                        engine.resetAutoExposure()
                    }
                }

                Spacer()

                Button {
                    vm.startBurst()
                } label: {
                    Text("连拍×10")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.cyan.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    vm.resetProExposure()
                } label: {
                    Text("重置")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.orange.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            if vm.proModeEnabled {
                sliderRow(
                    label: "ISO",
                    value: Binding(
                        get: { Double(vm.manualISO) },
                        set: { vm.manualISO = Float($0) }
                    ),
                    range: Double(engine.isoRange.lowerBound)...Double(engine.isoRange.upperBound),
                    display: "\(Int(vm.manualISO))"
                ) {
                    vm.applyManualExposure()
                }

                sliderRow(
                    label: "快门",
                    value: Binding(
                        get: { vm.manualShutter },
                        set: { vm.manualShutter = $0 }
                    ),
                    range: engine.shutterRange,
                    display: formatShutter(vm.manualShutter)
                ) {
                    vm.applyManualExposure()
                }
            }

            sliderRow(
                label: "EV",
                value: Binding(
                    get: { Double(vm.manualBias) },
                    set: { vm.manualBias = Float($0) }
                ),
                range: Double(engine.biasRange.lowerBound)...Double(engine.biasRange.upperBound),
                display: String(format: "%+.1f", vm.manualBias)
            ) {
                vm.applyBias()
            }

            sliderRow(
                label: "白平衡",
                value: Binding(
                    get: { vm.whiteBalanceK },
                    set: { vm.whiteBalanceK = $0 }
                ),
                range: 2500.0...8500.0,
                display: "\(Int(vm.whiteBalanceK))K"
            ) {
                vm.applyWhiteBalance()
            }

            HStack(spacing: 14) {

                Toggle(isOn: $vm.rawEnabled) {
                    MonoLabel(text: "RAW DNG", size: 12, color: .white.opacity(0.85))
                }
                .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))

                Spacer()

                Button {
                    vm.autoWhiteBalance()
                    vm.whiteBalanceK = 5600
                } label: {
                    Text("白平衡自动")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.cyan.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            if vm.rawEnabled {
                MonoLabel(text: "RAW 模式输出 DNG 原始数据（滤镜/美颜/闪光不生效）", size: 8.5, color: Theme.orange.opacity(0.9))
            }

            HStack {
                MonoLabel(text: "ISO 范围 \(Int(engine.isoRange.lowerBound))~\(Int(engine.isoRange.upperBound))", size: 8.5, color: Theme.textFaint)
                Spacer()
                MonoLabel(text: vm.engine.isManualExposureActive ? "● MANUAL" : "○ AUTO", size: 8.5,
                          color: vm.engine.isManualExposureActive ? Theme.orange : Theme.textFaint)
            }
        }
        .padding(14)
        .background(Theme.panelBackground())
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func sliderRow(label: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           display: String,
                           onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            MonoLabel(text: label, size: 11, color: Theme.cyan)
                .frame(width: 32, alignment: .leading)
            Slider(value: value, in: range)
                .tint(Theme.cyan)
                .onChange(of: value.wrappedValue) { _ in onChange() }
            MonoLabel(text: display, size: 10.5, color: .white.opacity(0.9))
                .frame(width: 52, alignment: .trailing)
        }
    }
}

struct BeautyPanel: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $vm.beautyEnabled) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))

            MonoLabel(text: "美颜", size: 12, color: vm.beautyEnabled ? Theme.cyan : Theme.textDim)

            Slider(value: $vm.beautyLevel, in: 0...1)
                .tint(Theme.orange)
                .opacity(vm.beautyEnabled ? 1 : 0.4)
                .disabled(!vm.beautyEnabled)

            MonoLabel(text: "\(Int(vm.beautyLevel * 100))%", size: 11,
                      color: vm.beautyEnabled ? Theme.orange : Theme.textFaint)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(14)
        .background(Theme.panelBackground())
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}

struct FocusBox: View {
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .stroke(Theme.cyan, lineWidth: 1.5)
            .frame(width: 68, height: 68)
            .shadow(color: Theme.cyan.opacity(0.6), radius: 4)
            .scaleEffect(appeared ? 1.0 : 1.35)
            .opacity(appeared ? 1.0 : 0.4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.22)) {
                    appeared = true
                }
            }
    }
}

struct GridOverlay: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                switch vm.gridStyle {
                case .off:
                    break
                case .thirds:

                    for i in 1...2 {
                        let x = w * CGFloat(i) / 3.0
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                        let y = h * CGFloat(i) / 3.0
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                case .golden:

                    for f in [0.382, 0.618] {
                        let x = w * CGFloat(f)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                        let y = h * CGFloat(f)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                case .cross:

                    path.move(to: CGPoint(x: w / 2, y: h * 0.40))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.60))
                    path.move(to: CGPoint(x: w * 0.44, y: h / 2))
                    path.addLine(to: CGPoint(x: w * 0.56, y: h / 2))
                }
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
    }
}
