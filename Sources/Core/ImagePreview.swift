import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Decodes raster images into a bounded PNG thumbnail.
///
/// SpaceLens never claims image UTIs at the top level — macOS keeps previewing PNG/JPEG itself.
/// This path exists so that an image *inside* a folder or archive can be shown in the
/// container's detail pane. Decoding stays local and is limited on three axes (file size,
/// declared pixel dimensions, encoded thumbnail size) to keep a decompression bomb from
/// exhausting memory before the thumbnail is produced.
enum ImagePreview {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "heic", "heif"
    ]
    private static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumPixelDimension = 10_000
    private static let maximumPixelCount: Int64 = 20_000_000
    private static let thumbnailMaximumPixel = 2048
    private static let maximumThumbnailBytes = 8 * 1024 * 1024

    static func load(_ url: URL) throws -> PreviewSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard Int64(size) <= Int64(maximumFileBytes) else {
            throw PreviewFailure.unsupportedData(
                "图片超过 \(formatBytes(Int64(maximumFileBytes))) 的安全读取上限。")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try load(data: data, name: url.lastPathComponent)
    }

    /// Rejects absurd declared dimensions before any pixel buffer is allocated. Kept separate from
    /// decoding so the guard itself is directly testable.
    static func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw PreviewFailure.damagedData("无法读取图片尺寸。")
        }
        guard width <= maximumPixelDimension, height <= maximumPixelDimension else {
            throw PreviewFailure.unsupportedData(
                "图片尺寸 \(width)×\(height) 超过安全上限（最长边 \(maximumPixelDimension) px、共 \(maximumPixelCount / 1_000_000) 百万像素）。")
        }
        // Check each dimension before multiplying so hostile metadata cannot overflow Int64.
        let pixels = Int64(width) * Int64(height)
        guard pixels <= maximumPixelCount else {
            throw PreviewFailure.unsupportedData(
                "图片尺寸 \(width)×\(height) 超过安全上限（最长边 \(maximumPixelDimension) px、共 \(maximumPixelCount / 1_000_000) 百万像素）。")
        }
    }

    static func load(data: Data, name: String) throws -> PreviewSnapshot {
        try Task.checkCancellation()
        guard data.count <= maximumFileBytes else {
            throw PreviewFailure.unsupportedData(
                "图片超过 \(formatBytes(Int64(maximumFileBytes))) 的安全读取上限。")
        }
        // Header-only inspection: reading the declared size is cheap and lets an oversized
        // image be rejected before any pixel buffer is allocated.
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw PreviewFailure.damagedData("图片无法解码。")
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw PreviewFailure.damagedData("图片没有任何图像帧。") }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw PreviewFailure.damagedData("无法读取图片尺寸。")
        }
        try validate(width: width, height: height)
        try Task.checkCancellation()

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PreviewFailure.damagedData("图片缩略图无法生成。")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw PreviewFailure.damagedData("图片无法重新编码。")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PreviewFailure.damagedData("图片无法重新编码。")
        }
        let png = output as Data
        guard png.count <= maximumThumbnailBytes else {
            throw PreviewFailure.unsupportedData(
                "图片缩略图超过 \(formatBytes(Int64(maximumThumbnailBytes))) 的显示上限。")
        }
        let frameNote = frameCount > 1 ? " · \(frameCount) 帧（显示第 1 帧）" : ""
        return PreviewSnapshot(title: name,
            summary: "SpaceLens · 图片 · \(width)×\(height) · 缩略图 \(thumbnail.width)×\(thumbnail.height)\(frameNote)",
            body: "", truncated: false, contentKind: .image, imagePNGData: png)
    }
}
