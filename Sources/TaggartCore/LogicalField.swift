import Foundation

/// The fields shown in the editor, mapped onto TagLib's raw property keys.
public enum LogicalField: String, CaseIterable, Sendable, Identifiable {
    case title
    case artist
    case album
    case albumArtist
    case trackNumber
    case trackTotal
    case discNumber
    case discTotal
    case date
    case genre
    case composer
    case comment

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .albumArtist: "Album Artist"
        case .trackNumber: "Track"
        case .trackTotal: "Track Total"
        case .discNumber: "Disc"
        case .discTotal: "Disc Total"
        case .date: "Year"
        case .genre: "Genre"
        case .composer: "Composer"
        case .comment: "Comment"
        }
    }

    /// Fields whose display joins multiple values with "; " and whose edits are
    /// split back into multiple values on ";".
    public var allowsMultipleValues: Bool {
        switch self {
        case .artist, .albumArtist, .genre, .composer: true
        default: false
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .trackNumber, .trackTotal, .discNumber, .discTotal: true
        default: false
        }
    }

    /// What typing `text` into this field may produce: number fields keep only
    /// the digits 0–9, and Track and Disc also one "/" ("3/12" sets the total
    /// too). Other fields accept anything.
    public func allowedInput(_ text: String) -> String {
        guard isNumeric else { return text }
        let allowsSlash = self == .trackNumber || self == .discNumber
        var sawSlash = false
        return String(text.filter { character in
            if ("0"..."9").contains(character) {
                return true
            }
            if character == "/" && allowsSlash && !sawSlash {
                sawSlash = true
                return true
            }
            return false
        })
    }

    var simpleKey: String? {
        switch self {
        case .title: "TITLE"
        case .artist: "ARTIST"
        case .album: "ALBUM"
        case .albumArtist: "ALBUMARTIST"
        case .date: "DATE"
        case .genre: "GENRE"
        case .composer: "COMPOSER"
        case .comment: "COMMENT"
        case .trackNumber, .trackTotal, .discNumber, .discTotal: nil
        }
    }

    var numberKeys: NumberKeys? {
        switch self {
        case .trackNumber, .trackTotal: .track
        case .discNumber, .discTotal: .disc
        default: nil
        }
    }
}

/// Raw keys of a "n/total" pair. ID3v2 stores both in one frame (TRCK = "3/12");
/// Vorbis comments use separate fields, with two common spellings for the total.
struct NumberKeys {
    var number: String
    var totals: [String]

    static let track = NumberKeys(number: "TRACKNUMBER", totals: ["TRACKTOTAL", "TOTALTRACKS"])
    static let disc = NumberKeys(number: "DISCNUMBER", totals: ["DISCTOTAL", "TOTALDISCS"])
}

/// What a field looks like across several selected files.
public enum FieldState: Equatable, Sendable {
    /// Every file has this value ("" when every file lacks the field).
    case uniform(String)
    /// Files disagree.
    case mixed

    public init(_ values: some Sequence<String>) {
        var result: String?
        for value in values {
            if let result, result != value {
                self = .mixed
                return
            }
            result = value
        }
        self = .uniform(result ?? "")
    }
}

extension TagSnapshot {
    /// The display value of a field.
    public func value(of field: LogicalField) -> String {
        if let key = field.simpleKey {
            return (fields[key] ?? []).joined(separator: "; ")
        }
        let keys = field.numberKeys!
        let (number, embeddedTotal) = Self.splitNumber(first(keys.number))
        switch field {
        case .trackNumber, .discNumber:
            return number
        default:
            if !embeddedTotal.isEmpty {
                return embeddedTotal
            }
            return keys.totals.lazy.map { first($0) }.first { !$0.isEmpty } ?? ""
        }
    }

