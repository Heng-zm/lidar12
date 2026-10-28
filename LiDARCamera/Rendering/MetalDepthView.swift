import ARKit
import CoreVideo
import MetalKit
import SwiftUI
import simd
import UIKit

// MARK: - GPU uniforms

private struct DepthMapUniforms {
    var displayInverse: simd_float4x4
    var params: SIMD4<Float>
}

private struct PointCloudUniforms {
    var viewProjection: simd_float4x4
    var cameraTransform: simd_float4x4
    var intrinsics: simd_float4x4
    var sizes: SIMD4<UInt32>
    var params: SIMD4<Float>
}

// MARK: - Renderer

final class MetalDepthRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let depthPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var paletteTextures: [DepthPalette: MTLTexture] = [:]

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let queue = device.makeCommandQueue() else {
            return nil
        }

        guard let depthPipeline = Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: .bgra8Unorm,
            vertex: "depthMapVertex",
            fragment: "depthMapFragment",
            blending: false
        ), let pointPipeline = Self.makePipeline(
            device: device,
            library: library,
            pixelFormat: .bgra8Unorm,
            vertex: "pointCloudVertex",
            fragment: "pointCloudFragment",
            blending: true
        ) else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.depthPipeline = depthPipeline
        self.pointPipeline = pointPipeline

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.clearColor = MTLClearColorMake(0.010, 0.014, 0.022, 1.0)
        view.framebufferOnly = true
        view.isOpaque = true
        view.preferredFramesPerSecond = 30
        // Render on the display link instead of relying on setNeedsDisplay.
        // On-demand drawing can stall when the view is re-attached by SwiftUI,
        // leaving the depth surface black even though ARKit is streaming.
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) != kCVReturnSuccess {
            return nil
        }

        for palette in DepthPalette.allCases {
            if let texture = Self.makePaletteTexture(palette: palette, device: device) {
                paletteTextures[palette] = texture
            }
        }
    }

    func draw(
        frame: ARFrame,
        firstCameraTransform: simd_float4x4?,
        mode: ScanMode,
        palette: DepthPalette,
        orbitYaw: Float,
        orbitPitch: Float,
        zoom: Float,
        in view: MTKView
    ) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let textureCache,
              let paletteTexture = paletteTextures[palette] else {
            return
        }

        let depthMap = depthData.depthMap
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0,
              let sampleFormat = DepthSampleFormat(pixelBuffer: depthMap) else {
            return
        }

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            depthMap,
            nil,
            sampleFormat.metalPixelFormat,
            depthWidth,
            depthHeight,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess,
              let cvTexture,
              let depthTexture = CVMetalTextureGetTexture(cvTexture),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.label = "LiDAR depth pass"
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(view.drawableSize.width),
            height: Double(view.drawableSize.height),
            znear: 0,
            zfar: 1
        ))

        switch mode {
        case .depthMap:
            let displayInverse = Self.displayInverseMatrix(
                frame: frame,
                viewportSize: view.bounds.size
            )

            var uniforms = DepthMapUniforms(
                displayInverse: displayInverse,
                params: SIMD4(DepthVisualization.near, DepthVisualization.far, 0, 0)
            )

            encoder.setRenderPipelineState(depthPipeline)
            encoder.setFragmentBytes(
                &uniforms,
                length: MemoryLayout<DepthMapUniforms>.stride,
                index: 0
            )
            encoder.setFragmentTexture(depthTexture, index: 0)
            encoder.setFragmentTexture(paletteTexture, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        case .pointCloud:
            let aspect = Float(view.drawableSize.width / view.drawableSize.height)
            let fov = Float(68.0 / Double(max(zoom, 1.0)))
            let projection = Self.makePerspective(
                fovYRadians: fov * .pi / 180.0,
                aspect: aspect,
                nearZ: 0.05,
                farZ: 12.0
            )

            let anchor = firstCameraTransform.map { simd_inverse($0) } ?? matrix_identity_float4x4
            let yawRotation = simd_float4x4(simd_quatf(angle: orbitYaw, axis: SIMD3<Float>(0, 1, 0)))
            let pitchRotation = simd_float4x4(simd_quatf(angle: orbitPitch, axis: SIMD3<Float>(1, 0, 0)))
            let viewMatrix = pitchRotation * yawRotation * anchor
            let viewProjection = projection * viewMatrix

            let cameraIntrinsics = frame.camera.intrinsics
            var intrinsics = matrix_identity_float4x4
            intrinsics.columns.0.x = cameraIntrinsics.columns.0.x
            intrinsics.columns.1.y = cameraIntrinsics.columns.1.y
            intrinsics.columns.2.x = cameraIntrinsics.columns.2.x
            intrinsics.columns.2.y = cameraIntrinsics.columns.2.y

            let imageResolution = frame.camera.imageResolution
            let drawableScale = Float(view.drawableSize.height / max(view.bounds.height, 1))

            var uniforms = PointCloudUniforms(
                viewProjection: viewProjection,
                cameraTransform: frame.camera.transform,
                intrinsics: intrinsics,
                sizes: SIMD4<UInt32>(
                    UInt32(depthWidth),
                    UInt32(depthHeight),
                    UInt32(imageResolution.width),
                    UInt32(imageResolution.height)
                ),
                params: SIMD4<Float>(DepthVisualization.near, DepthVisualization.far, drawableScale, 1)
            )

            let vertexCount = depthWidth * depthHeight

            encoder.setRenderPipelineState(pointPipeline)
            encoder.setVertexBytes(
                &uniforms,
                length: MemoryLayout<PointCloudUniforms>.stride,
                index: 0
            )
            encoder.setVertexTexture(depthTexture, index: 0)
            encoder.setFragmentTexture(paletteTexture, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Helpers

    static func displayInverseMatrix(frame: ARFrame, viewportSize: CGSize) -> simd_float4x4 {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return matrix_identity_float4x4
        }

        let display = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let normalizer = CGAffineTransform(
            scaleX: 1.0 / viewportSize.width,
            y: 1.0 / viewportSize.height
        )
        let inverse = display.concatenating(normalizer).inverted()

        var matrix = matrix_identity_float4x4
        matrix.columns.0 = SIMD4<Float>(Float(inverse.a), Float(inverse.b), 0, 0)
        matrix.columns.1 = SIMD4<Float>(Float(inverse.c), Float(inverse.d), 0, 0)
        matrix.columns.2 = SIMD4<Float>(Float(inverse.tx), Float(inverse.ty), 1, 0)
        return matrix
    }

    fileprivate static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        vertex: String,
        fragment: String,
        blending: Bool
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = vertex
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        if blending {
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    fileprivate static func makePaletteTexture(palette: DepthPalette, device: MTLDevice) -> MTLTexture? {
        let count = 256
        var bytes = [UInt8](repeating: 0, count: count * 4)

        for index in 0..<count {
            let color = palette.color(at: Float(index) / Float(count - 1))
            let offset = index * 4
            bytes[offset] = UInt8(min(max(Int(color.x * 255), 0), 255))
            bytes[offset + 1] = UInt8(min(max(Int(color.y * 255), 0), 255))
            bytes[offset + 2] = UInt8(min(max(Int(color.z * 255), 0), 255))
            bytes[offset + 3] = 255
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: count,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, count, 1),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: count * 4
            )
        }
        return texture
    }

    private static func makePerspective(
        fovYRadians: Float,
        aspect: Float,
        nearZ: Float,
        farZ: Float
    ) -> simd_float4x4 {
        let ys = 1.0 / tan(fovYRadians * 0.5)
        let xs = ys / max(aspect, 0.001)
        let zs = farZ / (nearZ - farZ)

        return simd_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }
}

