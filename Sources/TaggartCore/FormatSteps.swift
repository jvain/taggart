import Foundation

extension LogicalField: Codable {}

/// What a Format Tags step changes or reads.
public enum FormatTarget: Codable, Hashable, Sendable {
    /// Title, Artist, Album, Album Artist, Genre, Composer and Comment.
    case textTags
    /// One of the fields the tag editor shows.
    case field(LogicalField)
    /// Any tag, by the name the All Tags view shows (e.g. "ARTISTSORT").
    case tag(String)
    /// The file's name, without its extension.
    case fileName

    /// The fields "All text tags" covers.
    public static let textFields: [LogicalField] = [.title, .artist, .album, .albumArtist, .genre, .composer, .comment]

    /// Targets for the tags among `keys` that aren't stored in the editor's
    /// fields (those are offered as fields), sorted by name.
    public static func otherTags(among keys: some Sequence<String>) -> [FormatTarget] {
        let fieldKeys = Set(LogicalField.allCases.flatMap(\.rawKeys))
        return Set(keys).subtracting(fieldKeys).sorted().map { .tag($0) }
    }

    public var label: String {
        switch self {
        case .textTags: "All text tags"
        case let .field(field): field.label
        case let .tag(key): LogicalField.allCases.first { $0.simpleKey == key }?.label ?? key
        case .fileName: "File name"
        }
    }
}

/// One step of Format Tags. Each kind of step uses some of the properties;
/// the others keep their defaults, so switching a step's kind back and forth
/// in the editor doesn't lose what was typed.
public struct FormatStep: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case changeCase
        case replace
        case cleanUpSpaces
        case setTag
        case splitTag
        case removeTags

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .changeCase: "Change Case"
            case .replace: "Replace Text"
            case .cleanUpSpaces: "Clean Up Spaces"
            case .setTag: "Set a Tag"
            case .splitTag: "Split a Tag"
            case .removeTags: "Remove Tags"
            }
        }

        /// Whether the step changes text where it is (rather than setting,
        /// reading or removing tags), so it has a target.
        public var changesText: Bool {
            switch self {
            case .changeCase, .replace, .cleanUpSpaces: true
            case .setTag, .splitTag, .removeTags: false
            }
        }
    }

    public var id = UUID()
    public var kind: Kind

    // Change case, replace text, clean up spaces: what they change.
    public var target = FormatTarget.textTags
    public var caseStyle = CaseStyle.titleCase
    /// Words case changes write exactly like this, separated by commas.
    public var keptWords = CaseConverter.defaultKeptWords.joined(separator: ", ")
    public var find = ""
    public var replacement = ""
    public var matchCase = false
    public var regularExpression = false

    // Set a tag: which one, from what pattern (e.g. "%artist%"), and whether
    // only where it's empty.
    public var destination = FormatTarget.field(.albumArtist)
    public var pattern = "%artist%"
    public var onlyIfEmpty = true

    // Split a tag: which one, with what pattern (e.g. "%artist% - %title%").
    public var source = FormatTarget.field(.title)
    public var splitPattern = "%artist% - %title%"

    // Remove tags: their names, separated by commas, or all others instead.
    public var tagNames = "Comment, ENCODER, ENCODEDBY, ENCODING"
    public var keepsListedTags = false

    public init(_ kind: Kind) {
        self.kind = kind
    }

    /// For the step list, e.g. "Title Case · All text tags".
    public var summary: String {
        switch kind {
        case .changeCase:
            let style = caseStyle.label.split(separator: ":").first.map(String.init) ?? caseStyle.label
            return "\(style) · \(target.label)"
        case .replace:
            return find.isEmpty ? target.label : "“\(find)” → “\(replacement)” · \(target.label)"
        case .cleanUpSpaces:
            return target.label
        case .setTag:
            return "\(destination.label) = \(pattern)"
        case .splitTag:
            return "\(source.label) → \(splitPattern)"
        case .removeTags:
            return keepsListedTags ? "Keep only \(tagNames)" : "Remove \(tagNames)"
        }
    }

    /// The comma-separated names in `text`, trimmed.
    static func names(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Decoded with defaults for missing properties, so lists saved by an
    // older version still load.
    private enum CodingKeys: String, CodingKey {
        case id, kind, target, caseStyle, keptWords, find, replacement, matchCase, regularExpression
        case destination, pattern, onlyIfEmpty, source, splitPattern, tagNames, keepsListedTags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? id
        target = try container.decodeIfPresent(FormatTarget.self, forKey: .target) ?? target
        caseStyle = try container.decodeIfPresent(CaseStyle.self, forKey: .caseStyle) ?? caseStyle
        keptWords = try container.decodeIfPresent(String.self, forKey: .keptWords) ?? keptWords
        find = try container.decodeIfPresent(String.self, forKey: .find) ?? find
        replacement = try container.decodeIfPresent(String.self, forKey: .replacement) ?? replacement
        matchCase = try container.decodeIfPresent(Bool.self, forKey: .matchCase) ?? matchCase
        regularExpression = try container.decodeIfPresent(Bool.self, forKey: .regularExpression) ?? regularExpression
        destination = try container.decodeIfPresent(FormatTarget.self, forKey: .destination) ?? destination
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? pattern
        onlyIfEmpty = try container.decodeIfPresent(Bool.self, forKey: .onlyIfEmpty) ?? onlyIfEmpty
        source = try container.decodeIfPresent(FormatTarget.self, forKey: .source) ?? source
        splitPattern = try container.decodeIfPresent(String.self, forKey: .splitPattern) ?? splitPattern
        tagNames = try container.decodeIfPresent(String.self, forKey: .tagNames) ?? tagNames
        keepsListedTags = try container.decodeIfPresent(Bool.self, forKey: .keepsListedTags) ?? keepsListedTags
    }
}

