import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        ZStack {
            Theme.spaceGradient(Theme.bg)

            if vm.permissionDenied {
                PermissionView()
            } else {
                mainUI
            }
        }
        .sheet(isPresented: $vm.showPhotoViewer) {
            PhotoViewer()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showAIStudio) {
            AIStudioView()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showSettings) {
            SettingsSheet()
                .environmentObject(vm)
        }
        .sheet(isPresented: $vm.showLUTPanel) {
            LUTPanel()
                .environmentObject(vm)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var mainUI: some View {
        VStack(spacing: 0) {
            TopBar(engine: vm.engine)

            viewfinder
                .layoutPriority(1)

            FilterStrip()

            if vm.proExpanded {
                ProPanel(engine: vm.engine)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if vm.beautyPanelExpanded {
                BeautyPanel()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ModeSwitcher()

            BottomBar(engine: vm.engine)
        }
    }

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                MetalPreview(engine: vm.engine, viewModel: vm)

                if vm.gridEnabled {
                    GridOverlay()
                }

                if let p = vm.focusIndicator {
                    FocusBox()
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }

                if vm.zebraEnabled {
                    ZebraOverlay()
                        .allowsHitTesting(false)
                }
                if vm.motionEnabled {
                    LevelCompassOverlay()
                        .allowsHitTesting(false)
                        .padding(.top, 44)
                }
                if vm.histogramEnabled {
                    HistogramOverlay()
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 10)
                        .padding(.top, 46)
                }
                if vm.focusPeakingEnabled {
                    FocusPeakingOverlay()
                        .allowsHitTesting(false)
                }

                if vm.cinematicEnabled {
                    CinematicOverlay()
                }

                ForEach(Array(vm.engine.faceBoxes.enumerated()), id: \.offset) { _, box in
                    let w = geo.size.width * box.width
                    let h = geo.size.height * box.height
                    let cx = geo.size.width * box.midX
                    let cy = geo.size.height * box.midY
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow.opacity(0.8), lineWidth: 1.2)
                        .frame(width: w, height: h)
                        .position(x: cx, y: cy)
                }

                if vm.showEVSlider {
                    EVSlider()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 12)
                }

                VStack {
                    HStack {
                        if vm.isRecording {
                            Button {
                                vm.togglePauseRecording()
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 7, height: 7)
                                        .opacity(vm.isRecordingPaused ? 0.3 : 1.0)
                                    Text(String(format: "%02d:%02d", vm.recordingSeconds / 60, vm.recordingSeconds % 60))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }

                        if vm.timelapseRunning {
                            let secs = vm.timelapse.elapsedSeconds
                            let mm = secs / 60
                            let ss = secs % 60
                            let frames = vm.timelapse.frameCount
                            let tlText = String(format: "TL %02d:%02d %d帧", mm, ss, frames)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Theme.orange)
                                    .frame(width: 7, height: 7)
                                Text(tlText)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                        }

                        if vm.panoramaRunning {
                            let panoProgress = vm.panorama.progress
                            let panoCount = vm.panorama.stripeCount
                            let panoText = "全景 \(panoCount)"
                            HStack(spacing: 6) {
                                ProgressView(value: panoProgress)
                                    .progressViewStyle(.linear)
                                    .tint(Theme.orange)
                                    .frame(width: 90)
                                Text(panoText)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                        }
                        MonoLabel(text: vm.currentFilter.name.uppercased(), size: 9.5, color: Theme.cyan.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        Spacer()
                        if vm.beautyEnabled {
                            MonoLabel(text: "BEAUTY \(Int(vm.beautyLevel * 100))", size: 9.5, color: Theme.orange.opacity(0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(10)
                    Spacer()
                    HStack(spacing: 8) {

                        capsuleControl(vm.photoRatio.rawValue) { vm.cycleRatio() }

                        capsuleControl(vm.timerSetting == .off ? "定时" : "\(vm.timerSetting.rawValue)",
                                       active: vm.timerSetting != .off) { vm.cycleTimer() }

                        capsuleControl(vm.captureStyle == .normal ? "HDR" : vm.captureStyle.rawValue,
                                       active: vm.captureStyle != .normal) { vm.cycleStyle() }
                        Spacer()

                        if vm.engine.hasUltraWide {
                            zoomChip("0.5", active: vm.onUltraWide) { vm.toggleUltraWide() }
                        }
                        zoomChip("1x", active: !vm.onUltraWide && vm.engine.zoomFactor < 1.5) { vm.goWideZoom(1) }
                        zoomChip("2x", active: vm.engine.zoomFactor >= 1.5) { vm.goWideZoom(2) }
                    }
                    .padding(10)
                }

                if let c = vm.countdown {
                    Text("\(c)")
                        .font(.system(size: 96, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.cyan)
                        .shadow(color: Theme.cyan.opacity(0.9), radius: 18)
                }

                if vm.flashHighlight {
                    Color.white.opacity(0.85)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in vm.handleZoomGesture(value) }
                        .onEnded { value in vm.endZoomGesture(value) },
                    SpatialTapGesture()
                        .onEnded { value in
                            vm.handleTapToFocus(at: value.location, in: geo.size)
                        }
                )
            )
        }
        .aspectRatio(vm.photoRatio.viewfinderAspect, contentMode: vm.fullScreenViewfinder ? .fill : .fit)
        .clipped()
        .background(Color.black)
        .overlay(
            Rectangle().stroke(Theme.hairline, lineWidth: 0.5)
        )
    }

    private func capsuleControl(_ text: String, active: Bool = false, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? Theme.cyan : .white.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .overlay(
                    Capsule().stroke(active ? Theme.cyan.opacity(0.7) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func zoomChip(_ text: String, active: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(active ? .black : .white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Theme.cyan : Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

struct PhotoViewer: View {
    @EnvironmentObject var vm: CameraViewModel
    @Environment(\.dismiss) var dismiss
    @State private var index = 0
    @State private var showShare = false

    var body: some View {
        ZStack {
            Theme.spaceGradient(.black)

            if vm.capturedPhotos.isEmpty {
                VStack(spacing: 14) {
                    AppIconView(name: .photo, size: 44, lineWidth: 1.4, color: Theme.textFaint)
                    MonoLabel(text: "暂无照片", size: 14)
                }
            } else {
                VStack(spacing: 14) {
                    TabView(selection: $index) {
                        ForEach(Array(vm.capturedPhotos.enumerated()), id: \.offset) { i, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .tag(i)
                                .padding(.vertical, 30)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))

                    if index < vm.capturedPhotos.count {
                        let img = vm.capturedPhotos[index]
                        let px = Int(img.size.width * img.scale) * Int(img.size.height * img.scale)
                        let info = String(format: "%d × %d · %.1fMP · %@/%@",
                                          Int(img.size.width * img.scale), Int(img.size.height * img.scale),
                                          Double(px) / 1_000_000.0,
                                          vm.mode.rawValue, vm.captureStyle.rawValue)
                        Text(info)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassPill()
                    }

                    HStack(spacing: 12) {
                        viewerButton("AI 修图", icon: .wand, accent: true) {
                            guard index < vm.capturedPhotos.count else { return }
                            let img = vm.capturedPhotos[index]
                            vm.showPhotoViewer = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                vm.openAIStudio(with: img)
                            }
                        }
                        viewerButton("分享", icon: .share, accent: false) {
                            showShare = true
                        }

                        viewerButton("删除", icon: .trash, accent: false) {
                            guard index < vm.capturedPhotos.count else { return }
                            Haptics.medium()
                            vm.capturedPhotos.remove(at: index)
                            if index >= vm.capturedPhotos.count {
                                index = max(0, vm.capturedPhotos.count - 1)
                            }
                            if vm.capturedPhotos.isEmpty {
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        AppIconView(name: .close, size: 22, lineWidth: 2.2, color: .white.opacity(0.75))
                            .frame(width: 42, height: 42)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                Spacer()
            }
        }
        .sheet(isPresented: $showShare) {
            if index < vm.capturedPhotos.count {
                ShareSheet(items: [vm.capturedPhotos[index]])
            }
        }
    }

    private func viewerButton(_ title: String, icon: AppIcon, accent: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 7) {
                AppIconView(name: icon, size: 15, lineWidth: 1.9, color: accent ? .black : .white)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(accent ? Theme.cyan : Color.white.opacity(0.12))
            )
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PermissionView: View {
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(spacing: 18) {
            AppIconView(name: .camera, size: 48, lineWidth: 1.4, color: Theme.cyan)
                .shadow(color: Theme.cyan.opacity(0.5), radius: 10)

            Text("需要相机权限")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("请在 设置 → 隐私与安全性 → 相机 中\n允许「倾瑶相机」访问\n然后回到 App 即可开始拍摄")
                .font(.system(size: 13))
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("前往设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.cyan))
            }
            .padding(.top, 6)
        }
        .padding(30)
    }
}

struct ModeSwitcher: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach(CaptureMode.allCases, id: \.self) { m in
                Button {
                    guard !vm.isRecording else { return }
                    Haptics.selection()
                    withAnimation(DS.spring) { vm.mode = m }
                } label: {
                    VStack(spacing: 4) {
                        Text(m.rawValue)
                            .font(.system(size: 12,
                                          weight: vm.mode == m ? .semibold : .regular,
                                          design: .rounded))
                            .foregroundColor(vm.mode == m ? accent(m) : .white.opacity(0.45))
                            .fixedSize()
                            .scaleEffect(vm.mode == m ? 1.06 : 1.0)
                            .animation(DS.spring, value: vm.mode)
                        Capsule()
                            .fill(vm.mode == m ? accent(m) : Color.clear)
                            .frame(width: 18, height: 2.5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if vm.mode == m {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                                    .glassPill()
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassPill()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func accent(_ m: CaptureMode) -> Color {
        switch m {
        case .photo: return Theme.cyan
        case .video: return Color(red: 1.0, green: 0.28, blue: 0.28)
        case .night, .timelapse, .panorama: return Theme.orange
        }
    }
}
