import SwiftUI

enum Theme {
    static let bg = Color(red: 0.020, green: 0.024, blue: 0.042)
    static let panel = Color(red: 0.055, green: 0.068, blue: 0.102)
    static let panelStroke = Color(red: 0.0, green: 0.90, blue: 1.0).opacity(0.22)

    static func spaceGradient(_ base: Color) -> some View {
        ZStack {
            base.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.14, blue: 0.28).opacity(0.55),
                    Color.clear,
                    Color(red: 0.16, green: 0.08, blue: 0.22).opacity(0.35)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            RadialGradient(colors: [Color.cyan.opacity(0.10), .clear],
                           center: .top, startRadius: 10, endRadius: 620)
                .ignoresSafeArea()
        }
    }
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let cyanDim = Color(red: 0.0, green: 0.90, blue: 1.0).opacity(0.55)
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let textDim = Color(white: 0.55)
    static let textFaint = Color(white: 0.38)
    static let hairline = Color.white.opacity(0.08)

    static func panelBackground() -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.panel.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 0.7)
            )
    }
}

struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = Theme.textDim

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
    }
}

func formatShutter(_ seconds: Double) -> String {
    if seconds >= 1.0 {
        return String(format: "%.1fs", seconds)
    }
    let denom = Int(round(1.0 / seconds))
    return "1/\(denom)"
}
