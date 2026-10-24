import Foundation
import SwiftUI

struct HomeView: View {
    let report: LiDARCapabilityReport
    let onRecheck: () -> Void

    @EnvironmentObject private var library: CaptureLibrary
    @State private var path: [HomeRoute] = []
    @State private var showInfo = false

    enum HomeRoute: Hashable {
        case scan(ScanMode)
        case library
        case capture(CaptureRecord)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 26) {
                    header
                    hero
                    modeSection
                    recentSection
                    privacyCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .scan(let mode):
                    ScanView(initialMode: mode)
                case .library:
                    LibraryView()
                case .capture(let record):
                    CaptureDetailView(record: record)
                }
            }
        }
        .onAppear { library.reload() }
        .sheet(isPresented: $showInfo) {
            InfoSheet(report: report, onRecheck: onRecheck)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            SensorMark(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("LIDAR CAMERA")
                    .font(.mono(11, weight: .bold))
                    .tracking(2.4)
                    .foregroundStyle(AppTheme.text)
                HStack(spacing: 5) {
                    StatusDot()
                    Text("DEPTH SENSOR VERIFIED")
                        .font(.mono(7.8, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(AppTheme.accent.opacity(0.9))
                }
            }

            Spacer()

            Button {
                Haptics.light()
                showInfo = true
            } label: {
                Image(systemName: "info")
            }
            .buttonStyle(IconButtonStyle(size: 38))

            NavigationLink(value: HomeRoute.library) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Circle().strokeBorder(AppTheme.hairline, lineWidth: 1))
                        }

                    if !library.captures.isEmpty {
                        Text("\(library.captures.count)")
                            .font(.mono(8, weight: .bold))
                            .foregroundStyle(AppTheme.background)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(AppTheme.accent))
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.raised,
                            Color(hex: 0x0A1B19),
                            Color(hex: 0x090B13),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            DepthFieldArtwork()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .opacity(0.9)

            LinearGradient(
                colors: [AppTheme.background.opacity(0.0), AppTheme.background.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    CapsuleTag(text: "LIDAR ONLY", icon: "sensor.tag.radiowaves.forward", color: AppTheme.accent)
                    CapsuleTag(text: "RGB OFF", icon: "video.slash", color: AppTheme.muted)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("See distance.")
                        .font(.display(38, weight: .bold))
                        .foregroundStyle(AppTheme.text)
                    Text("Not pixels.")
                        .font(.display(38, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Text("A depth camera that ignores the picture. Map your space in meters, build point clouds, and keep every capture on device.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.text.opacity(0.72))
                    .lineSpacing(3.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330, alignment: .leading)

                NavigationLink(value: HomeRoute.scan(.depthMap)) {
                    HStack(spacing: 10) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Open LiDAR")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .font(.display(15.5, weight: .semibold))
                .foregroundStyle(AppTheme.background)
                .padding(.horizontal, 18)
                .frame(height: 48)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AppTheme.accent)
                }
                .shadow(color: AppTheme.accent.opacity(0.28), radius: 16, y: 8)
                .padding(.top, 2)
            }
            .padding(22)
        }
        .frame(height: 430)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.4), radius: 36, y: 22)
    }

    // MARK: Modes

    private var modeSection: some View {
        VStack(spacing: 12) {
            SectionLabel(text: "Capture mode", trailing: "NO RGB FEED")

            ForEach(ScanMode.allCases) { mode in
                NavigationLink(value: HomeRoute.scan(mode)) {
                    ModeRow(mode: mode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Recent captures

    private var recentSection: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("DEPTH LIBRARY")
                    .font(.mono(10, weight: .semibold))
                    .tracking(2.0)
                    .foregroundStyle(AppTheme.muted)

                Spacer()

                if !library.captures.isEmpty {
                    NavigationLink(value: HomeRoute.library) {
                        Text("View all")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if library.captures.isEmpty {
                EmptyLibraryCard {
                    path.append(.scan(.depthMap))
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(library.captures.prefix(6)) { capture in
                            NavigationLink(value: HomeRoute.capture(capture)) {
                                RecentCaptureTile(record: capture)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }

    // MARK: Privacy

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Camera feed stays off")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text("Only LiDAR depth is read. The RGB video stream is never displayed, recorded, or saved. Captures remain in this app.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("LiDAR Camera · \(report.deviceModel) · iOS \(report.systemVersion)")
                .font(.mono(9, weight: .medium))
                .foregroundStyle(AppTheme.muted.opacity(0.55))
            Text("Hardware checked \(report.checkedAt.formatted(date: .omitted, time: .shortened))")
                .font(.mono(8.5))
                .foregroundStyle(AppTheme.muted.opacity(0.35))
        }
        .padding(.top, 2)
    }
}

// MARK: - Mode row

private struct ModeRow: View {
    let mode: ScanMode

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(mode.accent.opacity(0.10))
                    .frame(width: 54, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(mode.accent.opacity(0.20), lineWidth: 1)
                    }

                Image(systemName: mode.icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(mode.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(mode.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    CapsuleTag(text: mode == .depthMap ? "2D" : "3D", color: mode.accent.opacity(0.85))
                }
                Text(mode.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.04)))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.surface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [mode.accent.opacity(0.035), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

// MARK: - Empty state

private struct EmptyLibraryCard: View {
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(AppTheme.hairline)
                        .frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your depth library is empty")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    Text("Capture a depth map to begin.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .foregroundStyle(AppTheme.hairline)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
