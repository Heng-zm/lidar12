import Combine
import Foundation
import simd
import UIKit

// MARK: - Snapshot from the sensor

struct DepthSnapshot {
    let id: UUID
    let createdAt: Date
    let width: Int
    let height: Int
    let depths: [Float]
    let imageWidth: Int
    let imageHeight: Int
    let intrinsics: simd_float3x3
    let cameraTransform: simd_float4x4
    /// Normalized viewport -> normalized depth image, six CGAffineTransform values.
    let displayInverse: [Float]
    let mode: ScanMode
    let palette: DepthPalette
    let minDepth: Float
    let maxDepth: Float
    let meanDepth: Float
}

// MARK: - Stored capture

struct CaptureRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let folderName: String
    let mode: ScanMode
    let palette: DepthPalette
    let minDepth: Float
    let maxDepth: Float
    let meanDepth: Float
    let pointCount: Int
    let depthWidth: Int
    let depthHeight: Int
    let imageWidth: Int
    let imageHeight: Int

    var pointCountLabel: String {
        pointCount >= 1000 ? "\(pointCount / 1000)k" : "\(pointCount)"
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDepthFrame
    case imageEncodingFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .noDepthFrame:
            return "No LiDAR depth frame is available yet. Hold still for a moment and try again."
        case .imageEncodingFailed:
            return "The depth visualization could not be encoded."
        case .fileWriteFailed:
            return "The capture could not be written to disk."
        }
    }
}

// MARK: - Library

@MainActor
final class CaptureLibrary: ObservableObject {
    @Published private(set) var captures: [CaptureRecord] = []

    nonisolated let rootURL: URL

    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let fullImageCache = NSCache<NSString, UIImage>()

    private static let metadataName = "capture.json"
    private static let thumbnailName = "thumb.jpg"
    private static let depthImageName = "depth.png"
    private static let pointCloudName = "cloud.ply"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("Captures", isDirectory: true)

        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        reload()
    }

    func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [CaptureRecord] = []
        for folder in urls {
            let metadataURL = folder.appendingPathComponent(Self.metadataName)
            guard FileManager.default.fileExists(atPath: metadataURL.path),
                  let data = try? Data(contentsOf: metadataURL),
                  let record = try? decoder.decode(CaptureRecord.self, from: data) else {
                continue
            }
            loaded.append(record)
        }

        captures = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    func save(snapshot: DepthSnapshot) async throws -> CaptureRecord {
        let root = rootURL
        let record = try await Task.detached(priority: .userInitiated) {
            try CaptureWriter.write(snapshot: snapshot, rootURL: root)
        }.value

        captures.insert(record, at: 0)
        return record
    }

    func delete(_ record: CaptureRecord) {
        try? FileManager.default.removeItem(at: folderURL(for: record))
        captures.removeAll { $0.id == record.id }
        thumbnailCache.removeObject(forKey: cacheKey(record, kind: "thumb") as NSString)
        fullImageCache.removeObject(forKey: cacheKey(record, kind: "full") as NSString)
    }

    func folderURL(for record: CaptureRecord) -> URL {
        rootURL.appendingPathComponent(record.folderName, isDirectory: true)
    }

    func depthImageURL(for record: CaptureRecord) -> URL {
        folderURL(for: record).appendingPathComponent(Self.depthImageName)
    }

    func pointCloudURL(for record: CaptureRecord) -> URL {
        folderURL(for: record).appendingPathComponent(Self.pointCloudName)
    }

    func shareItems(for record: CaptureRecord) -> [URL] {
        var items: [URL] = []
        let png = depthImageURL(for: record)
        let ply = pointCloudURL(for: record)
        if FileManager.default.fileExists(atPath: png.path) { items.append(png) }
        if FileManager.default.fileExists(atPath: ply.path) { items.append(ply) }
        return items
    }

    func thumbnail(for record: CaptureRecord) -> UIImage? {
        let key = cacheKey(record, kind: "thumb")
        if let cached = thumbnailCache.object(forKey: key as NSString) {
            return cached
        }

        let folder = folderURL(for: record)
        let thumbURL = folder.appendingPathComponent(Self.thumbnailName)
        if let image = UIImage(contentsOfFile: thumbURL.path) {
            thumbnailCache.setObject(image, forKey: key as NSString)
            return image
        }

        if let image = fullImage(for: record) {
            thumbnailCache.setObject(image, forKey: key as NSString)
            return image
        }
        return nil
    }

    func fullImage(for record: CaptureRecord) -> UIImage? {
        let key = cacheKey(record, kind: "full")
        if let cached = fullImageCache.object(forKey: key as NSString) {
            return cached
        }

        let url = depthImageURL(for: record)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        fullImageCache.setObject(image, forKey: key as NSString)
        return image
    }

    private func cacheKey(_ record: CaptureRecord, kind: String) -> String {
        "\(kind)-\(record.id.uuidString)"
    }
}

// MARK: - Writer

private enum CaptureWriter {
    static func write(snapshot: DepthSnapshot, rootURL: URL) throws -> CaptureRecord {
        let folderName = "\(snapshot.id.uuidString.prefix(8))-\(Int(snapshot.createdAt.timeIntervalSince1970))"
        let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw CaptureError.fileWriteFailed
        }