/// A named list of steps, saved to run again.
public struct FormatStepList: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var steps: [FormatStep]
    public var id: String { name }

    public init(name: String, steps: [FormatStep]) {
        self.name = name
        self.steps = steps
    }
}

public struct FormatStepError: Error, Equatable, Sendable {
    public var message: String
    init(_ message: String) { self.message = message }
}

/// A file as the steps see it: its tags and its name (without extension).
struct FormatState {
    var tags: TagSnapshot
    var name: String
    let format: AudioFormat
}

/// Steps checked and prepared (regular expressions compiled, patterns parsed)
/// to run on many files.
struct FormatProgram: Sendable {
    private enum Step: Sendable {
        case text(@Sendable (String) -> String, FormatTarget)
        case setTag(FormatTarget, TagValuePattern, onlyIfEmpty: Bool)
        case splitTag(FormatTarget, TagsFromNamePattern)
        case removeTags(fields: [LogicalField], keys: Set<String>, keepsListed: Bool)
    }

    private let steps: [Step]

    /// Fails with the first step's problem, e.g. "Step 2: Enter the text to find."
    static func compile(_ steps: [FormatStep]) -> Result<FormatProgram, FormatStepError> {
        var compiled: [Step] = []
        for (index, step) in steps.enumerated() {
            switch compile(step) {
            case let .success(step):
                compiled.append(step)
            case let .failure(error):
                return .failure(steps.count == 1 ? error : FormatStepError("Step \(index + 1): \(error.message)"))
            }
        }
        return .success(FormatProgram(steps: compiled))
    }

    private static func compile(_ step: FormatStep) -> Result<Step, FormatStepError> {
        let target: FormatTarget = switch step.kind {
        case .changeCase, .replace, .cleanUpSpaces: step.target
        case .setTag: step.destination
        case .splitTag: step.source
        case .removeTags: .textTags
        }
        if case let .tag(key) = target, let error = RawTagKey.validate(key).error {
            return .failure(FormatStepError(error))
        }
        switch step.kind {
        case .changeCase:
            let converter = CaseConverter(step.caseStyle, keeping: FormatStep.names(in: step.keptWords))
            return .success(.text({ converter.convert($0) }, step.target))
        case .replace:
            return replacement(for: step).map { .text($0, step.target) }
        case .cleanUpSpaces:
            return .success(.text(cleanUpSpaces, step.target))
        case .setTag:
            if step.destination == .textTags {
                return .failure(FormatStepError("Choose one tag to set."))
            }
            let pattern = TagValuePattern(step.pattern)
            if let error = pattern.error {
                return .failure(FormatStepError(error))
            }
            return .success(.setTag(step.destination, pattern, onlyIfEmpty: step.onlyIfEmpty))
        case .splitTag:
            if step.source == .textTags {
                return .failure(FormatStepError("Choose one tag to split."))
            }
            let pattern = TagsFromNamePattern(step.splitPattern, readsFolders: false)
            if let error = pattern.error {
                return .failure(FormatStepError(error))
            }
            return .success(.splitTag(step.source, pattern))
        case .removeTags:
            let names = FormatStep.names(in: step.tagNames)
            if names.isEmpty {
                return .failure(FormatStepError(step.keepsListedTags ? "List the tags to keep." : "List the tags to remove."))
            }
            // Names of fields ("Album Artist", "Track Total") or tags ("ENCODER").
            var fields: [LogicalField] = []
            var keys = Set<String>()
            for name in names {
                if let field = LogicalField.allCases.first(where: { $0.label.caseInsensitiveCompare(name) == .orderedSame }) {
                    fields.append(field)
                } else {
                    keys.insert(name.uppercased())
                }
            }
            return .success(.removeTags(fields: fields, keys: keys, keepsListed: step.keepsListedTags))
        }
    }

