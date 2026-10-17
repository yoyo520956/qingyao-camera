import SwiftUI

struct EVSlider: View {
    @EnvironmentObject var vm: CameraViewModel
    @State private var height: CGFloat = 140

    var body: some View {
        VStack(spacing: 6) {

            Image(systemName: "sun.max.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)

            GeometryReader { geo in
                let trackH = geo.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(width: 3)

                    Rectangle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 12, height: 1)
                        .offset(y: trackH / 2)

                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(y: trackH / 2 - (CGFloat(vm.evBias / 3.0)) * (trackH / 2) - 8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let t = 1.0 - min(1, max(0, g.location.y / trackH))
                            let bias = Float((t - 0.5) * 2.0) * 3.0
                            vm.setEV(bias)
                        }
                        .onEnded { _ in
                            Haptics.light()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation(DS.easeOut) { vm.showEVSlider = false }
                            }
                        }
                )
            }
            .frame(width: 26, height: height)

            Image(systemName: "sun.min.fill")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))

            Text(String(format: "%+.1f", vm.evBias))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 8)
        .glassPill()
    }
}
