import Foundation
import TagBridge

/// Genre names to suggest while typing in the Genre field.
public enum Genres {
    /// The standard ID3v1 genres (the original 80 plus Winamp's extensions),
    /// from TagLib's built-in table.
    public static let standard: [String] = {
        let list = tb_id3v1_genres()
        defer { tb_string_list_free(list) }
        guard list.count > 0, let items = list.items else { return [] }
        return (0..<list.count).compactMap { items[$0].map { String(cString: $0) } }
    }()

    public struct Suggestion: Hashable, Identifiable, Sendable {
        /// The genre, as shown in the list.
        public var genre: String
        /// The whole field text if the suggestion is picked: earlier genres in
        /// a multi-value field ("Rock; ") are kept.
        public var completion: String
        public var id: String { completion }
    }

    /// Suggestions for the genre being typed: the part of `text` after the last
    /// ";". Genres in `preferred` (those in the loaded files) come before the
    /// standard ones, and names starting with the typed text before names
    /// merely containing it. Genres already in the field aren't suggested.
    public static func suggestions(for text: String, preferring preferred: [String], limit: Int = 12) -> [Suggestion] {
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        let typed = (parts.last.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        let earlier = parts.dropLast().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let prefix = earlier.isEmpty ? "" : earlier.joined(separator: "; ") + "; "

        func key(_ genre: String) -> String {
            genre.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let typedKey = key(typed)
        var seen = Set(earlier.map(key))
        var starting: [String] = []
        var containing: [String] = []
        for genre in preferred + standard {
            let genreKey = key(genre)
            // Skip duplicates, and exactly the text already typed (but do offer
            // "Jazz" for "JAZZ", to fix the spelling).
            guard !genreKey.isEmpty, seen.insert(genreKey).inserted, genre != typed else { continue }
            if typedKey.isEmpty {
                // Nothing typed yet: offer only the genres already in use.
                if preferred.contains(genre) {
                    starting.append(genre)
                }
            } else if genreKey.hasPrefix(typedKey) {
                starting.append(genre)
            } else if genreKey.contains(typedKey) {
                containing.append(genre)
            }
        }
        return (starting + containing).prefix(limit).map { Suggestion(genre: $0, completion: prefix + $0) }
    }
}
