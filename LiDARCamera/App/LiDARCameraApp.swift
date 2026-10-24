import SwiftUI

@main
struct LiDARCameraApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(AppTheme.accent)
        }
    }
}
