import SwiftUI
import MetalKit
import CoreVideo
import CoreImage

struct MetalPreview: UIViewRepresentable {
    @ObservedObject var engine: CameraEngine
    @ObservedObject var viewModel: CameraViewModel

    var lutCache: [String: (Data, Int)] = [:]

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.backgroundColor = .black

        let renderer = PreviewRenderer(viewModel: viewModel)
        context.coordinator.renderer = renderer
        view.delegate = renderer

        engine.onVideoFrame = { [weak renderer] buffer in
            renderer?.update(buffer: buffer)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: PreviewRenderer?
    }
}

final class PreviewRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext
    private weak var viewModel: CameraViewModel?

    private let lock = NSLock()
    private var latestBuffer: CVPixelBuffer?

    init(viewModel: CameraViewModel) {
        self.viewModel = viewModel
        if let device = MTLCreateSystemDefaultDevice() {
            self.commandQueue = device.makeCommandQueue()
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.commandQueue = nil
            self.ciContext = CIContext()
        }
        super.init()
    }

    func update(buffer: CVPixelBuffer) {
        lock.lock()
        latestBuffer = buffer
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let drawable = view.currentDrawable else { return }

        lock.lock()
        let buffer = latestBuffer
        lock.unlock()
        guard let pixelBuffer = buffer else { return }

        var image = CIImage(cvPixelBuffer: pixelBuffer)

        let isFront = viewModel?.engine.cameraPosition == .front
        image = image.oriented(isFront ? .leftMirrored : .right)

        if let vm = viewModel {
            if vm.beautyEnabled {
                image = BeautyProcessor.apply(image, level: vm.beautyLevel)
            }
            image = vm.currentFilter.apply(image)
            if let lut = vm.activeLUT {
                image = CubeLUTParser.apply(image, lut: lut, cache: &lutCache, intensity: vm.lutIntensity)
            }
        }

        let target = CGRect(origin: .zero, size: view.drawableSize)
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return }
        let scale = max(target.width / extent.width, target.height / extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tx = target.midX - image.extent.midX
        let ty = target.midY - image.extent.midY
        image = image.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        guard let cmd = commandQueue.makeCommandBuffer() else { return }
        ciContext.render(image,
                         to: drawable.texture,
                         commandBuffer: cmd,
                         bounds: target,
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        cmd.present(drawable)
        cmd.commit()
    }
}
