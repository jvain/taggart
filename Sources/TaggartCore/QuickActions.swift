import Foundation

/// A text edit applied to tags of many files at once, like Mp3tag's quick
/// actions: case conversion, text replacement, or tidying spaces.
public enum QuickAction: Sendable, Equatable {
    case changeCase(CaseStyle)
    case replace(find: String, with: String, matchCase: Bool, regularExpression: Bool)
    case cleanUpSpaces

    public enum CaseStyle: String, CaseIterable, Sendable, Identifiable {
        case titleCase
        case sentenceCase
        case uppercase
        case lowercase

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .titleCase: "Title Case (Each Word Capitalized)"
            case .sentenceCase: "Sentence case (first letter only)"
            case .uppercase: "UPPERCASE"
            case .lowercase: "lowercase"
            }
        }
    }

    /// The tags quick actions can change: the text ones.
    public static let fields: [LogicalField] = [.title, .artist, .album, .albumArtist, .genre, .composer, .comment]

    public var actionName: String {
        switch self {
        case .changeCase: "Change Case"
        case .replace: "Replace Text"
        case .cleanUpSpaces: "Clean Up Spaces"
        }
    }

    /// The function applying the action to one value, or an error message
    /// (for an empty search or an invalid regular expression).
    public func transform() -> Result<@Sendable (String) -> String, QuickActionError> {
        switch self {
        case let .changeCase(style):
            return .success { Self.changeCase($0, to: style) }
        case let .replace(find, replacement, matchCase, regularExpression):
            guard !find.isEmpty else { return .failure(QuickActionError("Enter the text to find.")) }
            if regularExpression {
                let options: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
                guard let expression = try? NSRegularExpression(pattern: find, options: options) else {
                    return .failure(QuickActionError("The regular expression isn't valid."))
                }
                return .success { text in
                    expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                        withTemplate: replacement)
                }
            }
            let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
            return .success { $0.replacingOccurrences(of: find, with: replacement, options: options) }
        case .cleanUpSpaces:
            return .success(Self.cleanUpSpaces)
        }
    }

    /// Characters after which Title Case starts a new word (besides whitespace).
    /// Apostrophes aren't among them: "don't" becomes "Don't", not "Don'T".
    private static let wordStarts = Set("([{\"“‘/-_.")

    static func changeCase(_ text: String, to style: CaseStyle) -> String {
        switch style {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .sentenceCase:
            // Capitalize the first letter, wherever it is ("(the song)" → "(The song)").
            var result = ""
            var capitalized = false
            for character in text.lowercased() {
                if !capitalized, character.isLetter {
                    result += String(character).uppercased()
                    capitalized = true
                } else {
                    result.append(character)
                }
            }
            return result
        case .titleCase:
            var result = ""
            var atWordStart = true
            for character in text.lowercased() {
                if atWordStart, character.isLetter {
                    result += String(character).uppercased()
                    atWordStart = false
                } else {
                    result.append(character)
                    if character.isWhitespace || wordStarts.contains(character) {
                        atWordStart = true
                    } else if character.isLetter || character.isNumber {
                        // "2nd" stays "2nd": a word starting with a digit isn't capitalized.
                        atWordStart = false
                    }
                }
            }
            return result
        }
    }

    /// Removes spaces at the start and end, and turns runs of spaces and tabs
    /// into one space (line breaks, e.g. in comments, are kept).
    @Sendable static func cleanUpSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct QuickActionError: Error, Equatable, Sendable {
    public var message: String
    init(_ message: String) { self.message = message }
}

/// One tag a quick action would change in one file.
public struct QuickActionChange: Identifiable, Sendable {
    public var itemID: AudioFileItem.ID
    public var url: URL
    public var field: LogicalField
    public var before: String
    public var after: String

    public var id: String { "\(itemID)-\(field.rawValue)" }
}

extension TagSnapshot {
    /// The snapshot with `transform` applied to each value of `fields`.
    /// Values that become empty are removed, and the tag with them if none is left.
    func applying(_ transform: (String) -> String, to fields: [LogicalField]) -> TagSnapshot {
        var copy = self
        for field in fields {
            guard let key = field.simpleKey, let values = copy.fields[key] else { continue }
            let changed = values.map(transform).filter { !$0.isEmpty }
            copy.fields[key] = changed.isEmpty ? nil : changed
        }
        return copy
    }
}
