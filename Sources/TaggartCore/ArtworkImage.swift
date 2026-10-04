import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image helpers: turning image bytes into `Artwork`, and making thumbnails.
public enum ArtworkImage {
    /// Makes a new picture from image bytes. JPEG and PNG are embedded as is;
    /// other formats ImageIO can read (HEIC, TIFF, WebP, …) are converted to
    /// JPEG, since players widely support only those two. With `maxPixelSize`,
    /// an image wider or taller than that is scaled down to fit, as a JPEG.
    public static func artwork(from data: Data, type: PictureType = .frontCover, maxPixelSize: Int? = nil) throws -> Artwork {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw TagIOError.unsupportedImage
        }
        var bytes = data
        var mimeType = mimeType(of: data)
        let original = metrics(of: data)
        if let maxPixelSize, max(original.width, original.height) > maxPixelSize {
            guard let jpeg = shrunkJPEG(from: source, maxPixelSize: maxPixelSize) else {
                throw TagIOError.unsupportedImage
            }
            bytes = jpeg
            mimeType = "image/jpeg"
        } else if mimeType == nil {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let jpeg = jpegData(from: image)
            else {
                throw TagIOError.unsupportedImage
            }
            bytes = jpeg
            mimeType = "image/jpeg"
        }
        let metrics = metrics(of: bytes)
        return Artwork(
            type: type,
            mimeType: mimeType!,
            digest: SHA256.hash(data: bytes),
            byteCount: bytes.count,
            width: metrics.width,
            height: metrics.height,
            colorDepth: metrics.colorDepth,
            source: .new(bytes)
        )
    }

    public static func artwork(contentsOf url: URL, type: PictureType = .frontCover, maxPixelSize: Int? = nil) throws -> Artwork {
        try artwork(from: Data(contentsOf: url), type: type, maxPixelSize: maxPixelSize)
    }

    /// Downloads an image, e.g. one dragged from a web browser as a link. For a
    /// plain http:// address the secure https:// one is tried first.
    @concurrent
    public static func download(from url: URL, maxPixelSize: Int? = nil) async throws -> Artwork {
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let secure = components.url,
               let artwork = try? await fetch(secure, timeout: 10, maxPixelSize: maxPixelSize) {
                return artwork
            }
        }
        return try await fetch(url, timeout: 30, maxPixelSize: maxPixelSize)
    }

    private static func fetch(_ url: URL, timeout: TimeInterval, maxPixelSize: Int?) async throws -> Artwork {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: timeout))
        } catch {
            throw TagIOError.cannotDownload(url, reason: error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw TagIOError.imageNotFound(url)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TagIOError.cannotDownload(url, reason: "The server answered with error \(http.statusCode).")
        }
        guard data.count <= maxDownloadSize else {
            throw TagIOError.cannotDownload(url, reason: "The image is larger than 50 MB.")
        }
        do {
            return try artwork(from: data, maxPixelSize: maxPixelSize)
        } catch {
            throw TagIOError.cannotDownload(url, reason: "It isn't an image Taggart can read.")
        }
    }

    static let maxDownloadSize = 50 * 1024 * 1024

    /// "image/jpeg" or "image/png" if the bytes are one of those, else nil.
    public static func mimeType(of data: Data) -> String? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "image/png"
        }
        return nil
    }

    public static func fileExtension(forMimeType mimeType: String) -> String {
        UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "jpg"
    }

    /// A downscaled image for display, or nil if the bytes aren't a readable image.
    public static func thumbnail(of data: Data, maxPixelSize: Int = 512) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func metrics(of data: Data) -> (width: Int, height: Int, colorDepth: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (0, 0, 0)
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let bitsPerComponent = properties[kCGImagePropertyDepth] as? Int ?? 8
        let model = properties[kCGImagePropertyColorModel] as? String
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let components = (model == (kCGImagePropertyColorModelGray as String) ? 1 : 3) + (hasAlpha ? 1 : 0)
        return (width, height, bitsPerComponent * components)
    }

    /// The image scaled down so neither side exceeds `maxPixelSize`, as JPEG.
    /// ImageIO's thumbnail path downsamples with good quality and applies any
    /// EXIF orientation, so the result is upright.
    private static func shrunkJPEG(from source: CGImageSource, maxPixelSize: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(from: image)
    }

    /// JPEG has no transparency: an image with an alpha channel is drawn onto
    /// white first (otherwise transparent areas would turn black).
    static func opaque(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            return image
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    private static func jpegData(from image: CGImage) -> Data? {
        let image = opaque(image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Small thumbnails keyed by picture digest, shared across files: an album's
/// twelve identical covers cost one thumbnail. Kept small (128 px, ~64 KB) so
/// thousands of covers fit in memory; larger previews are made on demand.
/// Safe to use from any thread.
public final class ThumbnailCache: @unchecked Sendable {
    static let maxPixelSize = 128
    private let lock = NSLock()
    private var images: [SHA256.Digest: CGImage] = [:]

    public init() {}

    public subscript(digest: SHA256.Digest) -> CGImage? {
        lock.withLock { images[digest] }
    }

    func insert(_ image: CGImage, for digest: SHA256.Digest) {
        lock.withLock { images[digest] = image }
    }

    /// Makes and caches a thumbnail unless one already exists.
    @discardableResult
    public func add(_ data: Data, digest: SHA256.Digest) -> CGImage? {
        if let existing = self[digest] {
            return existing
        }
        guard let image = ArtworkImage.thumbnail(of: data, maxPixelSize: Self.maxPixelSize) else { return nil }
        insert(image, for: digest)
        return image
    }
}
