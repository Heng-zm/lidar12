import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var recordToDelete: CaptureRecord?
    @State private var activeRecord: CaptureRecord?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                if library.captures.isEmpty {
                    emptyState
                } else {
                    summaryRow

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(library.captures) { record in
                            Button {
                                Haptics.light()
                                activeRecord = record
                            } label: {
                                CaptureGridTile(record: record)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    recordToDelete = record
                                } label: {
                                    Label("Delete capture", systemImage: "trash")
                                }
                            }
                        }
                    }

                    privacyFooter
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $activeRecord) { record in
            CaptureDetailView(record: record)
                .environmentObject(library)
        }
        .alert("Delete this capture?", isPresented: Binding(
            get: { recordToDelete != nil },
            set: { if !$0 { recordToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let recordToDelete {
                    library.delete(recordToDelete)
                    Haptics.success()
                }
                recordToDelete = nil
            }
            Button("Keep", role: .cancel) {
                recordToDelete = nil
            }
        } message: {
            Text("The depth image, raw depth data, and point cloud will be permanently removed from this iPhone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle(size: 40))

            VStack(alignment: .leading, spacing: 2) {
                Text("Depth library")
                    .font(.display(24, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text("\(library.captures.count) capture\(library.captures.count == 1 ? "" : "s") · on device")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            CapsuleTag(text: "LIDAR ONLY", icon: "sensor.tag.radiowaves.forward", color: AppTheme.accent)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryCell(
                icon: "cube.transparent",
                value: totalPointsLabel,
                label: "TOTAL POINTS",
                color: AppTheme.violet
            )
            summaryCell(
                icon: "arrow.left.and.right",
                value: closestLabel,
                label: "CLOSEST",
                color: AppTheme.accent
            )
        }
    }

    private func summaryCell(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(color.opacity(0.09)))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.mono(13, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text(label)
                    .font(.mono(7.5, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppTheme.hairline, lineWidth: 1)
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                    .foregroundStyle(AppTheme.hairline)
                    .frame(width: 150, height: 150)
                Circle()
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
                    .frame(width: 100, height: 100)
                Image(systemName: "cube.transparent")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Nothing measured yet")
                    .font(.display(23, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text("Depth captures you save will appear here as color-mapped images with a 3D point cloud file.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }

            NavigationLink(value: HomeView.HomeRoute.scan(.depthMap)) {
                HStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                    Text("Start a scan")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text("Depth files stay in the app container. Nothing is uploaded.")
                .font(.system(size: 10.5))
        }
        .foregroundStyle(AppTheme.muted.opacity(0.65))
        .padding(.top, 8)
    }

    private var totalPointsLabel: String {
        let total = library.captures.reduce(0) { $0 + $1.pointCount }
        if total >= 1_000_000 {
            return String(format: "%.1fM", Double(total) / 1_000_000)
        }
        return "\(total / 1000)k"
    }

    private var closestLabel: String {
        guard let closest = library.captures.map(\.minDepth).min() else { return "--" }
        return String(format: "%.2f m", closest)
    }
}

// MARK: - Grid tile

struct CaptureGridTile: View {
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
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: record.mode.icon)
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 224)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.86)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    CapsuleTag(
                        text: record.mode.shortTitle,
                        color: record.mode.accent
                    )
                    Spacer(minLength: 0)
                }

                Text(Format.meters(record.meanDepth))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(12)
        }
        .frame(height: 224)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

// MARK: - Detail

struct CaptureDetailView: View {
    let record: CaptureRecord

    @EnvironmentObject private var library: CaptureLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                imageCard
                primaryStats
                detailsCard
                exportCard
                deleteButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showShare) {
            ActivityView(items: library.shareItems(for: record))
                .presentationDetents([.medium, .large])
        }
        .alert("Delete this capture?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                library.delete(record)
                Haptics.success()
                dismiss()
            }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("This removes the depth image and point cloud from this iPhone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle(size: 40))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.mode.title)
                    .font(.display(22, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Button {
                Haptics.light()
                showShare = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(IconButtonStyle(size: 40))
            .disabled(library.shareItems(for: record).isEmpty)
        }
    }

    private var imageCard: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = library.fullImage(for: record) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                Text("Depth image unavailable")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(AppTheme.muted)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }

            HStack(spacing: 7) {
                CapsuleTag(text: "LIDAR DEPTH", icon: "sensor.tag.radiowaves.forward", color: AppTheme.accent)
                CapsuleTag(text: record.palette.title.uppercased(), color: .white.opacity(0.7))
            }
            .padding(14)
        }
    }

    private var primaryStats: some View {
        HStack(spacing: 10) {
            statBox("NEAREST", Format.meters(record.minDepth), AppTheme.accent)
            statBox("AVERAGE", Format.meters(record.meanDepth), AppTheme.cyan)
            statBox("FARTHEST", Format.meters(record.maxDepth), AppTheme.violet)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            SectionLabel(text: "Capture data")
                .padding(.bottom, 10)

            detailRow("Mode", value: record.mode.title)
            Divider().overlay(AppTheme.hairline)
            detailRow("Points", value: "\(record.pointCount.formatted())")
            Divider().overlay(AppTheme.hairline)
            detailRow("Depth grid", value: "\(record.depthWidth) × \(record.depthHeight)")
            Divider().overlay(AppTheme.hairline)
            detailRow("Projection grid", value: "\(record.imageWidth) × \(record.imageHeight)")
            Divider().overlay(AppTheme.hairline)
            detailRow("Palette", value: record.palette.title)
            Divider().overlay(AppTheme.hairline)
            detailRow("RGB feed", value: "Not captured", valueColor: AppTheme.accent)
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Export")

            Text("Share the colorized depth image and an ASCII PLY point cloud in meters. Raw Float32 depth is also stored inside the app container.")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                formatPill("depth.png", icon: "photo")
                formatPill("cloud.ply", icon: "cube")
                formatPill("depth.f32", icon: "waveform.path")
            }

            Button {
                Haptics.light()
                showShare = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share capture")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(library.shareItems(for: record).isEmpty)
        }
        .padding(18)
        .glassCard(cornerRadius: 22)
    }

    private var deleteButton: some View {
        Button {
            Haptics.light()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "trash")
                Text("Delete capture")
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(AppTheme.danger.opacity(0.85))
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func statBox(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.mono(7.5, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.mono(13, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(color.opacity(0.065))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(color.opacity(0.14), lineWidth: 1)
                }
        }
    }

    private func detailRow(_ title: String, value: String, valueColor: Color = AppTheme.text) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(valueColor.opacity(0.9))
        }
        .padding(.vertical, 12)
    }

    private func formatPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(.mono(8.5, weight: .medium))
        }
        .foregroundStyle(AppTheme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.hairline, lineWidth: 1)
                }
        }
    }
}

// MARK: - Share sheet

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
