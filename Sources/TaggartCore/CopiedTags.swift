import Foundation

/// Tags copied from files, to paste onto others: one file's tags paste onto
/// any number of files, several files' tags onto as many files, in order.
/// Pictures carry their bytes, since a pasted picture can't be read back from
/// the file it came from.
public struct CopiedTags: Sendable {
    /// Each copied file's tags, in list order.
    public var files: [TagSnapshot]

    public init(files: [TagSnapshot]) {
        self.files = files
    }

    /// Whether these tags can be pasted onto this many files.
    public func canPaste(onto count: Int) -> Bool {
        files.count == 1 ? count > 0 : files.count == count
    }
}

extension TagSnapshot {
    /// These tags as a file of `format` stores them. Copied between formats,
    /// Track and Disc numbers and totals move between one "3/12" tag (MP3,
    /// M4A) and separate number and total tags (FLAC, Ogg).
    func converted(to format: AudioFormat) -> TagSnapshot {
        let numberFields: [LogicalField] = [.trackNumber, .trackTotal, .discNumber, .discTotal]
        let values = numberFields.map { value(of: $0) }
        var copy = self
        for keys in [NumberKeys.track, .disc] {
            copy.fields[keys.number] = nil
            for total in keys.totals {
                copy.fields[total] = nil
            }
        }
        for (field, value) in zip(numberFields, values) where !value.isEmpty {
            copy.set(field, to: value, format: format)
        }
        return copy
    }
}
