import Darwin
import Foundation

/// A file name pattern such as "%track% - %title%". "/" in the pattern makes
/// folders ("%artist%/%album%/%track% - %title%"), relative to a base folder.
/// The file's extension is kept, and characters that don't belong in file
/// names are replaced (including "/" in tag values).
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
        /// A "/" in the pattern: the end of a folder name.
        case folder
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
        func flushLiteral() {
            // Literal text may contain "/": split it into folder breaks.
            for (index, piece) in literal.split(separator: "/", omittingEmptySubsequences: false).enumerated() {
                if index > 0 {
                    parts.append(.folder)
                }
                if !piece.isEmpty {
                    parts.append(.literal(String(piece)))
                }
            }
            literal = ""
        }
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
                flushLiteral()
                parts.append(.field(token.field))
            } else {
                error = error ?? "Unknown placeholder “%\(name)%”."
                literal += rest[start...end]
            }
            rest = rest[rest.index(after: end)...]
        }
        literal += rest
        flushLiteral()

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            error = "Enter a pattern."
        } else if trimmed.hasPrefix("/") {
            error = "Folders are created relative to the destination: remove the leading “/”."
        } else if trimmed.hasSuffix("/") {
            error = "The pattern must end with a file name, not “/”."
        } else if text.contains("//") {
            error = "The pattern has an empty folder name (“//”)."
        }
        self.parts = parts
        self.error = error
    }

    /// Whether the pattern puts files into folders.
    public var createsFolders: Bool { parts.contains(.folder) }

    /// The relative path ("Artist/Album/01 - Title.flac", or just a file name)
    /// these tags give, with `fileExtension` added, and the fields the pattern
    /// uses that the tags lack. The path is empty if missing tags leave a file
    /// or folder name empty.
    public func relativePath(for tags: TagSnapshot, extension fileExtension: String) -> (path: String, missing: [LogicalField]) {
        var components: [String] = []
        var missing: [LogicalField] = []
        var current = ""
        var currentMissesField = false
        func finishComponent() {
            var name = Self.clean(current)
            if currentMissesField {
                // Drop separators an empty placeholder left at either end ("- Title").
                name = name.trimmingCharacters(in: Self.separators)
            }
            components.append(name)
            current = ""
            currentMissesField = false
        }
        for part in parts {
            switch part {
            case let .literal(text):
                current += text
            case let .field(field):
                let value = Self.value(of: field, in: tags)
                if value.isEmpty {
                    currentMissesField = true
                    if !missing.contains(field) {
                        missing.append(field)
                    }
                } else {
                    current += value
                }
            case .folder:
                finishComponent()
            }
        }
        finishComponent()
        guard !components.contains("") else { return ("", missing) }

        // Names are limited to 255 bytes; the extension counts for the file name.
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        for index in components.indices {
            let reserved = index == components.count - 1 ? suffix.utf8.count : 0
            while components[index].utf8.count + reserved > 255 {
                components[index].removeLast()
            }
        }
        components[components.count - 1] += suffix
        return (components.joined(separator: "/"), missing)
    }

    static let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—_.,;"))

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
    /// The new name, with any new folders, relative to the destination folder.
    public var relativePath: String
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
            let reason = switch code {
            case EEXIST: "A file named “\(destination.lastPathComponent)” already exists."
            case EXDEV: "Files can't be moved to another disk; choose a folder on the same disk."
            default: String(cString: strerror(code))
            }
            throw TagIOError.cannotRename(source, reason: reason)
        }
    }

    /// Creates the folder `url` will go in, if needed. Returns the folders that
    /// were created, outermost first.
    static func createParentFolders(of url: URL) throws -> [URL] {
        var missing: [URL] = []
        var folder = url.deletingLastPathComponent()
        while !exists(folder) {
            missing.insert(folder, at: 0)
            folder = folder.deletingLastPathComponent()
        }
        if let innermost = missing.last {
            do {
                try FileManager.default.createDirectory(at: innermost, withIntermediateDirectories: true)
            } catch {
                throw TagIOError.cannotRename(url, reason: "The folder “\(innermost.lastPathComponent)” couldn't be created.")
            }
        }
        return missing
    }

    /// Removes `folders` if they're empty (a Finder .DS_Store doesn't count),
    /// then their parents while those are empty too, deepest first. Never
    /// removes the home folder, its standard folders, or a disk's top level.
    static func removeFoldersLeftEmpty(_ folders: Set<URL>) {
        for start in folders.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            var folder = start.standardizedFileURL
            while isRemovableWhenEmpty(folder), removeIfEmpty(folder) {
                folder = folder.deletingLastPathComponent()
            }
        }
    }

    private static func removeIfEmpty(_ folder: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              contents.allSatisfy({ $0 == ".DS_Store" })
        else { return false }
        if !contents.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(".DS_Store"))
        }
        return folder.withUnsafeFileSystemRepresentation { rmdir($0!) } == 0
    }

    /// False for folders that must stay even when empty.
    static func isRemovableWhenEmpty(_ folder: URL) -> Bool {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        // "/", "/Users", "/Users/name", "/Volumes/Disk" and such.
        guard path.split(separator: "/").count > 2, !protectedFolders.contains(path) else { return false }
        return (try? folder.resourceValues(forKeys: [.isVolumeKey]).isVolume) != true
    }

    private static let protectedFolders: Set<String> = {
        let manager = FileManager.default
        let standard: [FileManager.SearchPathDirectory] = [
            .desktopDirectory, .documentDirectory, .downloadsDirectory, .musicDirectory, .moviesDirectory,
            .picturesDirectory, .sharedPublicDirectory, .libraryDirectory, .applicationDirectory,
        ]
        let urls = [manager.homeDirectoryForCurrentUser] + standard.flatMap { manager.urls(for: $0, in: .userDomainMask) }
        return Set(urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
    }()

    /// Removes those of `folders` that are empty, innermost first.
    static func removeEmptyFolders(_ folders: [URL]) {
        for folder in folders.reversed() {
            _ = folder.withUnsafeFileSystemRepresentation { rmdir($0!) }
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