// MARK: - SwiftUI bridge

struct MetalDepthSurface: UIViewRepresentable {
    @ObservedObject var engine: DepthEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.backgroundColor = UIColor(red: 0.01, green: 0.014, blue: 0.022, alpha: 1)
        view.isUserInteractionEnabled = true
        engine.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        engine.attachIfNeeded(to: uiView)
        uiView.setNeedsDisplay()
    }
}

#if DEBUG
// MARK: - Synthetic depth pipeline check

/// Renders a generated depth buffer through the real depth-map shader.
/// Used by the simulator smoke test to prove the Metal path itself works.
final class SyntheticDepthRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let paletteTexture: MTLTexture
    private let depthTexture: MTLTexture

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let queue = device.makeCommandQueue(),
              let pipeline = MetalDepthRenderer.makePipeline(
                  device: device,
                  library: library,
                  pixelFormat: .bgra8Unorm,
                  vertex: "depthMapVertex",
                  fragment: "depthMapFragment",
                  blending: false
              ),
              let palette = MetalDepthRenderer.makePaletteTexture(palette: .thermal, device: device) else {
            return nil
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float,
            width: 256,
            height: 192,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let depth = device.makeTexture(descriptor: descriptor) else { return nil }

        var samples = [Float16](repeating: 0, count: 256 * 192)
        for y in 0..<192 {
            for x in 0..<256 {
                let horizontal = Float(x) / 255.0
                let vertical = Float(y) / 191.0
                samples[y * 256 + x] = Float16(0.35 + 4.2 * horizontal * (0.55 + 0.45 * vertical))
            }
        }

        samples.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            depth.replace(
                region: MTLRegionMake2D(0, 0, 256, 192),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: 256 * MemoryLayout<Float16>.size
            )
        }

        self.commandQueue = queue
        self.pipeline = pipeline
        self.paletteTexture = palette
        self.depthTexture = depth

        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.010, 0.014, 0.022, 1.0)
        view.framebufferOnly = true
        view.isOpaque = true
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }

        var uniforms = DepthMapUniforms(
            displayInverse: matrix_identity_float4x4,
            params: SIMD4<Float>(0.2, 5.0, 0, 0)
        )

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DepthMapUniforms>.stride,
            index: 0
        )
        encoder.setFragmentTexture(depthTexture, index: 0)
        encoder.setFragmentTexture(paletteTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct SyntheticDepthSurface: UIViewRepresentable {
    final class Coordinator {
        var renderer: SyntheticDepthRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.backgroundColor = UIColor(red: 0.01, green: 0.014, blue: 0.022, alpha: 1)
        context.coordinator.renderer = SyntheticDepthRenderer(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#endif
