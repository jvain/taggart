import Foundation

/// How Format Tags changes the case of text.
public enum CaseStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case titleCase
    case sentenceCase
    case capitalizeEveryWord
    case uppercase
    case lowercase

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .titleCase: "Title Case: Dancing in the Dark"
        case .sentenceCase: "Sentence case: Dancing in the dark"
        case .capitalizeEveryWord: "Capitalize Every Word: Dancing In The Dark"
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        }
    }

    /// Whether the style uses the words to keep as written.
    public var usesKeptWords: Bool {
        switch self {
        case .titleCase, .sentenceCase, .capitalizeEveryWord: true
        case .uppercase, .lowercase: false
        }
    }
}

/// Changes the case of text the way titles are written.
///
/// Title Case follows MusicBrainz's English style: every word is capitalized
/// except articles, short conjunctions and short prepositions ("Dancing in the
/// Dark"), which are capitalized only as the first or last word of the title or
/// of a part of it (after a colon, inside brackets, around " - ").
///
/// Text that's mostly in normal case keeps the capitals it has inside words
/// ("Live at the BBC", "McCartney", "iPhone"). Text written all in capitals or
/// all in lowercase has no such hints, so it's rewritten from scratch. Either
/// way, Roman numerals ("Part II") and initials ("R.E.M.") come out in
/// capitals, and the words to keep as written are always spelled as listed.
public struct CaseConverter: Sendable {
    public var style: CaseStyle
    private let keptWords: [String: String]

    /// Common words that aren't written in normal case.
    public static let defaultKeptWords = ["DJ", "MC", "UK", "USA", "BBC", "TV", "OK", "EP", "LP", "CD", "NYC", "R&B", "AC/DC"]

