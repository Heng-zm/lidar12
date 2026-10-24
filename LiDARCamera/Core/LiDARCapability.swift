import ARKit
import Darwin
import Foundation

/// The result of the hardware check that runs before the depth camera is shown.
///
/// These ARKit queries are static feature checks. They do not create an
/// `ARSession`, do not open the camera, and do not ask for any permission.
struct LiDARCapabilityReport: Equatable {
    let isSupported: Bool
    let hasWorldTracking: Bool
    let hasSceneDepth: Bool
    let hasSmoothedDepth: Bool
    let isSimulator: Bool
    let deviceModel: String
    let machineIdentifier: String
    let systemVersion: String
    let checkedAt: Date

    static func current() -> LiDARCapabilityReport {
        let worldTracking = ARWorldTrackingConfiguration.isSupported
        let sceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let smoothedDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)

        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif

        return LiDARCapabilityReport(
            isSupported: worldTracking && sceneDepth && !simulator,
            hasWorldTracking: worldTracking,
            hasSceneDepth: sceneDepth,
            hasSmoothedDepth: smoothedDepth,
            isSimulator: simulator,
            deviceModel: Self.deviceModel,
            machineIdentifier: Self.machineIdentifier,
            systemVersion: Self.systemVersion,
            checkedAt: Date()
        )
    }

    var deviceDescription: String {
        "\(deviceModel) · iOS \(systemVersion)"
    }

    var hardwareDescription: String {
        machineIdentifier.isEmpty ? deviceDescription : "\(deviceDescription) · \(machineIdentifier)"
    }

    var unsupportedTitle: String {
        if isSimulator {
            return "The Simulator can't see depth"
        }
        if !hasWorldTracking {
            return "ARKit isn't available here"
        }
        return "This iPhone has no LiDAR scanner"
    }

    var unsupportedMessage: String {
        if isSimulator {
            return "The iOS Simulator has no LiDAR hardware. Run this app on a physical iPhone Pro model to open the depth camera."
        }
        if !hasWorldTracking {
            return "This device does not support ARKit world tracking, which is required to turn LiDAR measurements into a stable depth view."
        }
        if !hasSceneDepth {
            return "iOS reports no scene-depth support on this device. LiDAR Camera will not fall back to the regular RGB camera, so the home screen stays locked."
        }
        return "The depth camera is unavailable."
    }

    private static var deviceModel: String {
        #if targetEnvironment(simulator)
        return "iPhone Simulator"
        #else
        return "iPhone"
        #endif
    }

    private static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion == 0 {
            return "\(version.majorVersion).\(version.minorVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}

enum SupportedDevices {
    static let summary = "LiDAR Camera requires an iPhone with a LiDAR scanner"

    static let iphones = [
        "iPhone 12 Pro / Pro Max",
        "iPhone 13 Pro / Pro Max",
        "iPhone 14 Pro / Pro Max",
        "iPhone 15 Pro / Pro Max",
        "iPhone 16 Pro / Pro Max",
        "iPhone 17 Pro / Pro Max",
    ]

    static let footnote = "Every newer iPhone Pro model is supported. Standard iPhone models do not have a LiDAR scanner."
}
