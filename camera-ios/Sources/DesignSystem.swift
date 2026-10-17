import SwiftUI
import UIKit

enum DS {

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let springSoft = Animation.spring(response: 0.45, dampingFraction: 0.9)
    static let easeOut = Animation.easeOut(duration: 0.18)

    static let tint = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let tintSoft = Color(red: 0.04, green: 0.52, blue: 1.0).opacity(0.16)
    static let glassStroke = Color.white.opacity(0.22)
}

struct GlassModifier: ViewModifier {
    var interactive: Bool = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .capsule
                )
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(DS.glassStroke, lineWidth: 0.8))
        }
    }
}

extension View {

    func glassPill(interactive: Bool = false) -> some View {
        modifier(GlassModifier(interactive: interactive))
    }
}

let isCompactScreen = UIScreen.main.bounds.width < 380

struct GlassIconButton: View {
    let icon: AppIcon
    var active = false
    var color: Color = .white
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            AppIconView(name: icon, size: isCompactScreen ? 14 : 17, lineWidth: 1.8,
                        color: active ? .black : color)
                .frame(width: isCompactScreen ? 29 : 34, height: isCompactScreen ? 29 : 34)
                .background(
                    Group {
                        if active {
                            Circle().fill(Color.white)
                        } else {
                            Circle().fill(.white.opacity(0.10))
                        }
                    }
                )
                .glassPill()
                .scaleEffect(pressed ? 0.88 : 1.0)
                .animation(DS.spring, value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct ExposureHUD: View {
    let isoText: String
    let shutterText: String

    var body: some View {
        HStack(spacing: isCompactScreen ? 6 : 10) {
            HStack(spacing: 4) {
                Text("ISO")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Text(isoText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(width: 1, height: 10)
            HStack(spacing: 4) {
                Text(shutterText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassPill()
    }
}