    /// Lowercase in Title Case unless first or last: MusicBrainz's articles,
    /// coordinating conjunctions and short prepositions (without "up" and
    /// "off", more often parts of verbs in song titles: "Shut Up and Dance"),
    /// plus "vs." and "feat.".
    static let smallWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "as", "at", "by", "for", "in", "of", "on", "to", "per", "via",
        "vs", "vs.", "v.", "feat", "feat.", "ft.", "featuring", "'n'", "’n’", "n'", "o'",
    ]
    /// Credits, lowercase even where a part starts: "Song (feat. Artist)".
    static let creditWords: Set<String> = ["vs", "vs.", "v.", "feat", "feat.", "ft.", "featuring"]

    public init(_ style: CaseStyle, keeping keptWords: [String] = Self.defaultKeptWords) {
        self.style = style
        var map: [String: String] = [:]
        for word in keptWords where !word.isEmpty {
            map[word.lowercased()] = word
        }
        self.keptWords = map
    }

    public func convert(_ text: String) -> String {
        switch style {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .titleCase, .sentenceCase, .capitalizeEveryWord: break
        }

        // Runs of whitespace and of other characters.
        var pieces: [String] = []
        for character in text {
            if let last = pieces.last?.last, last.isWhitespace == character.isWhitespace {
                pieces[pieces.count - 1].append(character)
            } else {
                pieces.append(String(character))
            }
        }

        var words: [Word] = []
        var startsPart = true
        func endPart() {
            if !words.isEmpty {
                words[words.count - 1].endsPart = true
            }
            startsPart = true
        }
        for (index, piece) in pieces.enumerated() where !piece.first!.isWhitespace {
            guard piece.contains(where: { $0.isLetter || $0.isNumber }) else {
                // "-", "(", ":" and the like on their own.
                if Self.partBreaks.contains(piece) || piece.contains(where: { Self.partOpeners.contains($0) || Self.partClosers.contains($0) }) {
                    endPart()
                }
                continue
            }
            let coreStart = piece.firstIndex { !Self.leadingPunctuation.contains($0) } ?? piece.endIndex
            let coreEnd = piece[coreStart...].lastIndex { !Self.trailingPunctuation.contains($0) }.map { piece.index(after: $0) } ?? coreStart
            let prefix = piece[..<coreStart]
            let suffix = piece[coreEnd...]
            if prefix.contains(where: Self.partOpeners.contains) {
                endPart()
            }
            words.append(Word(piece: index, prefix: String(prefix), core: String(piece[coreStart..<coreEnd]),
                              suffix: String(suffix), startsPart: startsPart))
            startsPart = false
            if suffix.contains(where: Self.partClosers.contains) {
                endPart()
            }
        }
        if !words.isEmpty {
            words[words.count - 1].endsPart = true
        }

        let keepsCapitals = style != .capitalizeEveryWord && Self.isMostlyNormalCase(words.map(\.core))
        for (position, word) in words.enumerated() {
            pieces[word.piece] = word.prefix
                + convertWord(word.core, startsPart: word.startsPart, endsPart: word.endsPart,
                              startsText: position == 0, keepsCapitals: keepsCapitals)
                + word.suffix
        }
        return pieces.joined()
    }

    private struct Word {
        var piece: Int
        var prefix: String
        var core: String
        var suffix: String
        var startsPart: Bool
        var endsPart = false
    }

    private static let leadingPunctuation = Set("([{\"“«¿¡")
    private static let trailingPunctuation = Set(")]}\"”»,;:!?…")
    /// A word after one of these starts a new part of the title.
    private static let partOpeners = Set("([{")
    /// A word before one of these ends a part of the title.
    private static let partClosers = Set(")]}:!?")
    /// Separators between parts: "Song - Live", "Side A / Side B".
    private static let partBreaks: Set<String> = ["-", "–", "—", "/", "|"]
    /// Separators within a word: "Hip-Hop", "AC/DC".
    private static let wordJoiners = Set("-/_")

    /// Whether most words are in normal case rather than in capitals, so the
    /// capitals inside words ("BBC", "McCartney") were probably meant.
    static func isMostlyNormalCase(_ words: [String]) -> Bool {
        var lowercase = 0
        var capitals = 0
        for word in words {
            let letters = word.filter(\.isLetter)
            if letters.contains(where: \.isLowercase) {
                lowercase += 1
            } else if letters.count >= 2 {
                capitals += 1
            }
        }
        return lowercase > capitals
    }

    private func convertWord(_ word: String, startsPart: Bool, endsPart: Bool, startsText: Bool, keepsCapitals: Bool) -> String {
        if let kept = keptWords[word.lowercased()] {
            return kept
        }
        // The parts of "hip-hop" or "R&B/soul" are words of their own.
        var parts: [String] = [""]
        for character in word {
            if Self.wordJoiners.contains(character) {
                parts.append(String(character))
                parts.append("")
            } else {
                parts[parts.count - 1].append(character)
            }
        }
        let wordParts = stride(from: 0, to: parts.count, by: 2)
        for (index, position) in wordParts.enumerated() {
            parts[position] = convertPart(
                parts[position],
                startsPart: startsPart && index == 0,
                endsPart: endsPart && position == parts.count - 1,
                startsText: startsText && index == 0,
                keepsCapitals: keepsCapitals
            )
        }
        return parts.joined()
    }

    private func convertPart(_ part: String, startsPart: Bool, endsPart: Bool, startsText: Bool, keepsCapitals: Bool) -> String {
        guard part.contains(where: \.isLetter) else { return part }
        let lower = part.lowercased()
        if let kept = keptWords[lower] {
            return kept
        }
        if Self.isRomanNumeral(lower) || Self.isInitials(lower) {
            return part.uppercased()
        }
        let isSmall = Self.smallWords.contains(lower)
        if keepsCapitals && !isSmall {
            if Self.hasCapitalsInside(part) {
                return part
            }
            // "I", "I'm": capitalized in English, but in sentence case this is
            // the only hint that the text is English.
            if part.hasPrefix("I") && (part.count == 1 || part.dropFirst().first == "'" || part.dropFirst().first == "’") {
                return part
            }
        }
        switch style {
        case .titleCase:
            let staysLowercase = Self.creditWords.contains(lower) ? !startsText : !startsPart && !endsPart
            return isSmall && staysLowercase ? lower : Self.capitalized(lower)
        case .capitalizeEveryWord:
            return Self.capitalized(lower)
        case .sentenceCase:
            return startsText ? Self.capitalized(lower) : lower
        case .uppercase, .lowercase:
            return part
        }
    }

    /// The first letter in capitals, unless a digit comes first ("2nd").
    static func capitalized(_ word: String) -> String {
        for index in word.indices {
            let character = word[index]
            if character.isNumber {
                return word
            }
            if character.isLetter {
                return String(word[..<index]) + String(character).capitalized + String(word[word.index(after: index)...])
            }
        }
        return word
    }

    /// "McCartney", "iPhone", "BBC": a capital letter after the first letter.
    static func hasCapitalsInside(_ word: String) -> Bool {
        word.filter(\.isLetter).dropFirst().contains(where: \.isUppercase)
    }

    /// II to XXXIX (not I, which is a word; nor letters like M, C, D and L,
    /// which would turn "mix" or "did" into numerals).
    static func isRomanNumeral(_ lower: String) -> Bool {
        lower.count >= 2 && lower.wholeMatch(of: #/x{0,3}(ix|iv|v?i{0,3})/#) != nil
    }

    /// "r.e.m.", "u.s.a": single letters with dots.
    static func isInitials(_ lower: String) -> Bool {
        guard lower.contains(".") else { return false }
        let letters = lower.split(separator: ".")
        return letters.count >= 2 && letters.allSatisfy { $0.count == 1 && $0.first!.isLetter }
    }
}
