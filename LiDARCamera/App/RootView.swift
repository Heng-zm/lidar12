import SwiftUI

/// The support gate for the whole app.
///
/// The static ARKit capability check runs before anything else can appear.
/// `HomeView` is only built when the check proves that LiDAR scene depth is
/// available, so unsupported phones and the Simulator never reach the depth UI.
struct RootView: View {
    private enum Phase: Equatable {
        case checking
        case unsupported
        case home
    }

    @StateObject private var library = CaptureLibrary()
    @State private var phase: Phase = .checking
    @State private var report: LiDARCapabilityReport?
    @State private var isChecking = false

    var body: some View {
        ZStack {
            AppBackground()

            switch phase {
            case .checking:
                LiDARCheckView()
                    .transition(.opacity)
                    .zIndex(0)

            case .unsupported:
                if let report {
                    UnsupportedDeviceView(report: report) {
                        Task { await runCapabilityCheck() }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                    .zIndex(1)
                }

            case .home:
                if let report {
                    HomeView(report: report) {
                        Task { await runCapabilityCheck() }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
        .environmentObject(library)
        .task {
            guard report == nil else { return }
            await runCapabilityCheck()
        }
    }

    @MainActor
    private func runCapabilityCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        report = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .checking
        }

        // A short beat makes the check legible instead of flashing on screen.
        try? await Task.sleep(nanoseconds: 1_350_000_000)

        let result = LiDARCapabilityReport.current()
        report = result

        withAnimation(.easeInOut(duration: 0.42)) {
            phase = result.isSupported ? .home : .unsupported
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
