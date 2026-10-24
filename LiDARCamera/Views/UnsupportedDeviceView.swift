import SwiftUI

struct UnsupportedDeviceView: View {
    let report: LiDARCapabilityReport
    let onRetry: () -> Void

    @State private var showDevices = false

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                hero
                reportCard
                devicesCard
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                SensorMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LIDAR")
                        .font(.mono(10, weight: .bold))
                        .tracking(2.6)
                        .foregroundStyle(AppTheme.text)
                    Text("CAMERA")
                        .font(.mono(8, weight: .medium))
                        .tracking(2.1)
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Spacer()

            CapsuleTag(text: "HARDWARE CHECK", icon: "checkmark.shield", color: AppTheme.amber)
        }
    }

    private var hero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppTheme.amber.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)

                Circle()
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    .frame(width: 150, height: 150)

                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 7]))
                    .foregroundStyle(AppTheme.amber.opacity(0.3))
                    .frame(width: 196, height: 196)

                Image(systemName: "iphone")
                    .font(.system(size: 58, weight: .ultraLight))
                    .foregroundStyle(AppTheme.muted)

                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
                    .background(Circle().fill(AppTheme.background).frame(width: 26, height: 26))
                    .offset(x: 36, y: -38)
            }
            .frame(height: 210)

            VStack(spacing: 12) {
                Text(report.unsupportedTitle)
                    .font(.display(30, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)

                Text(report.unsupportedMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var reportCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SENSOR REPORT")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text(report.deviceModel.uppercased())
                    .font(.mono(9.5, weight: .medium))
                    .foregroundStyle(AppTheme.muted.opacity(0.8))
            }
            .padding(.bottom, 14)

            checkRow("LiDAR / scene depth", ok: report.hasSceneDepth)
            Divider().overlay(AppTheme.hairline)
            checkRow("Smoothed depth", ok: report.hasSmoothedDepth)
            Divider().overlay(AppTheme.hairline)
            checkRow("ARKit world tracking", ok: report.hasWorldTracking)
            Divider().overlay(AppTheme.hairline)

            HStack {
                HStack(spacing: 7) {
                    StatusDot(color: AppTheme.amber)
                    Text("REGULAR CAMERA")
                        .font(.mono(10, weight: .medium))
                        .tracking(1.0)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text("Never used")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.vertical, 14)
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var devicesCard: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showDevices.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.cyan)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Which iPhones have LiDAR?")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(AppTheme.text)
                        Text("Pro models only")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.muted)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .rotationEffect(.degrees(showDevices ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDevices {
                VStack(alignment: .leading, spacing: 12) {
                    Text(SupportedDevices.summary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppTheme.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    WrapTags(items: SupportedDevices.iphones, color: AppTheme.cyan)
                }
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            Button(action: onRetry) {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.clockwise")
                    Text("Check again")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: AppTheme.amber))

            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                Text("No camera was opened during this check.")
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(AppTheme.muted.opacity(0.8))
        }
    }

    private func checkRow(_ title: String, ok: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(AppTheme.text.opacity(0.92))
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? AppTheme.accent : AppTheme.amber.opacity(0.8))
                    .frame(width: 5, height: 5)
                Text(ok ? "AVAILABLE" : "NOT FOUND")
                    .font(.mono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(ok ? AppTheme.accent : AppTheme.muted)
            }
        }
        .padding(.vertical, 14)
    }
}

struct SensorMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.18), AppTheme.cyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.34), lineWidth: 1)
                }

            ZStack {
                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.75), lineWidth: 1.2)
                    .frame(width: size * 0.44, height: size * 0.44)
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: size * 0.13, height: size * 0.13)
                Circle()
                    .trim(from: 0.55, to: 0.95)
                    .stroke(AppTheme.cyan, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .frame(width: size * 0.70, height: size * 0.70)
                    .rotationEffect(.degrees(-35))
            }
        }
        .frame(width: size, height: size)
    }
}

struct WrapTags: View {
    var items: [String]
    var color: Color = AppTheme.cyan

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 6, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.text.opacity(0.8))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(color.opacity(0.14), lineWidth: 1)
                            }
                    }
            }
        }
    }
}