        do {
            let depthURL = folder.appendingPathComponent("depth.f32")
            try rawDepthData(snapshot.depths).write(to: depthURL, options: .atomic)

            guard let image = DepthImageRenderer.makeImage(
                snapshot: snapshot,
                width: 540,
                height: 960
            ), let png = image.pngData() else {
                throw CaptureError.imageEncodingFailed
            }

            try png.write(
                to: folder.appendingPathComponent("depth.png"),
                options: .atomic
            )

            let thumb = DepthImageRenderer.makeImage(
                snapshot: snapshot,
                width: 270,
                height: 480
            )

            if let thumb,
               let jpeg = thumb.jpegData(compressionQuality: 0.82) {
                try jpeg.write(
                    to: folder.appendingPathComponent("thumb.jpg"),
                    options: .atomic
                )
            }

            let pointCount = try writePointCloud(
                snapshot: snapshot,
                to: folder.appendingPathComponent("cloud.ply")
            )

            let record = CaptureRecord(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                folderName: folderName,
                mode: snapshot.mode,
                palette: snapshot.palette,
                minDepth: snapshot.minDepth,
                maxDepth: snapshot.maxDepth,
                meanDepth: snapshot.meanDepth,
                pointCount: pointCount,
                depthWidth: snapshot.width,
                depthHeight: snapshot.height,
                imageWidth: snapshot.imageWidth,
                imageHeight: snapshot.imageHeight
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let metadata = try encoder.encode(record)
            try metadata.write(
                to: folder.appendingPathComponent("capture.json"),
                options: .atomic
            )

            return record
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if let captureError = error as? CaptureError {
                throw captureError
            }
            throw CaptureError.fileWriteFailed
        }
    }

    private static func rawDepthData(_ depths: [Float]) -> Data {
        depths.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private static func writePointCloud(snapshot: DepthSnapshot, to url: URL) throws -> Int {
        let width = snapshot.width
        let height = snapshot.height
        guard width > 0, height > 0 else { throw CaptureError.fileWriteFailed }

        let fx = snapshot.intrinsics.columns.0.x
        let fy = snapshot.intrinsics.columns.1.y
        let cx = snapshot.intrinsics.columns.2.x
        let cy = snapshot.intrinsics.columns.2.y

        func isValid(_ depth: Float) -> Bool {
            depth.isFinite && depth > 0.01 && depth < 10.0
        }

        var count = 0
        for depth in snapshot.depths where isValid(depth) {
            count += 1
        }

        guard count > 0 else { throw CaptureError.noDepthFrame }

        var output = """
        ply
        format ascii 1.0
        comment LiDAR Camera depth-only point cloud
        element vertex \(count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """
        output.reserveCapacity(count * 44)

        let depthW = Float(width)
        let depthH = Float(height)
        let imageW = Float(snapshot.imageWidth)
        let imageH = Float(snapshot.imageHeight)

        for y in 0..<height {
            let v = (Float(y) + 0.5) / depthH
            let imageY = v * imageH

            for x in 0..<width {
                let depth = snapshot.depths[y * width + x]
                guard isValid(depth) else { continue }

                let u = (Float(x) + 0.5) / depthW
                let imageX = u * imageW

                let cameraX = (imageX - cx) / fx * depth
                let cameraY = (cy - imageY) / fy * depth
                let cameraPoint = SIMD4<Float>(cameraX, cameraY, -depth, 1)
                let world = snapshot.cameraTransform * cameraPoint

                let rgb = snapshot.palette.color(at: DepthVisualization.normalized(depth))
                let r = UInt8(min(max(Int(rgb.x * 255), 0), 255))
                let g = UInt8(min(max(Int(rgb.y * 255), 0), 255))
                let b = UInt8(min(max(Int(rgb.z * 255), 0), 255))

                output += String(
                    format: "%.4f %.4f %.4f %d %d %d\n",
                    world.x, world.y, world.z, Int(r),
                    Int(g), Int(b)
                )
            }
        }

        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CaptureError.fileWriteFailed
        }
        return count
    }
}

// MARK: - Depth image

enum DepthImageRenderer {
    static func makeImage(snapshot: DepthSnapshot, width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0,
              snapshot.width > 0, snapshot.height > 0,
              snapshot.depths.count >= snapshot.width * snapshot.height,
              snapshot.displayInverse.count == 6 else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let inverse = snapshot.displayInverse
        let backgroundColor: (UInt8, UInt8, UInt8) = (5, 7, 10)

        for y in 0..<height {
            let v = (Float(y) + 0.5) / Float(height)

            for x in 0..<width {
                let index = (y * width + x) * 4
                let u = (Float(x) + 0.5) / Float(width)

                let imageU = inverse[0] * u + inverse[2] * v + inverse[4]
                let imageV = inverse[1] * u + inverse[3] * v + inverse[5]

                if imageU < 0 || imageU > 1 || imageV < 0 || imageV > 1 {
                    bytes[index] = backgroundColor.0
                    bytes[index + 1] = backgroundColor.1
                    bytes[index + 2] = backgroundColor.2
                    bytes[index + 3] = 255
                    continue
                }

                let px = min(max(Int(imageU * Float(snapshot.width)), 0), snapshot.width - 1)
                let py = min(max(Int(imageV * Float(snapshot.height)), 0), snapshot.height - 1)
                let depth = snapshot.depths[py * snapshot.width + px]

                guard depth.isFinite, depth > 0.01 else {
                    bytes[index] = backgroundColor.0
                    bytes[index + 1] = backgroundColor.1
                    bytes[index + 2] = backgroundColor.2
                    bytes[index + 3] = 255
                    continue
                }

                let rgb = snapshot.palette.color(at: DepthVisualization.normalized(depth))
                bytes[index] = UInt8(min(max(Int(rgb.x * 255), 0), 255))
                bytes[index + 1] = UInt8(min(max(Int(rgb.y * 255), 0), 255))
                bytes[index + 2] = UInt8(min(max(Int(rgb.z * 255), 0), 255))
                bytes[index + 3] = 255
            }
        }

        var image: UIImage?
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgImage = context.makeImage() else {
                return
            }
            image = UIImage(cgImage: cgImage)
        }

        return image
    }
}
