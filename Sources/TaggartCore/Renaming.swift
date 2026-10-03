import Darwin
import Foundation

/// A file name pattern such as "%track% - %title%". The file's extension is
/// kept, and characters that don't belong in file names are replaced.
public struct RenamePattern: Sendable, Equatable {
    public struct Token: Sendable, Identifiable {
        public var name: String
        public var label: String
        var field: LogicalField

        public var placeholder: String { "%\(name)%" }
        public var id: String { name }
    }

    /// The placeholders a pattern can use, in the order the UI offers them.
    public static let tokens: [Token] = [
        Token(name: "track", label: "Track", field: .trackNumber),
        Token(name: "title", label: "Title", field: .title),
        Token(name: "artist", label: "Artist", field: .artist),
        Token(name: "album", label: "Album", field: .album),
        Token(name: "albumartist", label: "Album Artist", field: .albumArtist),
        Token(name: "year", label: "Year", field: .date),
        Token(name: "disc", label: "Disc", field: .discNumber),
        Token(name: "tracktotal", label: "Track Total", field: .trackTotal),
        Token(name: "disctotal", label: "Disc Total", field: .discTotal),
        Token(name: "genre", label: "Genre", field: .genre),
        Token(name: "composer", label: "Composer", field: .composer),
    ]

    private enum Part: Sendable, Equatable {
        case literal(String)
        case field(LogicalField)
    }

    public let text: String
    private let parts: [Part]
    /// Why the pattern can't be used, or nil if it can.
    public let error: String?

    public init(_ text: String) {
        self.text = text
        var parts: [Part] = []
        var error: String?
        var literal = ""
        var rest = Substring(text)
        while let start = rest.firstIndex(of: "%") {
            literal += rest[..<start]
            let nameStart = rest.index(after: start)
            guard let end = rest[nameStart...].firstIndex(of: "%") else {
                // A lone "%" is just a character.
                literal += rest[start...]
                rest = ""
                break
            }
            let name = rest[nameStart..<end].lowercased()
            if let token = Self.tokens.first(where: { $0.name == name }) {
                if !literal.isEmpty {
                    parts.append(.literal(literal))
                    literal = ""
                }
                parts.append(.field(token.field))
            } else {
                error = error ?? "Unknown placeholder “%\(name)%”."
                literal += rest[start...end]
            }
            rest = rest[rest.index(after: end)...]
        }
        literal += rest
        if !literal.isEmpty {
            parts.append(.literal(literal))
        }

        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter a pattern."
        } else if text.contains("/") {
            error = "File names can't contain “/”."
        }
        self.parts = parts
        self.error = error
    }

    /// The file name (with `fileExtension`) these tags give, and the fields the
    /// pattern uses that the tags lack. The name is empty if nothing is left.
    public func fileName(for tags: TagSnapshot, extension fileExtension: String) -> (name: String, missing: [LogicalField]) {
        var base = ""
        var missing: [LogicalField] = []
        for part in parts {
            switch part {
            case let .literal(text):
                base += text
            case let .field(field):
                let value = Self.value(of: field, in: tags)
                if value.isEmpty {
                    if !missing.contains(field) {
                        missing.append(field)
                    }
                } else {
                    base += value
                }
            }
        }
        base = Self.clean(base)
        if !missing.isEmpty {
            // Drop separators an empty placeholder left at either end ("- Title").
            base = base.trimmingCharacters(in: Self.separators)
        }
        guard !base.isEmpty else { return ("", missing) }

        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        // File names are limited to 255 bytes.
        while base.utf8.count + suffix.utf8.count > 255 {
            base.removeLast()
        }
        return (base + suffix, missing)
    }

    private static let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—_.,;"))

    static func value(of field: LogicalField, in tags: TagSnapshot) -> String {
        switch field {
        case .trackNumber:
            // "1" → "01", so names sort correctly.
            let number = tags.value(of: field)
            return number.count == 1 && number.allSatisfy(\.isNumber) ? "0" + number : number
        case .date:
            // Just the year of a full date such as "2001-05-03".
            let date = tags.value(of: field)
            let year = date.prefix(4)
            return year.count == 4 && year.allSatisfy(\.isNumber) ? String(year) : date
        default:
            if field.allowsMultipleValues, let key = field.simpleKey {
                return (tags.fields[key] ?? []).joined(separator: ", ")
            }
            return tags.value(of: field)
        }
    }

    /// Makes a string safe as a macOS file name: "/" can't appear, and Finder
    /// shows ":" as "/", so both become "-". Also drops control characters,
    /// leading dots (which hide files) and surrounding spaces.
    static func clean(_ name: String) -> String {
        var name = name
            .replacingOccurrences(of: ": ", with: " - ")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        name = String(name.map { $0.isNewline ? " " : $0 }.filter { character in
            !character.unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) }
        })
        name = name.trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") {
            name.removeFirst()
        }
        while let last = name.last, last == "." || last.isWhitespace {
            name.removeLast()
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}

/// What renaming one file would do.
public struct RenamePlan: Identifiable, Sendable {
    public enum Status: Sendable, Equatable {
        case rename
        case unchanged
        case skipped(String)
    }

    public var id: AudioFileItem.ID
    public var source: URL
    public var destination: URL
    public var status: Status
    /// Fields the pattern uses that this file lacks.
    public var missing: [LogicalField] = []
}

enum FileRenamer {
    /// Renames a file, never replacing another file. A change of case only
    /// ("song.flac" → "Song.flac") works on case-insensitive volumes too.
    static func move(_ source: URL, to destination: URL) throws {
        let caseOnly = isSameFile(source, destination)
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                caseOnly
                    ? Darwin.rename(sourcePath!, destinationPath!)
                    : renamex_np(sourcePath!, destinationPath!, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            let reason = code == EEXIST
                ? "A file named “\(destination.lastPathComponent)” already exists."
                : String(cString: strerror(code))
            throw TagIOError.cannotRename(source, reason: reason)
        }
    }

    static func exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        var a = stat()
        var b = stat()
        guard lstat(first.path, &a) == 0, lstat(second.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino
    }
}
