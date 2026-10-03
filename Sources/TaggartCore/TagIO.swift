import CryptoKit
import Darwin
import Foundation

/// A file's tags and properties as read from disk.
public struct LoadedFile: Sendable {
    public var url: URL
    public var info: AudioInfo
    public var snapshot: TagSnapshot
    /// Used to detect changes made by other apps before saving.
    public var modificationDate: Date?
}

/// Reads and writes tags. All functions are synchronous and do file I/O: call
/// them off the main thread.
public enum TagIO {
    public static func read(_ url: URL, thumbnails: ThumbnailCache? = nil) throws -> LoadedFile {
        let modificationDate = modificationDate(of: url)
        let file = try TagLibFile(url: url)
        let artwork = file.pictures.enumerated().map { index, picture in
            let digest = SHA256.hash(data: picture.data)
            thumbnails?.add(picture.data, digest: digest)
            // ID3v2 doesn't store dimensions; read them from the image header.
            let metrics = picture.width > 0
                ? (width: picture.width, height: picture.height, colorDepth: picture.colorDepth)
                : ArtworkImage.metrics(of: picture.data)
            return Artwork(
                type: PictureType(rawValue: picture.type),
                mimeType: picture.mimeType,
                description: picture.description,
                digest: digest,
                byteCount: picture.data.count,
                width: metrics.width,
                height: metrics.height,
                colorDepth: metrics.colorDepth,
                source: .embedded(index: index)
            )
        }
        return LoadedFile(
            url: url,
            info: file.info,
            snapshot: TagSnapshot(fields: file.properties, artwork: artwork),
            modificationDate: modificationDate
        )
    }

    /// The image bytes of a picture, re-reading them from the file if needed.
    public static func data(of artwork: Artwork, in url: URL) throws -> Data {
        switch artwork.source {
        case let .new(data):
            return data
        case let .embedded(index):
            let pictures = try TagLibFile(url: url).pictures
            guard pictures.indices.contains(index), SHA256.hash(data: pictures[index].data) == artwork.digest else {
                throw TagIOError.artworkUnavailable(url)
            }
            return pictures[index].data
        }
    }

    /// Writes `edited` to the file if it differs from `original`.
    ///
    /// The tags are written to a clone of the file (instant on APFS), which then
    /// replaces the original, so a failure part-way can't damage the original.
    public static func write(
        _ edited: TagSnapshot,
        original: TagSnapshot,
        to url: URL,
        expectedModificationDate: Date?,
        id3v2Version: ID3v2WriteVersion = .keep
    ) throws {
        let fieldsChanged = edited.fields != original.fields
        let artworkChanged = edited.artwork != original.artwork
        guard fieldsChanged || artworkChanged else { return }

        if let expectedModificationDate, modificationDate(of: url) != expectedModificationDate {
            throw TagIOError.modifiedOnDisk(url)
        }

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).taggart-\(UUID().uuidString)")
        try clone(url, to: temporaryURL)
        var replaced = false
        defer {
            if !replaced {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        try applyTags(
            edited,
            fields: fieldsChanged,
            artwork: artworkChanged,
            to: temporaryURL,
            originalURL: url,
            id3v2Version: id3v2Version
        )
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        replaced = true
    }

    /// Separate function so the TagLib handle is closed before the file is moved.
    private static func applyTags(
        _ snapshot: TagSnapshot,
        fields: Bool,
        artwork: Bool,
        to url: URL,
        originalURL: URL,
        id3v2Version: ID3v2WriteVersion
    ) throws {
        let file = try TagLibFile(url: url, displayURL: originalURL)
        if fields {
            let rejected = file.setProperties(snapshot.fields)
            if !rejected.isEmpty {
                let keys = rejected.keys.sorted().joined(separator: ", ")
                throw TagIOError.cannotWrite(originalURL, reason: "This file type can't store these tags: \(keys).")
            }
        }
        if artwork {
            let needsExisting = snapshot.artwork.contains {
                if case .embedded = $0.source { true } else { false }
            }
            let existing = needsExisting ? file.pictures : []
            let pictures = try snapshot.artwork.map { artwork in
                let data: Data
                switch artwork.source {
                case let .new(bytes):
                    data = bytes
                case let .embedded(index):
                    guard existing.indices.contains(index),
                          SHA256.hash(data: existing[index].data) == artwork.digest
                    else {
                        throw TagIOError.artworkUnavailable(originalURL)
                    }
                    data = existing[index].data
                }
                return RawPicture(
                    data: data,
                    mimeType: artwork.mimeType,
                    description: artwork.description,
                    type: artwork.type.rawValue,
                    width: artwork.width,
                    height: artwork.height,
                    colorDepth: artwork.colorDepth
                )
            }
            try file.setPictures(pictures)
        }
        try file.save(id3v2Version: id3v2Version)
    }

    private static func clone(_ source: URL, to destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                copyfile(sourcePath, destinationPath, nil, copyfile_flags_t(COPYFILE_CLONE))
            }
        }
        if result != 0 {
            throw TagIOError.cannotWrite(source, reason: String(cString: strerror(errno)))
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        // Bypass URL's resource value cache: it would return a stale date.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}