    /// Sets a field. An empty value removes it.
    public mutating func set(_ field: LogicalField, to rawValue: String, format: AudioFormat) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if field == .trackNumber || field == .discNumber, value.contains("/") {
            // "3/12" sets the number and the total; "3/" just the number.
            let (number, total) = Self.splitNumber(value)
            set(field, to: number, format: format)
            if !total.isEmpty {
                set(field == .trackNumber ? .trackTotal : .discTotal, to: total, format: format)
            }
            return
        }
        if let key = field.simpleKey {
            let values = field.allowsMultipleValues
                ? value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : (value.isEmpty ? [] : [value])
            fields[key] = values.isEmpty ? nil : values
            return
        }

        let keys = field.numberKeys!
        let number: String
        let total: String
        switch field {
        case .trackNumber, .discNumber:
            number = value
            total = self.value(of: field == .trackNumber ? .trackTotal : .discTotal)
        default:
            number = self.value(of: field == .trackTotal ? .trackNumber : .discNumber)
            total = value
        }
        let editedTotal = field == .trackTotal || field == .discTotal

        if format.storesTotalWithNumber {
            // One tag holds both. Fold any separate total (e.g. a TXXX frame) into it.
            if number.isEmpty {
                fields[keys.number] = nil
                setTotal(total, keys: keys)
            } else {
                fields[keys.number] = [total.isEmpty ? number : "\(number)/\(total)"]
                setTotal("", keys: keys)
            }
        } else {
            // Only touch the total fields when the total was edited or used to be
            // embedded in the number field ("3/12"), to avoid renaming keys needlessly.
            let hadEmbeddedTotal = !Self.splitNumber(first(keys.number)).total.isEmpty
            fields[keys.number] = number.isEmpty ? nil : [number]
            if editedTotal || hadEmbeddedTotal {
                setTotal(total, keys: keys)
            }
        }
    }

    public func applying(_ edit: TagEdit, format: AudioFormat) -> TagSnapshot {
        var copy = self
        switch edit {
        case let .setField(field, value):
            copy.set(field, to: value, format: format)
        case let .setFrontCover(artwork):
            // Many taggers store the cover as type "Other", so replace those too.
            copy.artwork.removeAll { $0.type == .frontCover || $0.type == .other }
            var cover = artwork
            cover.type = .frontCover
            copy.artwork.insert(cover, at: 0)
        case .removeArtwork:
            copy.artwork = []
        }
        return copy
    }

    private func first(_ key: String) -> String {
        fields[key]?.first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    private mutating func setTotal(_ total: String, keys: NumberKeys) {
        for key in keys.totals {
            fields[key] = nil
        }
        if !total.isEmpty {
            fields[keys.totals[0]] = [total]
        }
    }

    static func splitNumber(_ raw: String) -> (number: String, total: String) {
        guard let slash = raw.firstIndex(of: "/") else {
            return (raw, "")
        }
        return (
            raw[..<slash].trimmingCharacters(in: .whitespaces),
            raw[raw.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        )
    }
}

/// One change applied to a set of files.
public enum TagEdit: Sendable {
    case setField(LogicalField, String)
    /// Replaces the front cover (and pictures of type "Other"); keeps other picture types.
    case setFrontCover(Artwork)
    case removeArtwork

    public var actionName: String {
        switch self {
        case let .setField(field, _): "Edit \(field.label)"
        case .setFrontCover: "Set Cover"
        case .removeArtwork: "Remove Artwork"
        }
    }
}

/// What the artwork looks like across several selected files.
public enum ArtworkState: Equatable, Sendable {
    case none
    case uniform(Artwork)
    case mixed

    public init(_ snapshots: some Sequence<TagSnapshot>) {
        var result: Artwork??
        for snapshot in snapshots {
            let artwork = snapshot.primaryArtwork
            if let result, result?.digest != artwork?.digest {
                self = .mixed
                return
            }
            result = .some(artwork)
        }
        if let artwork = result ?? nil {
            self = .uniform(artwork)
        } else {
            self = .none
        }
    }
}