    private static func replacement(for step: FormatStep) -> Result<@Sendable (String) -> String, FormatStepError> {
        let find = step.find
        let replacement = step.replacement
        guard !find.isEmpty else { return .failure(FormatStepError("Enter the text to find.")) }
        if step.regularExpression {
            let options: NSRegularExpression.Options = step.matchCase ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: find, options: options) else {
                return .failure(FormatStepError("The regular expression isn't valid."))
            }
            return .success { text in
                expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                    withTemplate: replacement)
            }
        }
        let options: String.CompareOptions = step.matchCase ? [] : [.caseInsensitive]
        return .success { $0.replacingOccurrences(of: find, with: replacement, options: options) }
    }

    /// Removes spaces at the start and end, and turns runs of spaces and tabs
    /// into one space (line breaks, e.g. in comments, are kept).
    @Sendable static func cleanUpSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func run(_ state: inout FormatState) {
        for step in steps {
            switch step {
            case let .text(transform, target):
                Self.transform(&state, target, transform)
            case let .setTag(destination, pattern, onlyIfEmpty):
                guard !onlyIfEmpty || Self.value(of: destination, in: state).isEmpty else { continue }
                let value = pattern.value(for: state)
                if !value.isEmpty {
                    Self.set(destination, to: value, in: &state)
                }
            case let .splitTag(source, pattern):
                guard let tags = pattern.tags(in: Self.value(of: source, in: state)) else { continue }
                for field in pattern.fields {
                    if let value = tags[field] {
                        state.tags.set(field, to: value, format: state.format)
                    }
                }
            case let .removeTags(fields, keys, keepsListed):
                if keepsListed {
                    let kept = keys.union(fields.flatMap(\.rawKeys))
                    state.tags.fields = state.tags.fields.filter { kept.contains($0.key) }
                } else {
                    for field in fields {
                        state.tags.set(field, to: "", format: state.format)
                    }
                    for key in keys {
                        state.tags.fields[key] = nil
                    }
                }
            }
        }
    }

    /// Applies `transform` to each value; values that become empty are removed,
    /// and the tag with them if none is left.
    private static func transform(_ state: inout FormatState, _ target: FormatTarget, _ transform: (String) -> String) {
        func transformValues(_ key: String) {
            guard let values = state.tags.fields[key] else { return }
            let changed = values.map(transform).filter { !$0.isEmpty }
            state.tags.fields[key] = changed.isEmpty ? nil : changed
        }
        switch target {
        case .textTags:
            for field in FormatTarget.textFields {
                transformValues(field.simpleKey!)
            }
        case let .field(field):
            if let key = field.simpleKey {
                transformValues(key)
            } else {
                let value = state.tags.value(of: field)
                if !value.isEmpty {
                    state.tags.set(field, to: transform(value), format: state.format)
                }
            }
        case let .tag(key):
            transformValues(key)
        case .fileName:
            state.name = transform(state.name)
        }
    }

    static func value(of target: FormatTarget, in state: FormatState) -> String {
        switch target {
        case .textTags: ""
        case let .field(field): state.tags.value(of: field)
        case let .tag(key): (state.tags.fields[key] ?? []).joined(separator: "; ")
        case .fileName: state.name
        }
    }

    private static func set(_ target: FormatTarget, to value: String, in state: inout FormatState) {
        switch target {
        case .textTags:
            break
        case let .field(field):
            state.tags.set(field, to: value, format: state.format)
        case let .tag(key):
            state.tags.fields[key] = [value]
        case .fileName:
            state.name = RenamePattern.clean(value)
        }
    }
}

