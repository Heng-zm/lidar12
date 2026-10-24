import Foundation
import SwiftUI
import UIKit

struct InfoSheet: View {
    let report: LiDARCapabilityReport
    let onRecheck: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    sensorSection
                    privacySection
                    permissionSection
                    devicesSection
                    recheckButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How it works")
                    .font(.display(30, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text("Depth, with a deliberate blind spot for pixels.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(IconButtonStyle(size: 38))
        }
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Sensor report")

            VStack(spacing: 0) {
                infoRow("Device", value: report.deviceModel)
                Divider().overlay(AppTheme.hairline)
                infoRow("iOS", value: report.systemVersion)
                Divider().overlay(AppTheme.hairline)
                infoRow("Scene depth", value: report.hasSceneDepth ? "Available" : "Missing", positive: report.hasSceneDepth)
                Divider().overlay(AppTheme.hairline)
                infoRow("Smoothed depth", value: report.hasSmoothedDepth ? "Available" : "Missing", positive: report.hasSmoothedDepth)
                Divider().overlay(AppTheme.hairline)
                infoRow("World tracking", value: report.hasWorldTracking ? "Available" : "Missing", positive: report.hasWorldTracking)
            }
            .padding(.horizontal, 16)
            .glassCard(cornerRadius: 20)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Privacy by design")

            VStack(alignment: .leading, spacing: 18) {
                privacyRow(
                    icon: "video.slash.fill",
                    title: "No RGB feed",
                    body: "The color camera stream is never read for display, never recorded, and never saved. You will not see a normal camera preview anywhere in this app."
                )
                privacyRow(
                    icon: "externaldrive.fill",
                    title: "On-device only",
                    body: "Captures stay inside the app's Documents folder. Export a depth image or .ply point cloud only when you choose to share."
                )
                privacyRow(
                    icon: "sensor.tag.radiowaves.forward.fill",
                    title: "Distance, not identity",
                    body: "A depth map contains geometry in meters. Faces and textures are not part of the data the app keeps."
                )
            }
            .padding(18)
            .glassCard(cornerRadius: 22)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "A note on permission")

            Text("iOS powers the LiDAR scanner through ARKit, and ARKit requires camera permission — even when an app only requests depth frames. LiDAR Camera never displays, records, or stores the image feed. Denying camera access also disables the LiDAR sensor.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(18)
                .glassCard(cornerRadius: 20)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Supported hardware")

            VStack(alignment: .leading, spacing: 12) {
                Text(SupportedDevices.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.text.opacity(0.86))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                WrapTags(items: SupportedDevices.iphones, color: AppTheme.cyan)
            }
            .padding(18)
            .glassCard(cornerRadius: 20)
        }
    }

    private var recheckButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onRecheck()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                Text("Run hardware check again")
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .frame(maxWidth: .infinity)

        .padding(.top, 4)
    }

    private func infoRow(_ title: String, value: String, positive: Bool? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(AppTheme.muted)
            Spacer()
            HStack(spacing: 6) {
                if let positive {
                    Circle()
                        .fill(positive ? AppTheme.accent : AppTheme.danger)
                        .frame(width: 5, height: 5)
                }
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(positive == false ? AppTheme.danger : AppTheme.text.opacity(0.9))
            }
        }
        .padding(.vertical, 13)
    }

    private func privacyRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppTheme.accent.opacity(0.09)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text(body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Recent capture tile

struct RecentCaptureTile: View {
    let record: CaptureRecord
    @EnvironmentObject private var library: CaptureLibrary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = library.thumbnail(for: record) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [AppTheme.raised, AppTheme.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay {
                        Image(systemName: record.mode.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .frame(width: 142, height: 176)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(record.mode.shortTitle)
                    .font(.mono(8, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(record.mode.accent)
                Text(Format.meters(record.meanDepth))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
        }
        .frame(width: 142, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            CapsuleTag(text: "\(record.pointCount / 1000)k PTS", color: .white.opacity(0.75))
                .padding(9)
        }
    }
}
