import Foundation

/// Pairs files with the tracks of a release.
///
/// Every file–track pair gets a score from what agrees: disc and track
/// numbers (from the tags, or a number at the start of the file name), the
/// title (tag or file name), the duration, and the position in the list.
/// The best-scoring pairs are taken first; pairs with too little in common
/// are left unmatched, for the user to pair by hand.
public enum TrackMatcher {
    public struct File: Sendable {
        public var id: AudioFileItem.ID
        public var disc: Int?
        public var track: Int?
        public var title: String
        /// The file name without its extension.
        public var name: String
        public var duration: TimeInterval

        public init(id: AudioFileItem.ID, disc: Int?, track: Int?, title: String, name: String, duration: TimeInterval) {
            self.id = id
            self.disc = disc
            self.track = track
            self.title = title
            self.name = name
            self.duration = duration
        }
    }

    /// Pairs scoring less than this are too uncertain to make.
    static let threshold = 2.5

    /// Each matched file's track, as an index into `release.tracks`.
    /// `files` are in list order.
    public static func match(_ files: [File], to release: MBRelease) -> [AudioFileItem.ID: Int] {
        let tracks = release.tracks
        let isSingleDisc = (release.media?.count ?? 1) <= 1
        let sameCount = files.count == tracks.count
        var pairs: [(score: Double, file: Int, track: Int)] = []
        for (fileIndex, file) in files.enumerated() {
            let fileTitle = normalized(file.title)
            let nameTitle = normalized(withoutLeadingNumber(file.name))
            let number = file.track ?? leadingNumber(file.name)
            for (trackIndex, entry) in tracks.enumerated() {
                var score = 0.0
                let disc = entry.medium.position ?? 1
                if let number {
                    var numberScore = 0.0
                    if number == entry.track.position && (file.disc ?? (isSingleDisc ? 1 : nil)) == disc {
                        numberScore = 4
                    }
                    if !isSingleDisc && number == trackIndex + 1 && (file.disc ?? 1) == 1 {
                        // Numbered straight through the discs (1–15 rather than 1–12, 1–3).
                        numberScore = max(numberScore, 3)
                    }
                    if number == entry.track.position && file.disc == nil {
                        // A multi-disc release, and the file doesn't say which disc.
                        numberScore = max(numberScore, 1.5)
                    }
                    score += numberScore
                }
                let title = normalized(entry.track.title)
                score += 3 * max(similarity(fileTitle, title), similarity(nameTitle, title))
                if let length = entry.track.length, file.duration > 0 {
                    let difference = abs(file.duration - Double(length) / 1000)
                    score += difference <= 2 ? 2 : difference <= 5 ? 1 : difference <= 15 ? 0.3 : difference > 30 ? -2 : 0
                }
                if sameCount && fileIndex == trackIndex {
                    score += 1
                }
                pairs.append((score, fileIndex, trackIndex))
            }
        }

        // Best first; ties go to the pair in list order.
        pairs.sort { $0.score != $1.score ? $0.score > $1.score : ($0.file, $0.track) < ($1.file, $1.track) }
        var matches: [AudioFileItem.ID: Int] = [:]
        var usedTracks = Set<Int>()
        for pair in pairs where pair.score >= threshold {
            let id = files[pair.file].id
            guard matches[id] == nil, !usedTracks.contains(pair.track) else { continue }
            matches[id] = pair.track
            usedTracks.insert(pair.track)
        }
        return matches
    }

    /// Lowercase letters and digits, accents removed, words separated by
    /// single spaces: "Paranoid Android (Remastered)" → "paranoid android remastered".
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: " ")
    }

    /// 1 for the same text, 0.9 when one contains the other (as a file name
    /// often contains the title), otherwise how many letter pairs they share.
    static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b {
            return 1
        }
        let (shorter, longer) = a.count < b.count ? (a, b) : (b, a)
        if shorter.count >= 4 && " \(longer) ".contains(" \(shorter) ") {
            return 0.9
        }
        return dice(a, b)
    }

    /// Dice's coefficient over letter pairs: 2 × shared pairs ÷ all pairs.
    private static func dice(_ a: String, _ b: String) -> Double {
        func bigrams(_ text: String) -> [String: Int] {
            let characters = Array(text)
            var counts: [String: Int] = [:]
            for index in characters.indices.dropLast() {
                counts[String(characters[index...index + 1]), default: 0] += 1
            }
            return counts
        }
        let first = bigrams(a)
        let second = bigrams(b)
        let total = first.values.reduce(0, +) + second.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let shared = first.reduce(0) { $0 + min($1.value, second[$1.key] ?? 0) }
        return Double(2 * shared) / Double(total)
    }

    /// "01 - Airbag" → 1; nil if the name doesn't start with a number.
    static func leadingNumber(_ name: String) -> Int? {
        let digits = name.prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty || digits.count > 3 ? nil : Int(digits)
    }

    /// "01 - Airbag" → "Airbag".
    static func withoutLeadingNumber(_ name: String) -> String {
        guard leadingNumber(name) != nil else { return name }
        return String(name.drop { $0.isNumber || $0 == " " || $0 == "-" || $0 == "." || $0 == "_" })
    }
}
