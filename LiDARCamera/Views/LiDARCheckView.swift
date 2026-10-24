import SwiftUI

struct LiDARCheckView: View {
    @State private var rotate = false
    @State private var breathe = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            scanner
                .frame(width: 230, height: 230)

            VStack(spacing: 14) {
                Text("LIDAR CAMERA")
                    .font(.mono(11, weight: .semibold))
                    .tracking(4.0)
                    .foregroundStyle(AppTheme.muted)

                Text("Checking this iPhone")
                    .font(.display(30, weight: .bold))
                    .foregroundStyle(AppTheme.text)

                Text("Looking for a LiDAR depth sensor.\nNo camera is opened during this check.")
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 36)

            Spacer()

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accent)
                Text("HARDWARE CHECK")
                    .font(.mono(9.5, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.bottom, 42)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotate = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    private var scanner: some View {
        ZStack {
            Circle()
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
                .padding(18)

            Circle()
                .strokeBorder(AppTheme.hairline.opacity(0.6), lineWidth: 1)
                .padding(52)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.clear, AppTheme.accent.opacity(0.0), AppTheme.accent, .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .padding(26)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .shadow(color: AppTheme.accent.opacity(0.45), radius: 8)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.clear, AppTheme.cyan.opacity(0.7), .clear],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
                .padding(5)
                .rotationEffect(.degrees(rotate ? -360 : 0))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppTheme.accent.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 95
                    )
                )
                .scaleEffect(breathe ? 1.08 : 0.9)

            ZStack {
                Circle()
                    .fill(AppTheme.raised)
                    .frame(width: 74, height: 74)
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.cyan],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            scanSweep
                .clipShape(Circle().inset(by: 18))
        }
    }

    private var scanSweep: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, AppTheme.accent.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 60)
                .offset(y: breathe ? proxy.size.height - 60 : 0)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: breathe)
        }
        .allowsHitTesting(false)
    }
}
