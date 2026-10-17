import CoreMotion
import SwiftUI

final class MotionManager: ObservableObject {

    static let shared = MotionManager()
    private let mgr = CMMotionManager()

    @Published var roll: Double = 99

    @Published var heading: Double = -1
    @Published var available = false

    private var running = false

    func start() {
        guard !running else { return }
        running = true
        if mgr.isDeviceMotionAvailable {
            available = true
            mgr.deviceMotionUpdateInterval = 0.12
            mgr.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self = self, let m = motion else { return }

                let g = m.gravity
                let angle = atan2(g.y, g.x) - Double.pi / 2
                self.roll = angle
            }
        }
        if mgr.isMagnetometerAvailable {
            mgr.magnetometerUpdateInterval = 0.5
            mgr.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let m = data?.magneticField else { return }

                let ang = atan2(m.x, -m.y) * 180.0 / Double.pi
                self?.heading = ang < 0 ? ang + 360 : ang
            }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        mgr.stopDeviceMotionUpdates()
        mgr.stopMagnetometerUpdates()
        roll = 99
        heading = -1
    }

    var isLevel: Bool { abs(rollDegrees) < 2.0 }
    var rollDegrees: Double { roll == 99 ? 99 : roll * 180.0 / Double.pi }

    var compassLabel: String? {
        guard heading >= 0 else { return nil }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((heading + 22.5) / 45.0) % 8
        return dirs[idx] + String(format: " %.0f°", heading)
    }
}

struct LevelCompassOverlay: View {
    @ObservedObject var motion = MotionManager.shared

    var body: some View {
        VStack(spacing: 6) {

            if motion.available && motion.roll != 99 {
                ZStack {
                    Rectangle()
                        .fill(motion.isLevel ? Color.green.opacity(0.85) : Color.white.opacity(0.55))
                        .frame(width: motion.isLevel ? 90 : 130, height: 1.5)
                    if motion.isLevel {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .rotationEffect(.degrees(motion.rollDegrees))
                .animation(.linear(duration: 0.1), value: motion.rollDegrees)
            }

            Spacer()

            if let label = motion.compassLabel {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
        }
    }
}

struct FocusPeakingOverlay: View {
    @ObservedObject private var fa = FrameAnalyzer.shared

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / 8
            let ch = geo.size.height / 8
            ForEach(0..<64, id: \.self) { i in
                if fa.peakingGrid[i] {
                    Circle()
                        .fill(Color(red: 0.2, green: 1.0, blue: 0.5).opacity(0.85))
                        .frame(width: 5, height: 5)
                        .position(x: CGFloat(i % 8) * cw + cw / 2,
                                  y: CGFloat(i / 8) * ch + ch / 2)
                }
            }
        }
    }
}

final class FrameAnalyzer: ObservableObject {

    static let shared = FrameAnalyzer()

    @Published var histR: [Float] = Array(repeating: 0.02, count: 32)
    @Published var histG: [Float] = Array(repeating: 0.02, count: 32)
    @Published var histB: [Float] = Array(repeating: 0.02, count: 32)

    @Published var overexposure: Float = 0
    @Published var enabled = true

    @Published var peakingGrid: [Bool] = Array(repeating: false, count: 64)
    var peakingEnabled = false

    private var skipCounter = 0

    func analyze(_ buffer: CVPixelBuffer) {
        guard enabled else { return }
        skipCounter += 1
        guard skipCounter % 12 == 0 else { return }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)

        var hr = [Float](repeating: 0, count: 32)
        var hg = [Float](repeating: 0, count: 32)
        var hb = [Float](repeating: 0, count: 32)
        var burned = 0
        var total = 0

        let stride = max(1, min(w, h) / 64)

        var gridSum = [Float](repeating: 0, count: 64)
        var prevY: Float = -1
        for y in strideArrays(start: 0, end: h, by: stride) {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            prevY = -1
            for x in strideArrays(start: 0, end: w, by: stride) {
                let off = x * 4
                let r = row[off], g = row[off + 1], b = row[off + 2]
                let yv = (Float(r) * 0.2126 + Float(g) * 0.7152 + Float(b) * 0.0722) / 255.0
                if yv > 0.985 { burned += 1 }
                total += 1
                hr[min(31, Int(r) / 8)] += 1
                hg[min(31, Int(g) / 8)] += 1
                hb[min(31, Int(b) / 8)] += 1

                if peakingEnabled && prevY >= 0 {
                    let gx = min(7, x * 8 / max(1, w))
                    let gy = min(7, y * 8 / max(1, h))
                    gridSum[gy * 8 + gx] += abs(yv - prevY)
                }
                prevY = yv
            }
        }
        guard total > 0 else { return }

        let mx = max(hr.max() ?? 1, hg.max() ?? 1, hb.max() ?? 1, 1)

        let peakMax = gridSum.max() ?? 1
        let peakGrid: [Bool] = peakingEnabled
            ? gridSum.map { $0 >= peakMax * 0.5 && $0 > 0.02 }
            : Array(repeating: false, count: 64)
        DispatchQueue.main.async {
            self.histR = hr.map { max(0.02, $0 / mx) }
            self.histG = hg.map { max(0.02, $0 / mx) }
            self.histB = hb.map { max(0.02, $0 / mx) }
            self.overexposure = Float(burned) / Float(total)
            self.peakingGrid = peakGrid
        }
    }

    private func strideArrays(start: Int, end: Int, by: Int) -> [Int] {
        Array(stride(from: start, to: end, by: by))
    }
}

struct HistogramOverlay: View {
    @ObservedObject var analyzer = FrameAnalyzer.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geo in
                    let w = geo.size.width / 32
                    histPath(analyzer.histR)
                        .stroke(Color.red.opacity(0.75), lineWidth: 1)
                    histPath(analyzer.histG)
                        .stroke(Color.green.opacity(0.75), lineWidth: 1)
                    histPath(analyzer.histB)
                        .stroke(Color.blue.opacity(0.75), lineWidth: 1)
                    Color.clear
                }
                .frame(width: 78, height: 40)
                .background(Color.black.opacity(0.45))
                .cornerRadius(6)
            }
            if analyzer.overexposure > 0.05 {
                Text(String(format: "过曝 %.0f%%", analyzer.overexposure * 100))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.75)))
            }
        }
    }

    private func histPath(_ bins: [Float]) -> Path {
        var path = Path()
        let n = bins.count
        for (i, v) in bins.enumerated() {
            let x = CGFloat(i) / CGFloat(n - 1) * 78
            let y = 40 - CGFloat(v) * 38
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct ZebraOverlay: View {
    @ObservedObject var analyzer = FrameAnalyzer.shared

    var body: some View {
        Rectangle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.red.opacity(min(0.85, Double(analyzer.overexposure) * 3.5)), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: analyzer.overexposure > 0.05 ? 8 : 0
            )
            .animation(.easeInOut(duration: 0.3), value: analyzer.overexposure > 0.05)
    }
}
