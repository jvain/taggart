import CryptoKit
import Foundation

/// All tags of one file: the raw property map plus embedded artwork.
///
/// `fields` keeps every key TagLib reports, so tags the app has no UI for
/// (MusicBrainz IDs, ReplayGain, …) survive an edit untouched.
public struct TagSnapshot: Sendable, Equatable {
    public var fields: [String: [String]]
    public var artwork: [Artwork]

    public init(fields: [String: [String]] = [:], artwork: [Artwork] = []) {
        self.fields = fields
        self.artwork = artwork
    }
}

/// ID3v2 / FLAC picture type.
public struct PictureType: RawRepresentable, Sendable, Hashable {
    public var rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let other = PictureType(rawValue: 0)
    public static let frontCover = PictureType(rawValue: 3)
    public static let backCover = PictureType(rawValue: 4)

    private static let names = [
        "Other", "File Icon", "Other File Icon", "Front Cover", "Back Cover", "Leaflet Page", "Media",
        "Lead Artist", "Artist", "Conductor", "Band", "Composer", "Lyricist", "Recording Location",
        "During Recording", "During Performance", "Movie Screen Capture", "Colored Fish", "Illustration",
        "Band Logo", "Publisher Logo",
    ]

    public var name: String {
        Self.names.indices.contains(rawValue) ? Self.names[rawValue] : "Other"
    }
}

/// An embedded picture. To keep memory bounded when thousands of files are
/// loaded, pictures read from a file don't keep their bytes: they're re-read
/// from the file when it's saved or the picture is exported.
public struct Artwork: Sendable, Identifiable {
    public enum Source: Sendable {
        /// The picture at this index in the file as it was loaded.
        case embedded(index: Int)
        /// A picture added in this session.
        case new(Data)
    }

    public var type: PictureType
    public var mimeType: String
    public var description: String
    public var digest: SHA256.Digest
    public var byteCount: Int
    public var width: Int
    public var height: Int
    public var colorDepth: Int
    public var source: Source

    public var id: SHA256.Digest { digest }

    public init(type: PictureType, mimeType: String, description: String = "", digest: SHA256.Digest,
                byteCount: Int, width: Int, height: Int, colorDepth: Int, source: Source) {
        self.type = type
        self.mimeType = mimeType
        self.description = description
        self.digest = digest
        self.byteCount = byteCount
        self.width = width
        self.height = height
        self.colorDepth = colorDepth
        self.source = source
    }
}

extension Artwork: Equatable {
    /// Compares content, not where the bytes come from, so setting the cover a
    /// file already has doesn't mark it as modified.
    public static func == (lhs: Artwork, rhs: Artwork) -> Bool {
        lhs.type == rhs.type && lhs.mimeType == rhs.mimeType && lhs.description == rhs.description
            && lhs.digest == rhs.digest
    }
}

extension TagSnapshot {
    /// The picture to show for this file: the first front cover, else the first picture.
    public var primaryArtwork: Artwork? {
        artwork.first { $0.type == .frontCover } ?? artwork.first
    }
}