extension LogicalField {
    /// Every raw key the field can be stored under. A total can be in the
    /// number's tag ("3/12" in MP3 and M4A files) or in a tag of its own.
    var rawKeys: [String] {
        if let key = simpleKey {
            return [key]
        }
        let keys = numberKeys!
        return self == .trackTotal || self == .discTotal ? [keys.number] + keys.totals : [keys.number]
    }
}

/// A pattern for a tag's new value, such as "%artist%" or "%title% (Live)".
/// Placeholders are the rename ones (with values as they are, e.g. track "3"
/// rather than "03"), %filename% for the file's name, or any tag's name
/// ("%MOOD%").
struct TagValuePattern: Sendable {
    private enum Part: Sendable {
        case literal(String)
        case field(LogicalField)
        case fileName
        case tag(String)
    }

    private let parts: [Part]
    let error: String?

    init(_ text: String) {
        var parts: [Part] = []
        var rest = Substring(text)
        while let start = rest.firstIndex(of: "%") {
            parts.append(.literal(String(rest[..<start])))
            let nameStart = rest.index(after: start)
            guard let end = rest[nameStart...].firstIndex(of: "%"), end > nameStart else {
                // A lone "%" (or "%%") is just text.
                parts.append(.literal(String(rest[start...])))
                rest = ""
                break
            }
            let name = String(rest[nameStart..<end])
            if let token = RenamePattern.tokens.first(where: { $0.name == name.lowercased() }) {
                parts.append(.field(token.field))
            } else if name.lowercased() == "filename" {
                parts.append(.fileName)
            } else {
                parts.append(.tag(name.uppercased()))
            }
            rest = rest[rest.index(after: end)...]
        }
        parts.append(.literal(String(rest)))
        self.parts = parts
        error = text.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter a pattern." : nil
    }

    /// The pattern filled in. If a placeholder is empty, separators it leaves
    /// at either end are dropped ("%track% - %title%" gives "Song", not "- Song").
    func value(for state: FormatState) -> String {
        var missesValue = false
        let value = parts.map { part in
            let text = switch part {
            case let .literal(text): text
            case let .field(field): state.tags.value(of: field)
            case .fileName: state.name
            case let .tag(key): (state.tags.fields[key] ?? []).joined(separator: "; ")
            }
            if case .literal = part {} else if text.isEmpty {
                missesValue = true
            }
            return text
        }
        .joined()
        return value.trimmingCharacters(in: missesValue ? RenamePattern.separators : .whitespaces)
    }
}

/// One change Format Tags would make to one file.
public struct FormatChange: Identifiable, Sendable {
    public var itemID: AudioFileItem.ID
    public var url: URL
    /// "Title", "ARTISTSORT" or "File Name".
    public var label: String
    public var before: String
    public var after: String
    /// Why the change can't be made (for renames), or nil.
    public var problem: String?

    public var id: String { "\(itemID)-\(label)" }
}

/// What running Format Tags steps on files would do.
public struct FormatPlan: Sendable {
    /// Every change, file by file in list order.
    public var changes: [FormatChange] = []
    /// The new tags of the files whose tags change.
    var tags: [AudioFileItem.ID: TagSnapshot] = [:]
    /// The files whose names change.
    public var renames: [RenamePlan] = []

    public init() {}

    /// How many files change (tags, name or both).
    public var fileCount: Int {
        Set(tags.keys).union(renames.filter { $0.status == .rename }.map(\.id)).count
    }

    /// The fields and tags that differ between two snapshots, as display
    /// values: the editor's fields first, then other tags by name.
    static func differences(from before: TagSnapshot, to after: TagSnapshot) -> [(label: String, before: String, after: String)] {
        var differences: [(String, String, String)] = []
        for field in LogicalField.allCases {
            let old = before.value(of: field)
            let new = after.value(of: field)
            if old != new {
                differences.append((field.label, old, new))
            }
        }
        let fieldKeys = Set(LogicalField.allCases.flatMap(\.rawKeys))
        let keys = Set(before.fields.keys).union(after.fields.keys).subtracting(fieldKeys)
        for key in keys.sorted() where before.fields[key] != after.fields[key] {
            differences.append((key, (before.fields[key] ?? []).joined(separator: "; "),
                                (after.fields[key] ?? []).joined(separator: "; ")))
        }
        return differences
    }
}
