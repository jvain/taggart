import Foundation

/// One tag as TagLib names it for every format (e.g. "MUSICBRAINZ_TRACKID"),
/// across the selected files.
public struct RawTag: Identifiable, Equatable, Sendable {
    public var key: String
    public var state: RawTagState
    public var id: String { key }
}

public enum RawTagState: Equatable, Sendable {
    /// Every selected file has exactly these values.
    case uniform([String])
    /// The files differ; `count` of them have the tag at all.
    case mixed(count: Int)
}

/// Tag names for the All Tags view.
public enum RawTagKey {
    /// The uppercased name, and why it can't be used (or nil if it can).
    /// Names are limited to what every format can store: Vorbis comments
    /// (FLAC, Ogg) allow only printable ASCII other than "=".
    public static func validate(_ text: String) -> (key: String, error: String?) {
        let key = text.trimmingCharacters(in: .whitespaces).uppercased()
        if key.isEmpty {
            return (key, "Enter a tag name.")
        }
        let allowed = key.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7D && $0 != "=" }
        if !allowed {
            return (key, "Tag names can contain only English letters, digits, spaces and punctuation other than “=”.")
        }
        return (key, nil)
    }

    /// Commonly used tag names that TagLib maps to each format's own fields.
    public static let common = [
        "ALBUMSORT", "ALBUMARTISTSORT", "ARTISTS", "ARTISTSORT", "BPM", "CATALOGNUMBER", "COMPILATION",
        "CONDUCTOR", "COPYRIGHT", "DISCSUBTITLE", "ENCODEDBY", "GROUPING", "ISRC", "LABEL", "LANGUAGE",
        "LYRICIST", "LYRICS", "MEDIA", "MOOD", "MUSICBRAINZ_ALBUMARTISTID", "MUSICBRAINZ_ALBUMID",
        "MUSICBRAINZ_ARTISTID", "MUSICBRAINZ_RELEASEGROUPID", "MUSICBRAINZ_RELEASETRACKID",
        "MUSICBRAINZ_TRACKID", "MUSICBRAINZ_WORKID", "ORIGINALDATE", "PERFORMER", "PRODUCER",
        "RELEASECOUNTRY", "RELEASESTATUS", "RELEASETYPE", "REMIXER", "REPLAYGAIN_ALBUM_GAIN",
        "REPLAYGAIN_ALBUM_PEAK", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK", "SUBTITLE", "TITLESORT",
    ]

    /// Common names starting with (then containing) the typed text, leaving
    /// out names already present.
    public static func suggestions(for text: String, excluding present: Set<String>, limit: Int = 10) -> [String] {
        let typed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !typed.isEmpty else { return [] }
        let candidates = common.filter { !present.contains($0) && $0 != typed }
        let starting = candidates.filter { $0.hasPrefix(typed) }
        let containing = candidates.filter { !$0.hasPrefix(typed) && $0.contains(typed) }
        return Array((starting + containing).prefix(limit))
    }
}
