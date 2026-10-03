import Foundation
import TagBridge

/// A picture exactly as TagLib stores it, including the image bytes.
struct RawPicture {
    var data: Data
    var mimeType: String
    var description: String
    var type: Int
    var width = 0
    var height = 0
    var colorDepth = 0
    var numColors = 0
}

/// Owns a TagBridge handle for the lifetime of one read or write. Not thread-safe:
/// use each instance from a single task, and don't keep it around.
final class TagLibFile {
    private let handle: OpaquePointer
    /// The file errors are reported against (the original when editing a temporary copy).
    private let displayURL: URL

    init(url: URL, displayURL: URL? = nil) throws {
        let displayURL = displayURL ?? url
        var message = ""
        let handle = url.withUnsafeFileSystemRepresentation { path in
            withErrorBuffer(&message) { tb_open(path, $0, $1) }
        }
        guard let handle else {
            throw TagIOError.cannotOpen(displayURL, reason: message)
        }
        self.handle = handle
        self.displayURL = displayURL
    }

    deinit {
        tb_close(handle)
    }

    var info: AudioInfo {
        AudioInfo(tb_get_info(handle))
    }

    var properties: [String: [String]] {
        let list = tb_get_properties(handle)
        defer { tb_property_list_free(list) }
        return Self.dictionary(from: list)
    }

    /// Replaces all properties. Returns the entries the format could not store.
    @discardableResult
    func setProperties(_ fields: [String: [String]]) -> [String: [String]] {
        var items: [tb_property] = []
        defer {
            for item in items {
                free(item.key)
                for index in 0..<item.value_count {
                    free(item.values[index])
                }
                item.values.deallocate()
            }
        }
        for (key, values) in fields {
            let cValues = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: max(values.count, 1))
            for (index, value) in values.enumerated() {
                cValues[index] = strdup(value)
            }
            items.append(tb_property(key: strdup(key), values: cValues, value_count: values.count))
        }
        let rejected = items.withUnsafeBufferPointer { tb_set_properties(handle, $0.baseAddress, $0.count) }
        defer { tb_property_list_free(rejected) }
        return Self.dictionary(from: rejected)
    }

    var pictures: [RawPicture] {
        let list = tb_get_pictures(handle)
        defer { tb_picture_list_free(list) }
        guard list.count > 0, let items = list.items else { return [] }
        return (0..<list.count).map { index in
            let picture = items[index]
            return RawPicture(
                data: Data(bytes: picture.data, count: picture.size),
                mimeType: String(cString: picture.mime_type),
                description: String(cString: picture.description),
                type: Int(picture.picture_type),
                width: Int(picture.width),
                height: Int(picture.height),
                colorDepth: Int(picture.color_depth),
                numColors: Int(picture.num_colors)
            )
        }
    }

    func setPictures(_ pictures: [RawPicture]) throws {
        var items: [tb_picture] = []
        defer {
            for item in items {
                item.data.deallocate()
                free(item.mime_type)
                free(item.description)
            }
        }
        for picture in pictures {
            let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: max(picture.data.count, 1))
            picture.data.copyBytes(to: bytes, count: picture.data.count)
            items.append(tb_picture(
                data: bytes,
                size: picture.data.count,
                mime_type: strdup(picture.mimeType),
                description: strdup(picture.description),
                picture_type: Int32(picture.type),
                width: Int32(picture.width),
                height: Int32(picture.height),
                color_depth: Int32(picture.colorDepth),
                num_colors: Int32(picture.numColors)
            ))
        }
        let ok = items.withUnsafeBufferPointer { tb_set_pictures(handle, $0.baseAddress, $0.count) }
        if !ok {
            throw TagIOError.cannotWrite(displayURL, reason: "The pictures could not be stored in this file.")
        }
    }

    func save(id3v2Version: ID3v2WriteVersion) throws {
        var message = ""
        let ok = withErrorBuffer(&message) {
            tb_save(handle, tb_id3v2_version(rawValue: UInt32(id3v2Version.rawValue)), $0, $1)
        }
        if !ok {
            throw TagIOError.cannotWrite(displayURL, reason: message)
        }
    }

    private static func dictionary(from list: tb_property_list) -> [String: [String]] {
        guard list.count > 0, let items = list.items else { return [:] }
        var result: [String: [String]] = [:]
        for index in 0..<list.count {
            let property = items[index]
            let values = (0..<property.value_count).compactMap { property.values[$0].map { String(cString: $0) } }
            result[String(cString: property.key)] = values
        }
        return result
    }
}

private func withErrorBuffer<T>(_ message: inout String, _ body: (UnsafeMutablePointer<CChar>, Int) -> T) -> T {
    var buffer = [CChar](repeating: 0, count: 512)
    return buffer.withUnsafeMutableBufferPointer { pointer in
        let result = body(pointer.baseAddress!, pointer.count)
        message = String(cString: pointer.baseAddress!)
        return result
    }
}
