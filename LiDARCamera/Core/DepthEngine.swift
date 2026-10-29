import ARKit
import AVFoundation
import Combine
import CoreVideo
import Foundation
import MetalKit
import UIKit
import simd

// MARK: - Session state

enum DepthSessionState: Equatable {
    case idle
    case starting
    case streaming
    case failed(String)

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var isLive: Bool {
        if case .streaming = self { return true }
        return false
    }
}

struct DepthMetrics: Equatable {
    var minDepth: Float = 0
    var maxDepth: Float = 0
    var meanDepth: Float = 0
    var centerDepth: Float = 0
    var width: Int = 0
    var height: Int = 0
}

// MARK: - Engine

final class DepthEngine: NSObject, ObservableObject, ARSessionDelegate, MTKViewDelegate {
    @Published private(set) var state: DepthSessionState = .idle
    @Published private(set) var metrics = DepthMetrics()
    @Published private(set) var isInterrupted = false
    @Published private(set) var hasRenderedDepth = false
    @Published private(set) var renderIssue: String?

    @Published var mode: ScanMode = .depthMap {
        didSet { requestDisplay() }
    }

    @Published var palette: DepthPalette = .thermal {
        didSet { requestDisplay() }
    }

    private let session = ARSession()
    private let frameLock = NSLock()

    private weak var view: MTKView?
    private var renderer: MetalDepthRenderer?
    private var rendererSetupAttempted = false

    private var latestFrame: ARFrame?
    private var firstCameraTransform: simd_float4x4?
    private var announcedStreaming = false
    private var lastMetricsTimestamp: TimeInterval = 0
    private var startTimeout: DispatchWorkItem?

    private var orbitYaw: Float = 0
    private var orbitPitch: Float = 0
    private var zoom: Float = 1

    override init() {
        super.init()
        session.delegate = self
    }

    deinit {
        startTimeout?.cancel()
        session.pause()
    }

    // MARK: Lifecycle

    func attach(to view: MTKView) {
        self.view = view
        guard renderer == nil else {
            view.delegate = self
            view.setNeedsDisplay()
            return
        }

        // A missing Metal library or pipeline is not recoverable by retrying
        // inside every SwiftUI update. Fail once and leave the screen in a
        // stable state.
        guard !rendererSetupAttempted else { return }
        rendererSetupAttempted = true

        guard let renderer = MetalDepthRenderer(view: view) else {
            state = .failed("The Metal renderer could not be created on this device.")
            return
        }

        self.renderer = renderer
        view.delegate = self
        view.setNeedsDisplay()
    }

    func attachIfNeeded(to view: MTKView) {
        if renderer == nil || self.view !== view {
            attach(to: view)
        }
    }

