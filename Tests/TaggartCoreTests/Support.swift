import CryptoKit
import Foundation
import Testing
@testable import TaggartCore

/// Copies a fixture into a fresh temporary directory and returns its URL.
func fixture(_ name: String) throws -> URL {
    let source = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TaggartTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(name)
    try FileManager.default.copyItem(at: source, to: destination)
    return destination
}

func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Reads a file, applies `change` to its tags, saves, and reads it back.
@discardableResult
func edit(
    _ url: URL,
    id3v2Version: ID3v2WriteVersion = .keep,
    _ change: (inout TagSnapshot, AudioFormat) throws -> Void
) throws -> LoadedFile {
    let loaded = try TagIO.read(url)
    var snapshot = loaded.snapshot
    try change(&snapshot, loaded.info.format)
    try TagIO.write(
        snapshot,
        original: loaded.snapshot,
        to: url,
        expectedModificationDate: loaded.modificationDate,
        id3v2Version: id3v2Version
    )
    return try TagIO.read(url)
}

/// SHA-256 of the audio payload: the bytes outside the tags.
func audioDigest(of url: URL) throws -> SHA256.Digest {
    let data = try Data(contentsOf: url)
    let bytes = [UInt8](data)
    var start = 0
    var end = bytes.count
    if bytes.starts(with: Array("fLaC".utf8)) {
        // Skip metadata blocks: 1 byte (last flag + type), 3 bytes length.
        start = 4
        while true {
            let isLast = bytes[start] & 0x80 != 0
            let length = Int(bytes[start + 1]) << 16 | Int(bytes[start + 2]) << 8 | Int(bytes[start + 3])
            start += 4 + length
            if isLast { break }
        }
    } else {
        if bytes.starts(with: Array("ID3".utf8)) {
            // Synchsafe size, plus a 10-byte header and an optional footer.
            let size = bytes[6..<10].reduce(0) { $0 << 7 | Int($1 & 0x7F) }
            let hasFooter = bytes[5] & 0x10 != 0
            start = 10 + size + (hasFooter ? 10 : 0)
        }
        if end >= 128, bytes[(end - 128)..<(end - 125)].elementsEqual(Array("TAG".utf8)) {
            end -= 128
        }
        // TagLib may add or drop padding after the ID3v2 tag: skip to the first frame sync.
        while start + 1 < end, !(bytes[start] == 0xFF && bytes[start + 1] & 0xE0 == 0xE0) {
            start += 1
        }
    }
    return SHA256.hash(data: Data(bytes[start..<end]))
}

/// Major ID3v2 version in the file header, or nil if there's no ID3v2 tag.
func id3v2MajorVersion(of url: URL) throws -> UInt8? {
    let header = try Data(contentsOf: url).prefix(4)
    return header.starts(with: Array("ID3".utf8)) ? header[header.startIndex + 3] : nil
}

func hasID3v1(_ url: URL) throws -> Bool {
    let data = try Data(contentsOf: url)
    return data.count >= 128 && data.suffix(128).starts(with: Array("TAG".utf8))
}

func newArtwork(_ name: String = "blue.jpg") throws -> Artwork {
    try ArtworkImage.artwork(from: fixtureData(name))
}
