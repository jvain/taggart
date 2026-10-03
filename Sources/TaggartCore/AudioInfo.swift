import Foundation
import TagBridge

public enum AudioFormat: String, Sendable, Hashable {
    case mp3 = "MP3"
    case flac = "FLAC"
    case other = "Other"
}

/// Technical properties of an audio file, for display.
public struct AudioInfo: Sendable, Hashable {
    public var format: AudioFormat
    public var duration: TimeInterval
    public var bitrateKbps: Int
    public var sampleRate: Int
    public var channels: Int
    /// 0 when the format has no fixed sample depth (MP3).
    public var bitsPerSample: Int
    /// Major version of the ID3v2 tag on disk (2, 3 or 4), or 0 if there is none.
    public var id3v2Version: Int
    public var hasID3v1: Bool
    public var isReadOnly: Bool

    public init(format: AudioFormat, duration: TimeInterval = 0, bitrateKbps: Int = 0, sampleRate: Int = 0,
                channels: Int = 0, bitsPerSample: Int = 0, id3v2Version: Int = 0, hasID3v1: Bool = false,
                isReadOnly: Bool = false) {
        self.format = format
        self.duration = duration
        self.bitrateKbps = bitrateKbps
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.id3v2Version = id3v2Version
        self.hasID3v1 = hasID3v1
        self.isReadOnly = isReadOnly
    }

    init(_ info: tb_info) {
        let format: AudioFormat = switch info.format {
        case TB_FORMAT_MPEG: .mp3
        case TB_FORMAT_FLAC: .flac
        default: .other
        }
        self.init(
            format: format,
            duration: TimeInterval(info.length_ms) / 1000,
            bitrateKbps: Int(info.bitrate_kbps),
            sampleRate: Int(info.sample_rate),
            channels: Int(info.channels),
            bitsPerSample: Int(info.bits_per_sample),
            id3v2Version: Int(info.id3v2_version),
            hasID3v1: info.has_id3v1,
            isReadOnly: info.read_only
        )
    }

    /// e.g. "FLAC 16-bit 44.1 kHz" or "MP3 320 kbps".
    public var summary: String {
        let kHz = (Double(sampleRate) / 1000).formatted(.number.precision(.fractionLength(0...1)))
        switch format {
        case .flac:
            return bitsPerSample > 0 ? "FLAC \(bitsPerSample)-bit \(kHz) kHz" : "FLAC \(kHz) kHz"
        case .mp3:
            return "MP3 \(bitrateKbps) kbps"
        case .other:
            return format.rawValue
        }
    }
}

/// Which ID3v2 version to write MP3 tags as.
public enum ID3v2WriteVersion: Int, Sendable, CaseIterable, Identifiable {
    /// Keep the file's current version; new tags are written as ID3v2.4.
    case keep = 0
    case v2_3 = 3
    case v2_4 = 4

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .keep: "Keep existing (new tags: ID3v2.4)"
        case .v2_3: "ID3v2.3"
        case .v2_4: "ID3v2.4"
        }
    }
}

public enum TagIOError: LocalizedError, Equatable {
    case cannotOpen(URL, reason: String)
    case cannotWrite(URL, reason: String)
    case modifiedOnDisk(URL)
    case artworkUnavailable(URL)
    case unsupportedImage

    public var errorDescription: String? {
        switch self {
        case let .cannotOpen(url, reason):
            "Couldn't open “\(url.lastPathComponent)”. \(reason)"
        case let .cannotWrite(url, reason):
            "Couldn't save “\(url.lastPathComponent)”. \(reason)"
        case let .modifiedOnDisk(url):
            "“\(url.lastPathComponent)” was changed by another app since it was loaded. Revert it to reload, then edit again."
        case let .artworkUnavailable(url):
            "The existing artwork in “\(url.lastPathComponent)” could not be read back while saving."
        case .unsupportedImage:
            "The image format isn't supported."
        }
    }
}
