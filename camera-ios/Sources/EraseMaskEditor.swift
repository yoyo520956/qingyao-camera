import SwiftUI
import UIKit

struct EraseMaskEditor: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var brushWidth: CGFloat = 0.055

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                header

                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        maskCanvas(size: geo.size)

                        if strokes.isEmpty && currentStroke.isEmpty {
                            VStack(spacing: 8) {
                                AppIconView(name: .brush, size: 30, lineWidth: 1.6, color: .white.opacity(0.9))
                                Text("用手指涂抹要消除的部分")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.black.opacity(0.5)))
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = CGPoint(
                                    x: min(max(value.location.x / max(geo.size.width, 1), 0), 1),
                                    y: min(max(value.location.y / max(geo.size.height, 1), 0), 1)
                                )
                                currentStroke.append(p)
                            }
                            .onEnded { _ in
                                if !currentStroke.isEmpty {
                                    strokes.append(currentStroke)
                                    currentStroke = []
                                }
                            }
                    )
                }
                .aspectRatio(imageAspect, contentMode: .fit)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
                .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    toolButton(.undo, "撤销") {
                        if !strokes.isEmpty { strokes.removeLast() }
                    }
                    .disabled(strokes.isEmpty)

                    toolButton(.trash, "清空") {
                        strokes.removeAll()
                    }
                    .disabled(strokes.isEmpty)

                    Button {
                        if let marked = renderMarkedImage() {
                            dismiss()
                            onDone(marked)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AppIconView(name: .eraser, size: 15, lineWidth: 1.8, color: .black)
                            Text("开始消除")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 13)
                                .fill(strokes.isEmpty ? Theme.cyan.opacity(0.35) : Theme.cyan)
                        )
                    }
                    .disabled(strokes.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private var imageAspect: CGFloat {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return 1 }
        return w / h
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                AppIconView(name: .close, size: 22, lineWidth: 2, color: .white.opacity(0.75))
                    .frame(width: 40, height: 40)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("涂抹消除")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("涂住不要的东西，AI 会移除并补全背景")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textDim)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func maskCanvas(size: CGSize) -> some View {
        Canvas { context, _ in
            let all = strokes + (currentStroke.isEmpty ? [] : [currentStroke])
            for stroke in all {
                guard !stroke.isEmpty else { continue }
                var path = Path()
                let w = size.width
                let h = size.height
                for (i, p) in stroke.enumerated() {
                    let pt = CGPoint(x: p.x * w, y: p.y * h)
                    if i == 0 {
                        path.move(to: pt)
                    } else {
                        path.addLine(to: pt)
                    }
                }
                if stroke.count == 1 {
                    path.addEllipse(in: CGRect(
                        x: stroke[0].x * w - 11, y: stroke[0].y * h - 11,
                        width: 22, height: 22))
                }
                context.stroke(
                    path,
                    with: .color(Color(red: 1.0, green: 0.10, blue: 0.10).opacity(0.6)),
                    style: StrokeStyle(
                        lineWidth: brushWidth * min(w, h) * 1.4,
                        lineCap: .round,
                        lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func toolButton(_ icon: AppIcon, _ label: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 4) {
                AppIconView(name: icon, size: 18, lineWidth: 1.8, color: .white.opacity(0.9))
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textDim)
            }
            .frame(width: 56, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.panel.opacity(0.9))
            )
        }
        .buttonStyle(.plain)
    }

    private func renderMarkedImage() -> UIImage? {
        guard !strokes.isEmpty else { return nil }
        let w = image.size.width
        let h = image.size.height
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let c = ctx.cgContext
            c.setStrokeColor(UIColor(red: 1.0, green: 0.10, blue: 0.10, alpha: 0.9).cgColor)
            c.setLineWidth(brushWidth * min(w, h) * 1.4)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            for stroke in strokes {
                guard !stroke.isEmpty else { continue }
                c.beginPath()
                for (i, p) in stroke.enumerated() {
                    let pt = CGPoint(x: p.x * w, y: p.y * h)
                    if i == 0 {
                        c.move(to: pt)
                        if stroke.count == 1 {
                            c.addLine(to: CGPoint(x: pt.x + 0.5, y: pt.y + 0.5))
                        }
                    } else {
                        c.addLine(to: pt)
                    }
                }
                c.strokePath()
            }
        }
    }
}
