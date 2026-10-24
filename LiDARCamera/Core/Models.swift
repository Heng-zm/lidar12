import SwiftUI
import UIKit
import simd

// MARK: - Scan mode

enum ScanMode: String, CaseIterable, Codable, Identifiable, Hashable {
    case depthMap
    case pointCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .depthMap: return "Depth map"
        case .pointCloud: return "Point cloud"
        }
    }

    var shortTitle: String {
        switch self {
        case .depthMap: return "DEPTH"
        case .pointCloud: return "POINTS"
        }
    }

    var subtitle: String {
        switch self {
        case .depthMap: return "Distance as color, live."
        case .pointCloud: return "Your room as 3D points."
        }
    }

    var detail: String {
        switch self {
        case .depthMap:
            return "A heat-colored distance field. Near surfaces glow warm, far surfaces cool. No image detail ever appears."
        case .pointCloud:
            return "Every depth pixel becomes a point in space. Move to scan the room, drag to look around."
        }
    }

    var icon: String {
        switch self {
        case .depthMap: return "circle.hexagongrid.fill"
        case .pointCloud: return "cube.transparent"
        }
    }

    var accent: Color {
        switch self {
        case .depthMap: return AppTheme.accent
        case .pointCloud: return AppTheme.violet
        }
    }
}

// MARK: - Palettes

struct PaletteStop {
    let location: Float
    let color: SIMD3<Float>
}

enum DepthPalette: String, CaseIterable, Codable, Identifiable, Hashable {
    case thermal
    case viridis
    case ocean
    case mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thermal: return "Heat"
        case .viridis: return "Field"
        case .ocean: return "Ocean"
        case .mono: return "Mono"
        }
    }

    var stops: [PaletteStop] {
        switch self {
        case .thermal:
            return [
                PaletteStop(location: 0.00, color: SIMD3(0.018, 0.024, 0.075)),
                PaletteStop(location: 0.24, color: SIMD3(0.155, 0.075, 0.310)),
                PaletteStop(location: 0.48, color: SIMD3(0.620, 0.115, 0.400)),
                PaletteStop(location: 0.68, color: SIMD3(0.965, 0.310, 0.180)),
                PaletteStop(location: 0.84, color: SIMD3(1.000, 0.690, 0.285)),
                PaletteStop(location: 1.00, color: SIMD3(1.000, 0.975, 0.890)),
            ]
        case .viridis:
            return [
                PaletteStop(location: 0.00, color: SIMD3(0.030, 0.070, 0.120)),
                PaletteStop(location: 0.25, color: SIMD3(0.055, 0.290, 0.330)),
                PaletteStop(location: 0.50, color: SIMD3(0.100, 0.540, 0.420)),
                PaletteStop(location: 0.72, color: SIMD3(0.470, 0.770, 0.300)),
                PaletteStop(location: 0.88, color: SIMD3(0.800, 0.880, 0.350)),
                PaletteStop(location: 1.00, color: SIMD3(0.960, 0.950, 0.620)),
            ]
        case .ocean:
            return [
                PaletteStop(location: 0.00, color: SIMD3(0.005, 0.025, 0.075)),
                PaletteStop(location: 0.30, color: SIMD3(0.020, 0.190, 0.350)),
                PaletteStop(location: 0.55, color: SIMD3(0.030, 0.500, 0.620)),
                PaletteStop(location: 0.76, color: SIMD3(0.270, 0.880, 0.820)),
                PaletteStop(location: 1.00, color: SIMD3(0.870, 1.000, 0.985)),
            ]
        case .mono:
            return [
                PaletteStop(location: 0.00, color: SIMD3(0.025, 0.035, 0.050)),
                PaletteStop(location: 0.35, color: SIMD3(0.250, 0.290, 0.340)),
                PaletteStop(location: 0.68, color: SIMD3(0.600, 0.660, 0.700)),
                PaletteStop(location: 1.00, color: SIMD3(0.965, 0.985, 1.000)),
            ]
        }
    }

    func color(at value: Float) -> SIMD3<Float> {
        let t = min(max(value, 0), 1)
        let stops = stops

        guard let upper = stops.firstIndex(where: { $0.location >= t }) else {
            return stops[stops.count - 1].color
        }
        if upper == 0 { return stops[0].color }

        let a = stops[upper - 1]
        let b = stops[upper]
        let span = max(b.location - a.location, 0.0001)
        let local = (t - a.location) / span
        return a.color + (b.color - a.color) * local
    }

    func uiColor(at value: Float) -> UIColor {
        let c = color(at: value)
        return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }

    /// Pre-sampled colors for the CPU capture path, where thousands of
    /// pixels are colored in a tight loop.
    var rgbTable: [SIMD3<Float>] {
        (0..<256).map { index in
            color(at: Float(index) / 255.0)
        }
    }

    var previewColors: [Color] {
        [0.0, 0.32, 0.60, 0.82, 1.0].map { value in
            let c = color(at: Float(value))
            return Color(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z))
        }
    }
}

// MARK: - Visualization range

enum DepthVisualization {
    static let near: Float = 0.2
    static let far: Float = 5.0

    static func normalized(_ depth: Float) -> Float {
        min(max((depth - near) / (far - near), 0), 1)
    }
}

// MARK: - Small formatting helpers

enum Format {
    static func meters(_ value: Float) -> String {
        String(format: "%.2f m", value)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide).day().hour().minute())
    }
}
