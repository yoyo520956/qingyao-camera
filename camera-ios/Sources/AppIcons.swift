import SwiftUI

enum AppIcon: String, CaseIterable {
    case sparkles, grid, zap, zapOff, switchCamera, photo, close, timer
    case arrowLR, camera, download, share, undo, eraser, brush, wand
    case check, rotateCCW, trash, beauty, settings, film
}

struct AppIconShape: Shape {
    let name: AppIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let k = min(rect.width, rect.height) / 24.0
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * k, y: rect.minY + y * k)
        }
        // 官方 Lucide 曲线优先（v4.8：19 个图标精确替换自绘）
        LucidePaths.path(for: name, into: &path, P: P)
        if !path.isEmpty {
            return path
        }
        switch name {
        case .sparkles:

            path.move(to: P(11.02, 2.81))
            path.addArc(center: P(12, 3), radius: 1 * k, startAngle: .degrees(-169.42), endAngle: .degrees(-10.58), clockwise: false)
            path.addLine(to: P(14.03, 8.37))
            path.addArc(center: P(16, 8), radius: 2 * k, startAngle: .degrees(169.3), endAngle: .degrees(100.7), clockwise: true)
            path.addLine(to: P(21.19, 11.02))
            path.addArc(center: P(21, 12), radius: 1 * k, startAngle: .degrees(-79.42), endAngle: .degrees(79.42), clockwise: false)
            path.addLine(to: P(15.63, 14.03))
            path.addArc(center: P(16, 16), radius: 2 * k, startAngle: .degrees(-100.7), endAngle: .degrees(-169.3), clockwise: true)
            path.addLine(to: P(12.98, 21.19))
            path.addArc(center: P(12, 21), radius: 1 * k, startAngle: .degrees(10.58), endAngle: .degrees(169.42), clockwise: false)
            path.addLine(to: P(9.97, 15.63))
            path.addArc(center: P(8, 16), radius: 2 * k, startAngle: .degrees(-10.7), endAngle: .degrees(-79.3), clockwise: true)
            path.addLine(to: P(2.81, 12.98))
            path.addArc(center: P(3, 12), radius: 1 * k, startAngle: .degrees(100.58), endAngle: .degrees(259.42), clockwise: false)
            path.addLine(to: P(8.37, 9.97))
            path.addArc(center: P(8, 8), radius: 2 * k, startAngle: .degrees(79.3), endAngle: .degrees(10.7), clockwise: true)
            path.closeSubpath()

            path.move(to: P(20, 2))
            path.addLine(to: P(20, 6))

            path.move(to: P(22, 4))
            path.addLine(to: P(18, 4))
            path.addEllipse(in: CGRect(x: P(2, 18).x, y: P(2, 18).y, width: 4 * k, height: 4 * k))
        case .grid:

            path.addRoundedRect(in: CGRect(x: P(3, 3).x, y: P(3, 3).y, width: 18 * k, height: 18 * k), cornerSize: CGSize(width: 2 * k, height: 2 * k))

            path.move(to: P(3, 9))
            path.addLine(to: P(21, 9))

            path.move(to: P(3, 15))
            path.addLine(to: P(21, 15))

            path.move(to: P(9, 3))
            path.addLine(to: P(9, 21))

            path.move(to: P(15, 3))
            path.addLine(to: P(15, 21))
        case .zap:

            path.move(to: P(15.91, 4))
        case .zapOff:

            path.move(to: P(10.77, 5.11))
            path.move(to: P(13.44, 2.44))

            path.move(to: P(18.89, 13.23))
            path.move(to: P(19.56, 12.56))

            path.move(to: P(2, 2))
            path.move(to: P(22, 22))

            path.move(to: P(7.94, 7.94))
            path.move(to: P(4.44, 11.44))
        case .switchCamera:

            path.move(to: P(11, 19))
            path.addLine(to: P(4, 19))
            path.addArc(center: P(4, 17), radius: 2 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: P(2, 7))
            path.addArc(center: P(4, 7), radius: 2 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: P(9, 5))

            path.move(to: P(13, 5))
            path.addLine(to: P(20, 5))
            path.addArc(center: P(20, 7), radius: 2 * k, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: P(22, 17))
            path.addArc(center: P(20, 17), radius: 2 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: P(15, 19))
            path.addEllipse(in: CGRect(x: P(9, 9).x, y: P(9, 9).y, width: 6 * k, height: 6 * k))

            path.move(to: P(18, 22))
            path.move(to: P(15, 19))
            path.move(to: P(18, 16))

            path.move(to: P(6, 2))
            path.move(to: P(9, 5))
            path.move(to: P(6, 8))
        case .photo:

            path.addRoundedRect(in: CGRect(x: P(3, 3).x, y: P(3, 3).y, width: 18 * k, height: 18 * k), cornerSize: CGSize(width: 2 * k, height: 2 * k))
            path.addEllipse(in: CGRect(x: P(7, 7).x, y: P(7, 7).y, width: 4 * k, height: 4 * k))

            path.move(to: P(21, 15))
            path.move(to: P(17.91, 11.91))
            path.addArc(center: P(16.5, 13.33), radius: 2 * k, startAngle: .degrees(-45.01), endAngle: .degrees(-134.99), clockwise: true)
            path.addLine(to: P(6, 21))
        case .close:

            path.move(to: P(18, 6))
            path.move(to: P(6, 18))

            path.move(to: P(6, 6))
            path.move(to: P(18, 18))
        case .timer:

            path.move(to: P(10, 2))
            path.addLine(to: P(14, 2))
            path.move(to: P(12, 14))
            path.addLine(to: P(15, 11))
            path.addEllipse(in: CGRect(x: P(4, 6).x, y: P(4, 6).y, width: 16 * k, height: 16 * k))
        case .arrowLR:

            path.move(to: P(8, 3))
            path.move(to: P(4, 7))
            path.addLine(to: P(8, 11))

            path.move(to: P(4, 7))
            path.addLine(to: P(20, 7))

            path.move(to: P(16, 21))
            path.move(to: P(20, 17))
            path.move(to: P(16, 13))

            path.move(to: P(20, 17))
            path.addLine(to: P(4, 17))
        case .camera:

            path.move(to: P(14, 4))
            path.addArc(center: P(14, 6), radius: 2 * k, startAngle: .degrees(-90), endAngle: .degrees(-28.36), clockwise: false)
            path.addLine(to: P(16.24, 5.95))
            path.addArc(center: P(18, 5), radius: 2 * k, startAngle: .degrees(151.64), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: P(20, 7))
            path.addArc(center: P(20, 9), radius: 2 * k, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: P(22, 18))
            path.addArc(center: P(20, 18), radius: 2 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: P(4, 20))
            path.addArc(center: P(4, 18), radius: 2 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: P(2, 9))
            path.addArc(center: P(4, 9), radius: 2 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: P(6, 7))
            path.addArc(center: P(6, 5), radius: 2 * k, startAngle: .degrees(90), endAngle: .degrees(28.42), clockwise: true)
            path.addLine(to: P(8.25, 5.05))
            path.addArc(center: P(10, 6), radius: 2 * k, startAngle: .degrees(-151.58), endAngle: .degrees(-90), clockwise: false)
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: P(9, 10).x, y: P(9, 10).y, width: 6 * k, height: 6 * k))
        case .download:

            path.move(to: P(12, 15))
            path.addLine(to: P(12, 3))

            path.move(to: P(21, 15))
            path.addLine(to: P(21, 19))
            path.addArc(center: P(19, 19), radius: 2 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: P(5, 21))
            path.addArc(center: P(5, 19), radius: 2 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: P(3, 15))

            path.move(to: P(7, 10))
            path.move(to: P(12, 15))
            path.move(to: P(17, 10))
        case .share:

            path.addEllipse(in: CGRect(x: P(15, 2).x, y: P(15, 2).y, width: 6 * k, height: 6 * k))
            path.addEllipse(in: CGRect(x: P(3, 9).x, y: P(3, 9).y, width: 6 * k, height: 6 * k))
            path.addEllipse(in: CGRect(x: P(15, 16).x, y: P(15, 16).y, width: 6 * k, height: 6 * k))
            path.move(to: P(8.59, 13.51))
            path.addLine(to: P(15.42, 17.49))
            path.move(to: P(15.41, 6.51))
            path.addLine(to: P(8.59, 10.49))
        case .undo:

            path.move(to: P(9, 14))
            path.move(to: P(4, 9))
            path.addLine(to: P(9, 4))

            path.move(to: P(4, 9))
            path.addLine(to: P(14.5, 9))
            path.addArc(center: P(14.5, 14.5), radius: 5.5 * k, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addArc(center: P(14.5, 14.5), radius: 5.5 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: P(11, 20))
        case .eraser:

            path.move(to: P(21, 21))
            path.addLine(to: P(8, 21))
            path.addArc(center: P(8, 19), radius: 2 * k, startAngle: .degrees(89.87), endAngle: .degrees(135.05), clockwise: false)
            path.addLine(to: P(2.59, 16.41))
            path.addArc(center: P(4, 15), radius: 2 * k, startAngle: .degrees(135.01), endAngle: .degrees(224.99), clockwise: false)
            path.addLine(to: P(12.59, 3.59))
            path.addArc(center: P(14, 5), radius: 2 * k, startAngle: .degrees(-135.01), endAngle: .degrees(-44.99), clockwise: false)
            path.addLine(to: P(21.41, 9.59))
            path.addArc(center: P(20, 11), radius: 2 * k, startAngle: .degrees(-44.99), endAngle: .degrees(44.99), clockwise: false)
            path.addLine(to: P(12.83, 21))

            path.move(to: P(5.08, 11.09))
            path.move(to: P(13.91, 19.92))
        case .brush:

            path.move(to: P(11, 10))
            path.move(to: P(14, 13))

            path.move(to: P(6.5, 21))
            path.addArc(center: P(6.5, 17.5), radius: 3.5 * k, startAngle: .degrees(90), endAngle: .degrees(-180), clockwise: true)
            path.addArc(center: P(0.38, 17.5), radius: 2.62 * k, startAngle: .degrees(-0.02), endAngle: .degrees(43.13), clockwise: false)
            path.addArc(center: P(3, 20), radius: 1 * k, startAngle: .degrees(-134.93), endAngle: .degrees(-270.1), clockwise: true)
            path.closeSubpath()

            path.move(to: P(9.97, 17.03))
            path.move(to: P(21.38, 5.62))
            path.addArc(center: P(19.88, 4.12), radius: 2.12 * k, startAngle: .degrees(45), endAngle: .degrees(-135), clockwise: true)
            path.addLine(to: P(6.97, 14.03))
        case .wand:

            path.move(to: P(21.64, 3.64))
            path.move(to: P(20.36, 2.36))
            path.addArc(center: P(19.5, 3.21), radius: 1.21 * k, startAngle: .degrees(-44.7), endAngle: .degrees(-135.3), clockwise: true)
            path.addLine(to: P(2.36, 18.64))
            path.addArc(center: P(3.21, 19.5), radius: 1.21 * k, startAngle: .degrees(-134.7), endAngle: .degrees(-225.3), clockwise: true)
            path.addLine(to: P(3.64, 21.64))
            path.addArc(center: P(4.5, 20.8), radius: 1.2 * k, startAngle: .degrees(135.78), endAngle: .degrees(44.22), clockwise: true)
            path.addLine(to: P(21.64, 5.36))
            path.addArc(center: P(20.8, 4.5), radius: 1.2 * k, startAngle: .degrees(45.78), endAngle: .degrees(-45.78), clockwise: true)

            path.move(to: P(14, 7))
            path.move(to: P(17, 10))

            path.move(to: P(5, 6))
            path.addLine(to: P(5, 10))

            path.move(to: P(19, 14))
            path.addLine(to: P(19, 18))

            path.move(to: P(10, 2))
            path.addLine(to: P(10, 4))

            path.move(to: P(7, 8))
            path.addLine(to: P(3, 8))

            path.move(to: P(21, 16))
            path.addLine(to: P(17, 16))

            path.move(to: P(11, 3))
            path.addLine(to: P(9, 3))
        case .check:

            path.move(to: P(20, 6))
            path.move(to: P(9, 17))
            path.addLine(to: P(4, 12))
        case .rotateCCW:

            path.move(to: P(3, 12))
            path.addArc(center: P(12, 12), radius: 9 * k, startAngle: .degrees(180), endAngle: .degrees(-90), clockwise: true)
            path.addArc(center: P(12.04, 12.75), radius: 9.75 * k, startAngle: .degrees(-90.22), endAngle: .degrees(-134.03), clockwise: true)
            path.addLine(to: P(3, 8))

            path.move(to: P(3, 3))
            path.addLine(to: P(3, 8))
            path.addLine(to: P(8, 8))
        case .trash:

            path.move(to: P(10, 11))
            path.addLine(to: P(10, 17))

            path.move(to: P(14, 11))
            path.addLine(to: P(14, 17))

            path.move(to: P(19, 6))
            path.addLine(to: P(19, 20))
            path.addArc(center: P(17, 20), radius: 2 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: P(7, 22))
            path.addArc(center: P(7, 20), radius: 2 * k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: P(5, 6))

            path.move(to: P(3, 6))
            path.addLine(to: P(21, 6))

            path.move(to: P(8, 6))
            path.addLine(to: P(8, 4))
            path.addArc(center: P(10, 4), radius: 2 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: P(14, 2))
            path.addArc(center: P(14, 4), radius: 2 * k, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: P(16, 6))
        case .beauty:

            path.addEllipse(in: CGRect(x: P(4, 4).x, y: P(4, 4).y, width: 16 * k, height: 16 * k))
            path.move(to: P(9, 10))
            path.addLine(to: P(9.01, 10))
            path.move(to: P(15, 10))
            path.addLine(to: P(15.01, 10))
            path.move(to: P(8.5, 14.5))
            path.addQuadCurve(to: P(15.5, 14.5), control: P(12, 17))

        case .settings:

            path.move(to: P(4, 7))
            path.addLine(to: P(20, 7))
            path.move(to: P(4, 12))
            path.addLine(to: P(20, 12))
            path.move(to: P(4, 17))
            path.addLine(to: P(20, 17))
            path.addEllipse(in: CGRect(x: P(8, 5.2).x, y: P(8, 5.2).y, width: 3.6 * k, height: 3.6 * k))
            path.addEllipse(in: CGRect(x: P(14, 10.2).x, y: P(14, 10.2).y, width: 3.6 * k, height: 3.6 * k))
            path.addEllipse(in: CGRect(x: P(6, 15.2).x, y: P(6, 15.2).y, width: 3.6 * k, height: 3.6 * k))

        case .film:

            path.move(to: P(6, 5))
            path.addLine(to: P(18, 5))
            path.addLine(to: P(18, 19))
            path.addLine(to: P(6, 19))
            path.closeSubpath()
            for yy in [7.5, 10.5, 13.5, 16.5] {
                path.move(to: P(7.6, yy))
                path.addLine(to: P(7.65, yy))
                path.move(to: P(16.4, yy))
                path.addLine(to: P(16.45, yy))
            }
        }
        return path
    }
}

struct AppIconView: View {
    let name: AppIcon
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.7
    var color: Color = .white

    var body: some View {
        AppIconShape(name: name)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

struct AppIconFillView: View {
    let name: AppIcon
    var size: CGFloat = 20
    var color: Color = .white

    var body: some View {
        AppIconShape(name: name)
            .fill(color)
            .frame(width: size, height: size)
    }
}
