import CoreVideo
import Metal

/// Describes how an ARKit depth map is stored in memory.
///
/// LiDAR scene-depth buffers are normally `kCVPixelFormatType_DepthFloat16`,
/// but ARKit can also hand back 32-bit depth. Every reader (Metal upload,
/// metrics, capture) goes through this type so the byte layout can never be
/// guessed incorrectly.
enum DepthSampleFormat {
    case float16
    case float32

    init?(pixelBuffer: CVPixelBuffer) {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_DepthFloat16:
            self = .float16
        case kCVPixelFormatType_DepthFloat32:
            self = .float32
        default:
            return nil
        }
    }

    var metalPixelFormat: MTLPixelFormat {
        switch self {
        case .float16: return .r16Float
        case .float32: return .r32Float
        }
    }

    /// Reads one depth sample from a locked pixel buffer.
    func value(
        atX x: Int,
        y: Int,
        baseAddress: UnsafeRawPointer,
        bytesPerRow: Int
    ) -> Float {
        let row = baseAddress.advanced(by: y * bytesPerRow)

        switch self {
        case .float16:
            return Float(row.assumingMemoryBound(to: Float16.self)[x])
        case .float32:
            return row.assumingMemoryBound(to: Float.self)[x]
        }
    }

    /// Copies a locked pixel buffer into a row-major `Float` array.
    func copyDepths(
        from baseAddress: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> [Float] {
        var depths = [Float](repeating: .nan, count: width * height)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)

            switch self {
            case .float16:
                let samples = row.assumingMemoryBound(to: Float16.self)
                for x in 0..<width {
                    depths[y * width + x] = Float(samples[x])
                }
            case .float32:
                let samples = row.assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    depths[y * width + x] = samples[x]
                }
            }
        }

        return depths
    }
}
