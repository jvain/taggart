import Foundation

/// Finds supported audio files among opened or dropped URLs.
public enum FileScanner {
    /// FLAC, MP3, MP4 audio (AAC or ALAC; .m4b is audiobooks), Ogg Vorbis, Opus,
    /// WAV, AIFF (and AIFF-C), WavPack, Monkey's Audio and WMA.
    public static let supportedExtensions: Set<String> = [
        "flac", "mp3", "m4a", "m4b", "ogg", "oga", "opus", "wav", "aif", "aiff", "aifc", "wv", "ape", "wma",
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Supported files in `urls`, descending into folders. Symlinks are resolved,
    /// duplicates removed, and the result sorted by path.
    public static func audioFiles(in urls: [URL]) -> [URL] {
        var found = Set<URL>()
        for url in urls {
            let url = url.standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                if isSupported(url) {
                    found.insert(url)
                }
                continue
            }
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let file = enumerator?.nextObject() as? URL {
                guard isSupported(file),
                      (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { continue }
                found.insert(file.standardizedFileURL.resolvingSymlinksInPath())
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
