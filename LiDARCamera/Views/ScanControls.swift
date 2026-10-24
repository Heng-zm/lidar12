import SwiftUI
import UIKit

// MARK: - Mode picker

struct ScanModePicker: View {
    @Binding var selection: ScanMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScanMode.allCases) { mode in
                Button {
                    guard selection != mode else { return }
                    Haptics.light()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.shortTitle)
                            .font(.mono(10, weight: .semibold))
                            .tracking(1.1)
                    }
                    .foregroundStyle(selection == mode ? mode.accent : AppTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selection == mode {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(mode.accent.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(mode.accent.opacity(0.28), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

// MARK: - Metrics

struct ScanMetricsStrip: View {
    let metrics: DepthMetrics

    var body: some View {
        HStack(spacing: 0) {
            metric("NEAR", value: value(metrics.minDepth))
            divider
            metric("CENTER", value: value(metrics.centerDepth))
            divider
            metric("FAR", value: value(metrics.maxDepth))
            divider
            metric("GRID", value: metrics.width > 0 ? "\(metrics.width)×\(metrics.height)" : "--")
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                        }
                }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.07))
            .frame(width: 1, height: 24)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.mono(7.5, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppTheme.muted.opacity(0.8))
            Text(value)
                .font(.mono(11.5, weight: .semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func value(_ depth: Float) -> String {
        depth > 0 ? String(format: "%.2f m", depth) : "--"
    }
}

// MARK: - Shutter

struct ScanShutterButton: View {
    let isEnabled: Bool
    let isBusy: Bool
    let accent: Color
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 78, height: 78)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(isEnabled ? 0.55 : 0.16), lineWidth: 2)
                    }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent, accent.opacity(0.75)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse && isEnabled ? 1.03 : 1)
                    .shadow(color: accent.opacity(isEnabled ? 0.4 : 0), radius: 18, y: 4)

                if isBusy {
                    ProgressView()
                        .tint(AppTheme.background)
                } else {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppTheme.background)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .opacity(isEnabled ? 1 : 0.5)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Palette

struct PaletteButton: View {
    let palette: DepthPalette

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1))

            Circle()
                .fill(
                    AngularGradient(
                        colors: palette.previewColors + [palette.previewColors[0]],
                        center: .center
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                .shadow(color: palette.previewColors[2].opacity(0.3), radius: 8)
        }
    }
}

struct PaletteTray: View {
    @Binding var selection: DepthPalette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DepthPalette.allCases) { palette in
                Button {
                    guard selection != palette else { return }
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = palette
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: palette.previewColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.8)
                            }

                        Text(palette.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(selection == palette ? AppTheme.text : AppTheme.muted)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(selection == palette ? Color.white.opacity(0.08) : Color.clear)
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        selection == palette ? Color.white.opacity(0.16) : Color.clear,
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.055), lineWidth: 1)
                }
        }
    }
}

// MARK: - Small gallery button

struct ScanGalleryButton: View {
    let record: CaptureRecord?
    let image: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.muted.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(record == nil)
        .opacity(record == nil ? 0.45 : 1)
    }
}

// MARK: - Toast

struct ScanToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AppTheme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.36)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }
}

// MARK: - Activation overlay

struct ScanActivationOverlay: View {
    let state: DepthSessionState
    let hasRequestedStart: Bool
    let onActivate: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            ScrollView {
                content
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 30)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = state {
            failureCard(message: message)
        } else if hasRequestedStart {
            startingCard
        } else {
            introCard
        }
    }

    private var introCard: some View {
        VStack(spacing: 20) {
            activationGlyph

            VStack(spacing: 10) {
                Text("Activate the LiDAR sensor")
                    .font(.display(26, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)

                Text("Depth is captured directly from the LiDAR scanner. The RGB camera feed is never shown, recorded, or saved.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                permissionRow(
                    icon: "sensor.tag.radiowaves.forward",
                    title: "LiDAR depth only",
                    detail: "No color video, no photos."
                )
                permissionRow(
                    icon: "camera.fill",
                    title: "Camera permission required by iOS",
                    detail: "ARKit needs it to power the LiDAR hardware."
                )
                permissionRow(
                    icon: "lock.shield",
                    title: "Nothing leaves this app",
                    detail: "Captures are stored locally on your iPhone."
                )
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    }
            }

            VStack(spacing: 10) {
                Button(action: onActivate) {
                    HStack(spacing: 8) {
                        Image(systemName: "sensor.tag.radiowaves.forward")
                        Text("Activate LiDAR")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Not now", action: onCancel)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.vertical, 4)
            }
        }
        .padding(22)
        .glassCard(cornerRadius: 28)
    }

    private var startingCard: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.12), lineWidth: 1)
                    .frame(width: 126, height: 126)
                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accent.opacity(0.1), AppTheme.accent, AppTheme.cyan],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 8) {
                Text("Waiting for depth")
                    .font(.display(24, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text("Approve camera access if iOS asks. It is used only to power the LiDAR sensor — no image feed is displayed.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Cancel", action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(22)
        .glassCard(cornerRadius: 28)
    }

    private func failureCard(message: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.danger.opacity(0.12))
                    .frame(width: 70, height: 70)
                    .overlay(Circle().strokeBorder(AppTheme.danger.opacity(0.25), lineWidth: 1))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.danger)
            }

            VStack(spacing: 9) {
                Text("LiDAR could not start")
                    .font(.display(24, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)
                Text("If you denied camera access, enable it in Settings. iOS requires it for ARKit to run the LiDAR sensor. This app still never shows or saves the camera feed.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(message)
                    .font(.mono(9.5))
                    .foregroundStyle(AppTheme.muted.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.top, 4)
            }

            VStack(spacing: 10) {
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onOpenSettings) {
                    HStack(spacing: 7) {
                        Image(systemName: "gearshape")
                        Text("Open Settings")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button("Back to home", action: onCancel)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(22)
        .glassCard(cornerRadius: 28)
    }

    private var activationGlyph: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.accent.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)

            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                .foregroundStyle(AppTheme.accent.opacity(0.28))
                .frame(width: 128, height: 128)

            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                .foregroundStyle(AppTheme.cyan.opacity(0.20))
                .frame(width: 162, height: 162)

            ZStack {
                Circle()
                    .fill(AppTheme.raised)
                    .frame(width: 70, height: 70)
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(height: 150)
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppTheme.accent.opacity(0.09)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.text.opacity(0.92))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}
