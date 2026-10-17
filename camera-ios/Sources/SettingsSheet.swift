import SwiftUI

enum GridStyle: String, CaseIterable {
    case off = "关闭"
    case thirds = "三分线"
    case golden = "黄金分割"
    case cross = "中心十字"
}

struct SettingsSheet: View {
    @EnvironmentObject var vm: CameraViewModel
    @Environment(\.dismiss) var dismiss
    @State private var appeared = false

    var body: some View {
        ZStack {
            Theme.spaceGradient(Theme.bg)

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        section("画面与画质") {
                            ToggleRow(icon: .photo, title: "画面全开", detail: vm.fullScreenViewfinder ? "铺满全屏" : "完整比例") {
                                Toggle("", isOn: $vm.fullScreenViewfinder)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }
                            ToggleRow(icon: .zap, title: "4K 视频", detail: vm.video4K ? "3840×2160" : "1080p") {
                                Toggle("", isOn: $vm.video4K)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.video4K) { on in
                                        Haptics.selection()
                                        vm.engine.setVideoResolution(ultraHD: on)
                                    }
                            }
                            ToggleRow(icon: .sparkles, title: "智能自动", detail: vm.smartAuto ? "低光自动多帧" : "手动") {
                                Toggle("", isOn: $vm.smartAuto)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }
                            ToggleRow(icon: .wand, title: "AI 超分", detail: vm.aiSuperResolution ? "waifu2x 真细节" : "关闭") {
                                Toggle("", isOn: $vm.aiSuperResolution)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.aiSuperResolution) { _ in Haptics.selection() }
                            }
                            ToggleRow(icon: .camera, title: "视频实时增强", detail: vm.videoSharpen ? "录制中实时清晰" : "关闭") {
                                Toggle("", isOn: $vm.videoSharpen)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.videoSharpen) { _ in Haptics.selection() }
                            }
                            ToggleRow(icon: .timer, title: "Live Photo", detail: vm.engine.livePhotoCapable ? (vm.livePhotoEnabled ? "开启" : "关闭") : "此设备不支持") {
                                Toggle("", isOn: $vm.livePhotoEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .disabled(!vm.engine.livePhotoCapable)
                            }
                            Text("画面全开：取景器铺满屏幕（轻微裁切）；智能自动参考系统相机策略，暗光自动叠加多帧合成；Live Photo 与系统相机同款（长按压播放）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        // 人像模式（v4.9：Vision 分割 + 背景虚化）
                        section("人像模式") {
                            ToggleRow(icon: .beauty, title: "背景虚化", detail: vm.portraitBlurEnabled ? "拍摄时自动识别人像" : "关闭") {
                                Toggle("", isOn: $vm.portraitBlurEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.portraitBlurEnabled) { _ in Haptics.selection() }
                            }
                            if vm.portraitBlurEnabled {
                                HStack(spacing: 8) {
                                    ForEach([PortraitProcessor.Depth.light, .medium, .deep], id: \.rawValue) { d in
                                        Button {
                                            vm.portraitDepth = d
                                            Haptics.selection()
                                        } label: {
                                            Text("景深·\(d.label)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(vm.portraitDepth == d ? .black : Theme.textDim)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(Capsule().fill(vm.portraitDepth == d ? Theme.cyan : Theme.panel))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            Text("拍摄时自动识别画面中的人像，前景清晰、背景虚化（系统级分割，无需额外模型）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        section("相机设置") {
                            ToggleRow(icon: .switchCamera, title: "前置镜像", detail: vm.mirrorFront ? "开启" : "关闭") {
                                Toggle("", isOn: $vm.mirrorFront)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.mirrorFront) { on in
                                        Haptics.selection()
                                        vm.setFrontMirror(on)
                                    }
                            }
                            Button {
                                vm.resetAllSettings()
                            } label: {
                                HStack(spacing: 10) {
                                    AppIconView(name: .rotateCCW, size: 15, lineWidth: 1.8, color: Theme.orange)
                                        .frame(width: 20)
                                    Text("恢复默认设置")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("全部归零")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundColor(Theme.textFaint)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                        }

                        section("专业对焦与电影模式") {
                            ToggleRow(icon: .brush, title: "电影模式", detail: vm.cinematicEnabled ? "2.35:1 遮幅+暗角+颗粒" : "关闭") {
                                Toggle("", isOn: $vm.cinematicEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.cinematicEnabled) { _ in Haptics.selection() }
                            }
                            if vm.manualFocus >= 0 {
                                HStack(spacing: 10) {
                                    Text("近")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                    Slider(value: Binding(
                                        get: { vm.manualFocus },
                                        set: { vm.setManualFocus($0) }
                                    ), in: 0...1)
                                    .tint(Theme.cyan)
                                    Text("远")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 6)
                                Button {
                                    Haptics.light()
                                    vm.resetFocus()
                                } label: {
                                    Text("恢复自动对焦")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.cyan)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    Haptics.light()
                                    vm.setManualFocus(0.5)
                                } label: {
                                    HStack(spacing: 10) {
                                        AppIconView(name: .brush, size: 15, lineWidth: 1.8, color: Theme.cyan)
                                            .frame(width: 20)
                                        Text("启用手动对焦")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("0-1 精确控焦")
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(Theme.textFaint)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        section("慢门长曝光") {
                            Picker("时长", selection: $vm.slowShutterSeconds) {
                                Text("关").tag(Double(0))
                                Text("3 秒").tag(Double(3))
                                Text("5 秒").tag(Double(5))
                                Text("10 秒").tag(Double(10))
                            }
                            .pickerStyle(.segmented)
                            Text("拍摄时保持手机静止：运动物体糊化、静态清晰（丝滑流水效果）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        section("音量键拍照") {
                            Toggle(isOn: $vm.volumeShutterEnabled) {
                                Text("按音量键即拍照")
                                    .font(.system(size: 14))
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                            Text("开启后音量 +/- 键等效快门（可能伴随提示音）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        section("超清引擎") {
                            Toggle(isOn: $vm.detailEnhanceEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("细节增强（推荐开启）")
                                        .font(.system(size: 14))
                                    Text("去噪 + 双层锐化 + 局部对比，分辨率不变提升清晰度")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))

                            Toggle(isOn: $vm.focusPeakingEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("峰值对焦")
                                        .font(.system(size: 14))
                                    Text("取景器高亮合焦区域，帮助精准对焦")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                            .onChange(of: vm.focusPeakingEnabled) { on in
                                FrameAnalyzer.shared.peakingEnabled = on
                            }

                            Text("提示：")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.cyan)
                            Text("逆光/暗光/远景时拍照模式切「超清Pro」（四帧对齐合成）效果最明显")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        section("构图与辅助") {
                            ToggleRow(icon: nil, title: "构图线", detail: vm.gridStyle.rawValue) {
                                HStack(spacing: 6) {
                                    ForEach(GridStyle.allCases, id: \.self) { g in
                                        Button {
                                            vm.gridStyle = g
                                        } label: {
                                            Text(g.rawValue)
                                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                                .foregroundColor(vm.gridStyle == g ? .black : Theme.textDim)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(Capsule().fill(vm.gridStyle == g ? Theme.cyan : Theme.panel))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            ToggleRow(icon: nil, title: "水平仪 & 指南针", detail: vm.motionEnabled ? "开启" : "关闭") {
                                Toggle("", isOn: $vm.motionEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.motionEnabled) { on in
                                        if on { MotionManager.shared.start() } else { MotionManager.shared.stop() }
                                    }
                            }

                            ToggleRow(icon: nil, title: "实时直方图", detail: vm.histogramEnabled ? "显示" : "隐藏") {
                                Toggle("", isOn: $vm.histogramEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.histogramEnabled) { on in
                                        FrameAnalyzer.shared.enabled = on
                                    }
                            }

                            ToggleRow(icon: nil, title: "斑马线过曝提示", detail: vm.zebraEnabled ? "开启" : "关闭") {
                                Toggle("", isOn: $vm.zebraEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }
                        }

                        section("拍摄") {
                            ToggleRow(icon: nil, title: "时间戳水印", detail: vm.timestampEnabled ? "右下角日期" : "关闭") {
                                Toggle("", isOn: $vm.timestampEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }

                            ToggleRow(icon: nil, title: "屏幕补光", detail: vm.screenFlashEnabled ? "前置自拍亮屏" : "关闭") {
                                Toggle("", isOn: $vm.screenFlashEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }

                            ToggleRow(icon: nil, title: "曝光锁定 AE-L", detail: vm.exposureLocked ? "已锁定" : "自动") {
                                Toggle("", isOn: $vm.exposureLocked)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.orange))
                                    .labelsHidden()
                                    .onChange(of: vm.exposureLocked) { on in
                                        if on { vm.engine.lockExposure() } else { vm.engine.unlockExposure() }
                                    }
                            }
                        }

                        section("视频") {
                            ToggleRow(icon: nil, title: "慢动作", detail: vm.slowMoEnabled ? "4× 慢放" : "正常") {
                                Toggle("", isOn: $vm.slowMoEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                            }

                            ToggleRow(icon: nil, title: "高帧率", detail: vm.highFrameRate ? "60fps（若支持）" : "标准") {
                                Toggle("", isOn: $vm.highFrameRate)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.highFrameRate) { on in
                                        vm.applyVideoFrameRate()
                                    }
                            }
                        }

                        section("语音") {
                            ToggleRow(icon: nil, title: "语音控制", detail: vm.voiceEnabled ? "听指令中" : "关闭") {
                                Toggle("", isOn: $vm.voiceEnabled)
                                    .toggleStyle(SwitchToggleStyle(tint: Theme.cyan))
                                    .labelsHidden()
                                    .onChange(of: vm.voiceEnabled) { on in
                                        if on {
                                            VoiceController.shared.onCommand = { cmd in
                                                DispatchQueue.main.async { vm.handleVoiceCommand(cmd) }
                                            }
                                            VoiceController.shared.start()
                                        } else {
                                            VoiceController.shared.stop()
                                        }
                                    }
                            }

                            if vm.voiceEnabled {
                                Text("指令：拍照 / 录制 / 停止 / 翻转  ·  识别：\(VoiceController.shared.lastHeard)")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(Theme.textFaint)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)

                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 26)
                    .onAppear {
                        withAnimation(DS.springSoft.delay(0.06)) { appeared = true }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("SETTINGS")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.cyan)
                .kerning(2)
            Spacer()
            Button { dismiss() } label: {
                AppIconView(name: .close, size: 20, lineWidth: 2.2, color: Theme.textDim)
                    .frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.textFaint)
                .kerning(1)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.panel.opacity(0.9))
            )
        }
    }
}

struct ToggleRow<Trailing: View>: View {
    var icon: AppIcon?
    var title: String
    var detail: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 11) {
            if let ic = icon {
                AppIconView(name: ic, size: 15, lineWidth: 1.6, color: Theme.cyan)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(Theme.textFaint)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
