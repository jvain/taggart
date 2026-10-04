import Foundation

/// Numbers files' tracks 1, 2, 3… in a given order (the list's), like Mp3tag's
/// auto-numbering wizard.
public struct TrackNumbering: Sendable, Equatable {
    /// The first number.
    public var start: Int
    /// Whether each folder's files are numbered from `start` on their own,
    /// as separate albums, rather than all in one run.
    public var restartsInEachFolder: Bool
    /// Whether Track Total is set to the last number (of each folder).
    public var setsTotal: Bool
    /// Whether numbers get leading zeros: "01", or "001" when numbering
    /// goes past 99.
    public var padsWithZeros: Bool

    public init(start: Int = 1, restartsInEachFolder: Bool = true, setsTotal: Bool = false, padsWithZeros: Bool = false) {
        self.start = start
        self.restartsInEachFolder = restartsInEachFolder
        self.setsTotal = setsTotal
        self.padsWithZeros = padsWithZeros
    }

    /// The track number, and the total if one is set, for each of the files
    /// at `urls`, numbered in this order.
    public func numbers(for urls: [URL]) -> [(number: String, total: String?)] {
        let groups = urls.map { restartsInEachFolder ? $0.deletingLastPathComponent().standardizedFileURL.path : "" }
        var counts: [String: Int] = [:]
        for group in groups {
            counts[group, default: 0] += 1
        }
        var next: [String: Int] = [:]
        return groups.map { group in
            let number = next[group, default: start]
            next[group] = number + 1
            let last = start + counts[group]! - 1
            let width = padsWithZeros ? max(2, String(last).count) : 0
            let text = String(number)
            return (String(repeating: "0", count: max(0, width - text.count)) + text, setsTotal ? String(last) : nil)
        }
    }
}

/// One file's track number before and after numbering.
public struct TrackNumberChange: Identifiable, Sendable {
    public var id: AudioFileItem.ID
    public var url: URL
    /// "3 of 12", "3", or "" for no number.
    public var before: String
    public var after: String

    public var isChange: Bool { before != after }

    static func display(_ tags: TagSnapshot) -> String {
        let number = tags.value(of: .trackNumber)
        let total = tags.value(of: .trackTotal)
        return total.isEmpty ? number : "\(number.isEmpty ? "–" : number) of \(total)"
    }
}