    func start() {
        guard !state.isLive, state != .starting else { return }

        guard renderer != nil else {
            state = .failed("The depth renderer is not ready yet.")
            return
        }

        let report = LiDARCapabilityReport.current()
        guard report.isSupported else {
            state = .failed("This iPhone did not report a usable LiDAR sensor.")
            return
        }

        let cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthorization == .denied || cameraAuthorization == .restricted {
            state = .failed("Camera access is off. Open Settings and allow Camera so iOS can power the LiDAR sensor.")
            return
        }

        frameLock.lock()
        latestFrame = nil
        firstCameraTransform = nil
        frameLock.unlock()

        announcedStreaming = false
        lastMetricsTimestamp = 0
        metrics = DepthMetrics()
        isInterrupted = false
        hasRenderedDepth = false
        renderIssue = nil
        resetOrbit()
        state = .starting

        // Do not leave the user on an indefinite "waiting" screen when ARKit
        // cannot deliver depth (for example, camera access was denied).
        startTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .starting else { return }
            self.session.pause()
            self.startTimeout = nil
            self.state = .failed("No depth frames arrived. Check Camera access in Settings, then try again.")
        }
        startTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)

        let configuration = ARWorldTrackingConfiguration()
        // Smoothed depth is preferred when the device offers it; both paths
        // ultimately resolve through the same 16/32-bit reader below.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        } else {
            configuration.frameSemantics = [.sceneDepth]
        }
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        configuration.worldAlignment = .gravity

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        startTimeout?.cancel()
        startTimeout = nil
        session.pause()

        frameLock.lock()
        latestFrame = nil
        firstCameraTransform = nil
        frameLock.unlock()

        announcedStreaming = false
        isInterrupted = false
        hasRenderedDepth = false
        renderIssue = nil
        state = .idle
        requestDisplay()
    }

    // MARK: Orbit

    func orbit(deltaX: CGFloat, deltaY: CGFloat) {
        orbitYaw += Float(deltaX) * 0.0045
        orbitPitch += Float(deltaY) * 0.0045
        orbitPitch = min(max(orbitPitch, -1.15), 1.15)
        requestDisplay()
    }

    func setZoom(_ value: CGFloat) {
        zoom = min(max(Float(value), 1.0), 1.8)
        requestDisplay()
    }

    func resetOrbit() {
        orbitYaw = 0
        orbitPitch = 0
        zoom = 1
        requestDisplay()
    }

    // MARK: Capture

    func captureSnapshot() throws -> DepthSnapshot {
        frameLock.lock()
        let frame = latestFrame
        frameLock.unlock()

        guard let frame,
              let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            throw CaptureError.noDepthFrame
        }

        let depthMap = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        guard width > 0, height > 0 else { throw CaptureError.noDepthFrame }

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else {
            throw CaptureError.noDepthFrame
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            throw CaptureError.noDepthFrame
        }

        guard let sampleFormat = DepthSampleFormat(pixelBuffer: depthMap) else {
            throw CaptureError.noDepthFrame
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        let depths = sampleFormat.copyDepths(
            from: baseAddress,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )

        var minDepth: Float = .greatestFiniteMagnitude
        var maxDepth: Float = 0
        var sum: Float = 0
        var count: Float = 0

        for depth in depths {
            guard depth.isFinite, depth > 0.01, depth < 10 else { continue }
            minDepth = min(minDepth, depth)
            maxDepth = max(maxDepth, depth)
            sum += depth
            count += 1
        }

        guard count > 0, minDepth.isFinite else { throw CaptureError.noDepthFrame }

        let inverse = MetalDepthRenderer.displayInverseMatrix(
            frame: frame,
            viewportSize: CGSize(width: 540, height: 960)
        )

        let inverseValues: [Float] = [
            inverse.columns.0.x,
            inverse.columns.0.y,
            inverse.columns.1.x,
            inverse.columns.1.y,
            inverse.columns.2.x,
            inverse.columns.2.y,
        ]

        let imageResolution = frame.camera.imageResolution

        return DepthSnapshot(
            id: UUID(),
            createdAt: Date(),
            width: width,
            height: height,
            depths: depths,
            imageWidth: Int(imageResolution.width),
            imageHeight: Int(imageResolution.height),
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            displayInverse: inverseValues,
            mode: mode,
            palette: palette,
            minDepth: minDepth,
            maxDepth: maxDepth,
            meanDepth: sum / count
        )
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.smoothedSceneDepth != nil || frame.sceneDepth != nil else { return }

        frameLock.lock()
        latestFrame = frame
        if firstCameraTransform == nil {
            firstCameraTransform = frame.camera.transform
        }
        frameLock.unlock()

        if !announcedStreaming {
            announcedStreaming = true
            startTimeout?.cancel()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.state == .starting {
                    self.state = .streaming
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.view?.setNeedsDisplay()
        }

        guard frame.timestamp - lastMetricsTimestamp > 0.24,
              let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else {
            return
        }
        lastMetricsTimestamp = frame.timestamp

        guard let measured = measure(depthMap: depthMap) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.metrics = measured
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        startTimeout?.cancel()
        startTimeout = nil
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .failed(message)
            self.isInterrupted = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isInterrupted = true
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isInterrupted = false
        }
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        frameLock.lock()
        let frame = latestFrame
        let firstTransform = firstCameraTransform
        frameLock.unlock()

        guard let frame, let renderer else { return }

        switch renderer.draw(
            frame: frame,
            firstCameraTransform: firstTransform,
            mode: mode,
            palette: palette,
            orbitYaw: orbitYaw,
            orbitPitch: orbitPitch,
            zoom: zoom,
            in: view
        ) {
        case .rendered:
            if !hasRenderedDepth {
                hasRenderedDepth = true
            }
            if renderIssue != nil {
                renderIssue = nil
            }
        case .failed(let message):
            if renderIssue != message {
                renderIssue = message
            }
        case .waiting:
            break
        }
    }

    // MARK: Helpers

    private func requestDisplay() {
        if Thread.isMainThread {
            view?.setNeedsDisplay()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.view?.setNeedsDisplay()
            }
        }
    }

    private func measure(depthMap: CVPixelBuffer) -> DepthMetrics? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 1, height > 1 else { return nil }

        guard CVPixelBufferLockBaseAddress(depthMap, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        guard let sampleFormat = DepthSampleFormat(pixelBuffer: depthMap) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let step = 3
        var minDepth: Float = .greatestFiniteMagnitude
        var maxDepth: Float = 0
        var sum: Float = 0
        var count: Float = 0

        var y = 1
        while y < height {
            var x = 1
            while x < width {
                let depth = sampleFormat.value(
                    atX: x,
                    y: y,
                    baseAddress: baseAddress,
                    bytesPerRow: bytesPerRow
                )
                if depth.isFinite, depth > 0.01, depth < 10 {
                    minDepth = min(minDepth, depth)
                    maxDepth = max(maxDepth, depth)
                    sum += depth
                    count += 1
                }
                x += step
            }
            y += step
        }

        guard count > 0, minDepth.isFinite else { return nil }

        let center = sampleFormat.value(
            atX: width / 2,
            y: height / 2,
            baseAddress: baseAddress,
            bytesPerRow: bytesPerRow
        )

        return DepthMetrics(
            minDepth: minDepth,
            maxDepth: maxDepth,
            meanDepth: sum / count,
            centerDepth: center.isFinite ? center : 0,
            width: width,
            height: height
        )
    }
}
