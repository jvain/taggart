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

struct NoAudioFound: Error {}

/// SHA-256 of the audio payload: the bytes outside the tags.
func audioDigest(of url: URL) throws -> SHA256.Digest {
    let data = try Data(contentsOf: url)
    let bytes = [UInt8](data)
    if bytes.starts(with: Array("OggS".utf8)) {
        return try oggAudioDigest(bytes)
    }
    if bytes.count >= 8, bytes[4..<8].elementsEqual(Array("ftyp".utf8)) {
        return try mp4AudioDigest(bytes)
    }
    if bytes.count >= 12, ["RIFF", "FORM"].contains(where: { bytes[0..<4].elementsEqual(Array($0.utf8)) }) {
        return try riffAudioDigest(bytes)
    }
    if bytes.starts(with: asfHeaderGUID) {
        return try asfAudioDigest(bytes)
    }
    if bytes.starts(with: Array("wvpk".utf8)) || bytes.starts(with: Array("MAC ".utf8)) {
        // WavPack and Monkey's Audio: the audio, then APE and ID3v1 tags.
        var end = bytes.count
        if end >= 128, bytes[(end - 128)..<(end - 125)].elementsEqual(Array("TAG".utf8)) {
            end -= 128
        }
        if end >= 32, bytes[(end - 32)..<(end - 24)].elementsEqual(Array("APETAGEX".utf8)) {
            func littleEndian(_ offset: Int) -> Int {
                bytes[offset..<(offset + 4)].reversed().reduce(0) { $0 << 8 | Int($1) }
            }
            // The size covers the items and the footer; a header may precede them.
            let size = littleEndian(end - 32 + 12)
            let hasHeader = littleEndian(end - 32 + 20) & (1 << 31) != 0
            end -= size + (hasHeader ? 32 : 0)
        }
        return SHA256.hash(data: Data(bytes[0..<end]))
    }
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

/// Ogg: the payload of the audio pages. Saving tags may re-paginate the header
/// packets and renumber later pages (changing their headers), but never their
/// payload. Header pages are those with granule position 0.
private func oggAudioDigest(_ bytes: [UInt8]) throws -> SHA256.Digest {
    var audio = Data()
    var position = 0
    while position + 27 <= bytes.count, bytes[position..<(position + 4)].elementsEqual(Array("OggS".utf8)) {
        // Little-endian 64-bit granule position at offset 6.
        let granule = bytes[(position + 6)..<(position + 14)].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let segmentCount = Int(bytes[position + 26])
        let bodyStart = position + 27 + segmentCount
        let bodyLength = bytes[(position + 27)..<bodyStart].reduce(0) { $0 + Int($1) }
        if granule != 0 {
            audio.append(contentsOf: bytes[bodyStart..<(bodyStart + bodyLength)])
        }
        position = bodyStart + bodyLength
    }
    guard !audio.isEmpty else { throw NoAudioFound() }
    return SHA256.hash(data: audio)
}

/// MP4: the contents of the top-level mdat boxes, which hold the audio.
private func mp4AudioDigest(_ bytes: [UInt8]) throws -> SHA256.Digest {
    func bigEndian(_ range: Range<Int>) -> Int {
        bytes[range].reduce(0) { $0 << 8 | Int($1) }
    }
    var audio = Data()
    var position = 0
    while position + 8 <= bytes.count {
        var size = bigEndian(position..<(position + 4))
        var headerLength = 8
        if size == 1 {
            size = bigEndian((position + 8)..<(position + 16))
            headerLength = 16
        } else if size == 0 {
            size = bytes.count - position
        }
        guard size >= headerLength else { break }
        if bytes[(position + 4)..<(position + 8)].elementsEqual(Array("mdat".utf8)) {
            audio.append(contentsOf: bytes[(position + headerLength)..<(position + size)])
        }
        position += size
    }
    guard !audio.isEmpty else { throw NoAudioFound() }
    return SHA256.hash(data: audio)
}

/// WAV and AIFF: the contents of the audio chunk ("data" or "SSND").
private func riffAudioDigest(_ bytes: [UInt8]) throws -> SHA256.Digest {
    let bigEndian = bytes.starts(with: Array("FORM".utf8))
    let audioChunk = Array((bigEndian ? "SSND" : "data").utf8)
    var position = 12
    while position + 8 <= bytes.count {
        let sizeBytes = bytes[(position + 4)..<(position + 8)]
        let size = (bigEndian ? Array(sizeBytes) : sizeBytes.reversed()).reduce(0) { $0 << 8 | Int($1) }
        let start = position + 8
        if bytes[position..<(position + 4)].elementsEqual(audioChunk) {
            return SHA256.hash(data: Data(bytes[start..<min(start + size, bytes.count)]))
        }
        // Chunks are padded to an even size.
        position = start + size + (size & 1)
    }
    throw NoAudioFound()
}

private let asfHeaderGUID: [UInt8] = [
    0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C,
]
private let asfDataGUID: [UInt8] = [
    0x36, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C,
]

/// WMA (ASF): the data object, which holds the audio packets. The tags live in
/// the header object before it.
private func asfAudioDigest(_ bytes: [UInt8]) throws -> SHA256.Digest {
    var position = 0
    while position + 24 <= bytes.count {
        let size = bytes[(position + 16)..<(position + 24)].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard size >= 24 else { break }
        if bytes[position..<(position + 16)].elementsEqual(asfDataGUID) {
            return SHA256.hash(data: Data(bytes[position..<min(position + size, bytes.count)]))
        }
        position += size
    }
    throw NoAudioFound()
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
