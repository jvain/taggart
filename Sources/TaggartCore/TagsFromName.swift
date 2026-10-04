import Foundation

/// A pattern for reading tags from file names, the reverse of `RenamePattern`:
/// "%track% - %title%" reads "03 - Song.flac" as track 3, title "Song".
///
/// - "/" matches folder names too: "%artist%/%album%/%track% - %title%" reads
///   the artist and album from the two folders the file is in.
/// - `%skip%` matches text that isn't wanted.
/// - Track, disc and the totals match digits only (leading zeros are dropped),
///   and the year four digits. Other placeholders match as little as they can,
///   so "%track% - %title%" reads "01 - Song - Live" as title "Song - Live".
/// - Literal text matches regardless of case.
public struct TagsFromNamePattern: Sendable {
    public struct Token: Sendable, Identifiable {
        public var name: String
        public var label: String
        /// Nil for %skip%.
        var field: LogicalField?

        public var placeholder: String { "%\(name)%" }
        public var id: String { name }
    }

    /// The placeholders a pattern can use: the rename placeholders plus %skip%.
    public static let tokens: [Token] = RenamePattern.tokens.map { Token(name: $0.name, label: $0.label, field: $0.field) }
        + [Token(name: "skip", label: "Skip", field: nil)]

    public let text: String
    /// Why the pattern can't be used, or nil if it can.
    public let error: String?
    /// One expression per path component, the file name last, and the field
    /// each capture group fills.
    private let components: [(expression: NSRegularExpression, fields: [LogicalField])]

    public init(_ text: String) {
        self.text = text
        var error: String?
        var components: [(NSRegularExpression, [LogicalField])] = []
        var usesAField = false

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            error = "Enter a pattern."
        } else if trimmed.hasPrefix("/") || trimmed.hasSuffix("/") || text.contains("//") {
            error = "Folder names in the pattern can't be empty."
        }

        for part in text.split(separator: "/", omittingEmptySubsequences: false) where error == nil {
            var expression = "^"
            var fields: [LogicalField] = []
            var rest = Substring(part)
            while let start = rest.firstIndex(of: "%") {
                expression += NSRegularExpression.escapedPattern(for: String(rest[..<start]))
                let nameStart = rest.index(after: start)
                guard let end = rest[nameStart...].firstIndex(of: "%") else {
                    // A lone "%" is just a character.
                    expression += NSRegularExpression.escapedPattern(for: String(rest[start...]))
                    rest = ""
                    break
                }
                let name = rest[nameStart..<end].lowercased()
                guard let token = Self.tokens.first(where: { $0.name == name }) else {
                    error = error ?? "Unknown placeholder “%\(name)%”."
                    break
                }
                if let field = token.field {
                    expression += Self.capture(for: field)
                    fields.append(field)
                    usesAField = true
                } else {
                    expression += ".*?"
                }
                rest = rest[rest.index(after: end)...]
            }
            expression += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
            if error == nil {
                if let compiled = try? NSRegularExpression(pattern: expression, options: [.caseInsensitive]) {
                    components.append((compiled, fields))
                } else {
                    error = "The pattern can't be used."
                }
            }
        }
        if error == nil && !usesAField {
            error = "Use at least one tag placeholder, e.g. %title%."
        }
        self.error = error
        self.components = error == nil ? components : []
    }

    private static func capture(for field: LogicalField) -> String {
        switch field {
        case .trackNumber, .trackTotal, .discNumber, .discTotal: "(\\d+)"
        case .date: "(\\d{4})"
        default: "(.+?)"
        }
    }

    /// The fields the pattern reads, in the order they appear in it.
    public var fields: [LogicalField] {
        var fields: [LogicalField] = []
        for field in components.flatMap(\.fields) where !fields.contains(field) {
            fields.append(field)
        }
        return fields
    }

    /// The tags the pattern reads from a file's path, or nil if the name (or
    /// its folders) doesn't match. Values are trimmed; empty ones are left out.
    public func tags(from url: URL, underscoresAsSpaces: Bool = false) -> [LogicalField: String]? {
        guard error == nil else { return nil }
        let folders = url.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        let names = folders + [url.deletingPathExtension().lastPathComponent]
        guard names.count >= components.count else { return nil }

        var tags: [LogicalField: String] = [:]
        for (component, name) in zip(components, names.suffix(components.count)) {
            let text = underscoresAsSpaces ? name.replacingOccurrences(of: "_", with: " ") : name
            let range = NSRange(text.startIndex..., in: text)
            guard let match = component.expression.firstMatch(in: text, range: range) else { return nil }
            for (index, field) in component.fields.enumerated() {
                guard let captured = Range(match.range(at: index + 1), in: text) else { continue }
                var value = text[captured].trimmingCharacters(in: .whitespaces)
                if field.isNumeric {
                    // "01" → "1", but "0" stays "0".
                    value = String(Int(value) ?? 0)
                }
                if !value.isEmpty, tags[field] == nil {
                    tags[field] = value
                }
            }
        }
        return tags
    }
}

/// What reading tags from one file's name would do.
public struct TagsFromNamePlan: Identifiable, Sendable {
    public var id: AudioFileItem.ID
    public var url: URL
    /// The tags read, or nil if the name doesn't match the pattern.
    public var tags: [LogicalField: String]?
    /// The pattern's fields, in pattern order, for display.
    public var fields: [LogicalField] = []

    /// e.g. "Track 3 · Title Song", in the order of the pattern.
    public var summary: String {
        guard let tags else { return "" }
        return fields.compactMap { field in tags[field].map { "\(field.label) \($0)" } }
            .joined(separator: " · ")
    }
}
