import SwiftUI
import UIKit

struct ScanView: View {
    let initialMode: ScanMode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: CaptureLibrary
    @StateObject private var engine = DepthEngine()

    @AppStorage("preferredDepthPalette") private var savedPalette = DepthPalette.thermal.rawValue

    @State private var showActivation = true
    @State private var hasRequestedStart = false
    @State private var isSaving = false
    @State private var showPalettes = false
    @State private var activeCapture: CaptureRecord?
    @State private var toastText: String?
    @State private var captureErrorMessage = ""
    @State private var showCaptureError = false
    @State private var flashOpacity: Double = 0

    @State private var lastDragTranslation: CGSize = .zero
    @State private var zoomStart: CGFloat = 1

    private var modeBinding: Binding<ScanMode> {
        Binding(
            get: { engine.mode },
            set: { engine.mode = $0 }
        )
    }

    private var paletteBinding: Binding<DepthPalette> {
        Binding(
            get: { engine.palette },
            set: {
                engine.palette = $0
                savedPalette = $0.rawValue
            }
        )
    }

    private var latestCapture: CaptureRecord? {
        library.captures.first
    }

    var body: some View {
        ZStack {
            Color(hex: 0x05070A)
                .ignoresSafeArea()

            MetalDepthSurface(engine: engine)
                .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0.0),
                    .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 0.56),
                    .init(color: .black.opacity(0.82), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            interactionLayer

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                if engine.state.isLive {
                    ScanMetricsStrip(metrics: engine.metrics)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if engine.isInterrupted {
                    interruptedBanner
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                }

                Spacer(minLength: 12)

                if engine.state.isLive && engine.mode == .pointCloud {
                    interactionHint
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }

                if let toastText {
                    ScanToast(text: toastText)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                bottomPanel
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if showActivation {
                ScanActivationOverlay(
                    state: engine.state,
                    hasRequestedStart: hasRequestedStart,
                    onActivate: activate,
                    onRetry: retry,
                    onOpenSettings: openSettings,
                    onCancel: { dismiss() }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .onAppear {
            engine.mode = initialMode
            if let saved = DepthPalette(rawValue: savedPalette) {
                engine.palette = saved
            }
        }
        .onChange(of: engine.state) { _, newState in
            if newState.isLive {
                withAnimation(.easeOut(duration: 0.35)) {
                    showActivation = false
                }
            } else if newState.isFailure {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showActivation = true
                }
            }
        }
        .onDisappear {
            engine.stop()
        }
        .sheet(item: $activeCapture) { record in
            CaptureDetailView(record: record)
                .environmentObject(library)
        }
        .alert("Capture failed", isPresented: $showCaptureError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(captureErrorMessage)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle(size: 40))

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Text(engine.mode.title.uppercased())
                    .font(.mono(10, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(AppTheme.text)

                HStack(spacing: 5) {
                    StatusDot(color: statusColor)
                    Text(statusText)
                        .font(.mono(8, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer(minLength: 0)

            CapsuleTag(text: "RGB OFF", icon: "video.slash", color: AppTheme.muted)
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .streaming: return AppTheme.accent
        case .starting: return AppTheme.amber
        case .failed: return AppTheme.danger
        case .idle: return AppTheme.muted
        }
    }

    private var statusText: String {
        switch engine.state {
        case .streaming: return "LIVE DEPTH"
        case .starting: return "STARTING"
        case .failed: return "OFFLINE"
        case .idle: return "STANDBY"
        }
    }

    private var interruptedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(AppTheme.amber)
            Text("Tracking paused — point at a textured surface")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.text.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(AppTheme.amber.opacity(0.08)))
                .overlay(Capsule().strokeBorder(AppTheme.amber.opacity(0.18), lineWidth: 1))
        }
    }

    private var interactionHint: some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.draw")
                .font(.system(size: 10, weight: .medium))
            Text("DRAG TO LOOK · PINCH TO ZOOM")
                .font(.mono(8.5, weight: .medium))
                .tracking(1.0)
        }
        .foregroundStyle(AppTheme.text.opacity(0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.34))
                .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: Bottom controls

    private var bottomPanel: some View {
        VStack(spacing: 13) {
            ScanModePicker(selection: modeBinding)

            if showPalettes {
                PaletteTray(selection: paletteBinding)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 0) {
                ScanGalleryButton(
                    record: latestCapture,
                    image: latestCapture.flatMap { library.thumbnail(for: $0) }
                ) {
                    guard let latestCapture else { return }
                    Haptics.light()
                    activeCapture = latestCapture
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScanShutterButton(
                    isEnabled: engine.state.isLive,
                    isBusy: isSaving,
                    accent: engine.mode.accent,
                    action: capture
                )

                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showPalettes.toggle()
                    }
                } label: {
                    PaletteButton(palette: engine.palette)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 8)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .shadow(color: .black.opacity(0.45), radius: 32, y: 16)
        }
    }

    // MARK: Gestures

    private var interactionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard engine.state.isLive, engine.mode == .pointCloud else { return }
                let dx = value.translation.width - lastDragTranslation.width
                let dy = value.translation.height - lastDragTranslation.height
                lastDragTranslation = value.translation
                engine.orbit(deltaX: dx, deltaY: dy)
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard engine.state.isLive, engine.mode == .pointCloud else { return }
                engine.setZoom(zoomStart * value.magnification)
            }
            .onEnded { value in
                guard engine.mode == .pointCloud else { return }
                zoomStart = min(max(zoomStart * value.magnification, 1.0), 1.8)
                engine.setZoom(zoomStart)
            }
    }

    // MARK: Actions

    private func activate() {
        Haptics.medium()
        hasRequestedStart = true
        engine.start()
    }

    private func retry() {
        Haptics.medium()
        hasRequestedStart = true
        engine.start()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func capture() {
        guard engine.state.isLive, !isSaving else { return }
        Haptics.medium()
        isSaving = true

        let snapshot: DepthSnapshot
        do {
            snapshot = try engine.captureSnapshot()
        } catch {
            isSaving = false
            Haptics.error()
            captureErrorMessage = error.localizedDescription
            showCaptureError = true
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            flashOpacity = 0.42
        }
        withAnimation(.easeIn(duration: 0.35).delay(0.10)) {
            flashOpacity = 0
        }

        Task { @MainActor in
            do {
                let record = try await library.save(snapshot: snapshot)
                Haptics.success()
                showToast("\(record.mode.title) saved")
            } catch {
                Haptics.error()
                captureErrorMessage = error.localizedDescription
                showCaptureError = true
            }
            isSaving = false
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            toastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastText == text {
                    toastText = nil
                }
            }
        }
    }
}
