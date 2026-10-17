import SwiftUI
import CoreImage

struct CinematicOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let bar = h * 0.12
            ZStack {

                VStack {
                    Rectangle().fill(.black).frame(height: bar)
                    Spacer()
                    Rectangle().fill(.black).frame(height: bar)
                }

                RadialGradient(colors: [.clear, .black.opacity(0.35)],
                               center: .center,
                               startRadius: h * 0.3, endRadius: h * 0.75)
                    .allowsHitTesting(false)

                FilmGrain()
                    .opacity(0.06)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

struct FilmGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for _ in 0..<1400 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat((seed >> 16) % UInt64(size.width))
                let y = CGFloat((seed >> 33) % UInt64(size.height))
                let v = Double((seed >> 48) % 255) / 255.0
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                             with: .color(Color(white: v)))
            }
        }
    }
}

struct LUTIntensitySlider: View {
    @EnvironmentObject var vm: CameraViewModel

    var body: some View {
        HStack(spacing: 10) {
            Text("强度")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Slider(value: Binding(
                get: { vm.lutIntensity },
                set: { vm.setLUTIntensity($0) }
            ), in: 0...1)
            .tint(Theme.orange)
            Text("\(Int(vm.lutIntensity * 100))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPill()
    }
}

struct LUTPanel: View {
    @EnvironmentObject var vm: CameraViewModel
    @ObservedObject private var thumbStore = LUTThumbStore.shared
    @Environment(\.dismiss) var dismiss
    @State private var category = "negative_color"
    @State private var search = ""
    @State private var appeared = false

    private var allLUTs: [CubeLUT] { CameraViewModel.allLUTs }

    private var shown: [CubeLUT] {
        if !search.isEmpty {
            return allLUTs.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return LUTStore.inCategory(category, from: allLUTs)
    }

    var body: some View {
        ZStack {
            Theme.spaceGradient(Theme.bg)

            VStack(spacing: 0) {

                HStack {
                    Text("胶片库")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(allLUTs.count) 款")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 3)
                    Spacer()
                    if vm.selectedLUTName != nil {
                        Button {
                            vm.selectLUT(nil)
                        } label: {
                            Text("清除")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.cyan)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(DS.tintSoft))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { dismiss() } label: {
                        AppIconView(name: .close, size: 18, lineWidth: 2, color: .white.opacity(0.7))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                HStack(spacing: 8) {
                    AppIconView(name: .photo, size: 13, lineWidth: 1.8, color: .white.opacity(0.4))
                    TextField("搜索胶片（kodak / fuji / tri-x…）", text: $search)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            AppIconView(name: .close, size: 11, lineWidth: 2, color: .white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LUTStore.categoryOrder, id: \.self) { cat in
                            let count = LUTStore.inCategory(cat, from: allLUTs).count
                            let label = allLUTs.first { $0.category == cat }?.categoryDisplay ?? cat
                            Button {
                                Haptics.selection()
                                search = ""
                                category = cat
                            } label: {
                                Text("\(label) \(count)")
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(search.isEmpty && category == cat ? .black : .white.opacity(0.7))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(search.isEmpty && category == cat ? Theme.cyan : Color.white.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.vertical, 12)

                LUTIntensitySlider()
                    .padding(.bottom, 6)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                        ForEach(shown) { lut in
                            let selected = vm.selectedLUTName == lut.file
                            Button {
                                Haptics.light()
                                vm.selectLUT(selected ? nil : lut)
                            } label: {
                                VStack(spacing: 6) {

                                    ZStack {
                                        if let thumb = thumbStore.thumbs[lut.file] {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(height: 54)
                                                .frame(maxWidth: .infinity)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [previewColorA(lut), previewColorB(lut)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(height: 54)
                                        }
                                    }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(selected ? Theme.cyan : Color.clear, lineWidth: 2)
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if selected {
                                                AppIconView(name: .check, size: 13, lineWidth: 2.4, color: .white)
                                                    .padding(6)
                                            }
                                        }
                                    Text(lut.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(selected ? Theme.cyan : .white.opacity(0.65))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 26)
                    .onAppear {
                        withAnimation(DS.springSoft.delay(0.06)) { appeared = true }
                        thumbStore.ensureAll(allLUTs)
                    }
                }
            }
        }
    }

    private func previewColorA(_ lut: CubeLUT) -> Color {
        switch lut.category {
        case "bw": return Color(white: 0.85)
        case "colorslide": return Color(red: 0.35, green: 0.72, blue: 0.85)
        case "fujixtransiii": return Color(red: 0.45, green: 0.65, blue: 0.55)
        case "instant_consumer": return Color(red: 0.95, green: 0.72, blue: 0.45)
        case "instant_pro": return Color(red: 0.85, green: 0.78, blue: 0.65)
        case "negative_color": return Color(red: 0.95, green: 0.55, blue: 0.35)
        case "negative_new": return Color(red: 0.65, green: 0.55, blue: 0.85)
        case "negative_old": return Color(red: 0.75, green: 0.60, blue: 0.45)
        case "print": return Color(red: 0.88, green: 0.85, blue: 0.78)
        default: return Color(white: 0.6)
        }
    }

    private func previewColorB(_ lut: CubeLUT) -> Color {
        switch lut.category {
        case "bw": return Color(white: 0.25)
        case "colorslide": return Color(red: 0.10, green: 0.25, blue: 0.45)
        case "fujixtransiii": return Color(red: 0.15, green: 0.30, blue: 0.28)
        case "instant_consumer": return Color(red: 0.55, green: 0.25, blue: 0.20)
        case "instant_pro": return Color(red: 0.35, green: 0.28, blue: 0.25)
        case "negative_color": return Color(red: 0.25, green: 0.20, blue: 0.55)
        case "negative_new": return Color(red: 0.20, green: 0.25, blue: 0.45)
        case "negative_old": return Color(red: 0.30, green: 0.22, blue: 0.18)
        case "print": return Color(red: 0.45, green: 0.42, blue: 0.38)
        default: return Color(white: 0.3)
        }
    }
}


final class LUTThumbStore: ObservableObject {
    static let shared = LUTThumbStore()
    @Published var thumbs: [String: UIImage] = [:]
    private var started = false
    private var baseCI: CIImage?
    private var baseExtent: CGRect = .zero

    private init() {
        guard let url = Bundle.main.url(forResource: "PreviewPhoto", withExtension: "jpg"),
              let data = try? Data(contentsOf: url),
              let ui = UIImage(data: data),
              let full = CIImage(image: ui) else { return }
        let w = full.extent.width
        let h = full.extent.height
        let crop = full.cropped(to: CGRect(x: 0, y: h * 0.32, width: w, height: h * 0.46))
        let small = crop.applyingFilter("CILanczosScaleTransform",
                                        parameters: [kCIInputScaleKey: 150.0 / w])
        baseCI = small
        baseExtent = small.extent
    }

    func ensureAll(_ luts: [CubeLUT]) {
        guard !started, baseCI != nil else { return }
        started = true
        let base = baseCI!
        let extent = baseExtent
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            var cache: [String: (Data, Int)] = [:]
            for lut in luts {
                autoreleasepool {
                    let out = CubeLUTParser.apply(base, lut: lut, cache: &cache, intensity: 1.0)
                    guard let cg = ctx.createCGImage(out, from: extent) else { return }
                    let img = UIImage(cgImage: cg)
                    DispatchQueue.main.async { self.thumbs[lut.file] = img }
                }
            }
        }
    }
}
