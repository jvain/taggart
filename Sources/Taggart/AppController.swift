import AppKit
import SwiftUI
import TaggartCore
import UniformTypeIdentifiers

/// App-wide state and actions shared by the window, menus and app delegate.
@MainActor
@Observable
final class AppController {
    let library = Library()
    var selection = Set<AudioFileItem.ID>()
    var alert: AppAlert?
    var renameRequest: RenameRequest?
    /// The file list cell being edited in place, if any.
    var editingCell: EditingCell?
    var tagsFromNamesRequest: TagsFromNamesRequest?
    var formatTagsRequest: FormatTagsRequest?
    var trackNumbersRequest: TrackNumbersRequest?
    var musicBrainzRequest: MusicBrainzRequest?
    /// Tags taken with Copy Tags, kept until the next copy (or quit).
    var copiedTags: CopiedTags?
    /// True while a cover is being downloaded from the web.
    var isDownloadingArtwork = false

    /// The main window's undo manager and window opener, captured from its environment.
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored var openWindow: OpenWindowAction?

    /// The file types the Open panel offers, from the supported extensions.
    static let audioTypes: [UTType] = Array(Set(FileScanner.supportedExtensions.compactMap { UTType(filenameExtension: $0) }))

    /// The list's rows in their displayed order, shared with the file table.
    let sortedRows = SortedRows()

    var selectedItems: [AudioFileItem] { library.items(selection) }

    /// The selected files in the order the list shows them.
    var orderedSelection: [AudioFileItem.ID] {
        var ordered: [AudioFileItem.ID] = sortedRows.current.compactMap { selection.contains($0.id) ? $0.id : nil }
        if ordered.count < selection.count {
            // Not shown yet: after the shown ones, in the order they were added.
            let shown = Set(ordered)
            ordered += library.items(selection).map(\.id).filter { !shown.contains($0) }
        }
        return ordered
    }

    // MARK: Files

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = Self.audioTypes + [.folder]
        panel.message = "Choose audio files (FLAC, MP3, M4A, Ogg Vorbis, Opus, WAV, AIFF, WavPack, APE, WMA), or folders containing them."
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        Task {
            let failures = await library.add(urls)
            if !failures.isEmpty {
                alert = AppAlert(
                    title: failures.count == 1 ? "A file couldn't be opened" : "\(failures.count) files couldn't be opened",
                    messages: failures
                )
            }
        }
    }

    func removeSelected() {
        let dirty = selectedItems.filter(\.isDirty).count
        if dirty > 0 {
            let alert = NSAlert()
            alert.messageText = dirty == 1
                ? "Remove a file with unsaved changes?"
                : "Remove \(dirty) files with unsaved changes?"
            alert.informativeText = "Their changes will be lost. The files themselves aren't deleted."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        library.remove(selection)
        selection = []
    }

    func revealSelectedInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.url))
    }

    // MARK: Editing

    func apply(_ edit: TagEdit, to ids: Set<AudioFileItem.ID>) {
        library.apply(edit, to: ids, undoManager: undoManager)
    }

    func revertSelected() {
        let ids = selection
        Task { await library.revert(ids, undoManager: undoManager) }
    }

    /// Saves all modified files; returns whether every save succeeded.
    @discardableResult
    func save() async -> Bool {
        library.id3v2Version = Preferences.id3v2Version
        library.keepModificationDates = Preferences.keepModificationDates
        library.writeInPlace = Preferences.writeTagsInPlace
        let failures = await library.save(undoManager: undoManager)
        if !failures.isEmpty {
            alert = AppAlert(
                title: failures.count == 1 ? "A file couldn't be saved" : "\(failures.count) files couldn't be saved",
                messages: failures
            )
        }
        return failures.isEmpty
    }

    // MARK: Renaming

    func showRenameSheet() {
        guard !selection.isEmpty else { return }
        renameRequest = RenameRequest(ids: selection)
    }

    func rename(_ plans: [RenamePlan], removeFoldersLeftEmpty: Bool = false) {
        let failures = library.rename(plans, removeFoldersLeftEmpty: removeFoldersLeftEmpty, undoManager: undoManager)
        if !failures.isEmpty {
            alert = AppAlert(
                title: failures.count == 1 ? "A file couldn't be renamed" : "\(failures.count) files couldn't be renamed",
                messages: failures
            )
        }
    }

    // MARK: Tags from file names

    func showTagsFromNamesSheet() {
        guard !selection.isEmpty else { return }
        tagsFromNamesRequest = TagsFromNamesRequest(ids: selection)
    }

    func applyTagsFromNames(_ plans: [TagsFromNamePlan]) {
        library.applyTagsFromNames(plans, undoManager: undoManager)
    }

    // MARK: Format Tags

    func showFormatTagsSheet() {
        guard !selection.isEmpty else { return }
        formatTagsRequest = FormatTagsRequest(ids: orderedSelection)
    }

    /// Runs saved steps on the selected files without the preview (⌘Z undoes it).
    func runFormatSteps(_ list: FormatStepList) {
        switch library.planFormat(list.steps, in: orderedSelection) {
        case let .success(plan):
            applyFormat(plan)
        case let .failure(error):
            alert = AppAlert(title: "“\(list.name)” can't be run", messages: [error.message])
        }
    }

    func applyFormat(_ plan: FormatPlan) {
        let failures = library.applyFormat(plan, undoManager: undoManager)
        if !failures.isEmpty {
            alert = AppAlert(
                title: failures.count == 1 ? "A file couldn't be renamed" : "\(failures.count) files couldn't be renamed",
                messages: failures
            )
        }
    }

    // MARK: MusicBrainz

    func showMusicBrainzSheet() {
        guard !selection.isEmpty else { return }
        musicBrainzRequest = MusicBrainzRequest(ids: orderedSelection)
    }

    func applyMusicBrainz(_ plan: FormatPlan) {
        library.applyFormat(plan, actionName: "MusicBrainz Tags", undoManager: undoManager)
    }

    // MARK: Track numbers

    func showTrackNumbersSheet() {
        guard !selection.isEmpty else { return }
        trackNumbersRequest = TrackNumbersRequest(ids: orderedSelection)
    }

    func applyTrackNumbers(_ ids: [AudioFileItem.ID], numbering: TrackNumbering) {
        library.applyTrackNumbers(ids, numbering: numbering, undoManager: undoManager)
    }

    // MARK: Copying tags

    func copyTags() {
        let ids = orderedSelection
        guard !ids.isEmpty else { return }
        // Cleared first, so a quick paste can't use the previous copy.
        copiedTags = nil
        Task {
            do {
                copiedTags = try await library.copyTags(ids)
            } catch {
                alert = AppAlert(title: "The tags couldn't be copied", messages: [error.localizedDescription])
            }
        }
    }

    /// Pastes copied tags onto the selected files: one file's tags onto all
    /// of them, or several files' tags onto as many files, in list order.
    func pasteTags() {
        guard let copiedTags else { return }
        let ids = orderedSelection
        guard copiedTags.canPaste(onto: ids.count) else {
            let count = copiedTags.files.count
            alert = AppAlert(
                title: "Select \(count) files to paste the tags onto",
                messages: ["The tags were copied from \(count) files. They're pasted in list order, the first file's tags onto the first selected file and so on. To paste the same tags onto any number of files, copy them from one file."]
            )
            return
        }
        library.pasteTags(copiedTags, to: ids, undoManager: undoManager)
    }

    // MARK: Artwork

    func chooseArtwork(for ids: Set<AudioFileItem.ID>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a cover image."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setArtwork(for: ids) { try ArtworkImage.artwork(contentsOf: url, maxPixelSize: Preferences.coverSizeLimit) }
    }

    /// Pastes an image, an image file, or a copied image address ("Copy Image
    /// Address" in a browser), which is downloaded.
    func pasteArtwork(for ids: Set<AudioFileItem.ID>) {
        if let data = Pasteboard.imageData() {
            setArtwork(for: ids) { try ArtworkImage.artwork(from: data, maxPixelSize: Preferences.coverSizeLimit) }
        } else if let url = Pasteboard.webURL() {
            downloadArtwork(from: url, for: ids)
        } else {
            NSSound.beep()
        }
    }

    /// Downloads an image and sets it as the cover of the files that were
    /// selected when the download began.
    func downloadArtwork(from url: URL, for ids: Set<AudioFileItem.ID>) {
        isDownloadingArtwork = true
        Task {
            defer { isDownloadingArtwork = false }
            do {
                apply(.setFrontCover(try await ArtworkImage.download(from: url, maxPixelSize: Preferences.coverSizeLimit)), to: ids)
            } catch {
                alert = AppAlert(title: "The image couldn't be downloaded", messages: [error.localizedDescription])
            }
        }
    }

    func setArtwork(for ids: Set<AudioFileItem.ID>, _ make: () throws -> Artwork) {
        do {
            apply(.setFrontCover(try make()), to: ids)
        } catch {
            alert = AppAlert(title: "The image couldn't be used", messages: [error.localizedDescription])
        }
    }

    func exportArtwork(_ artwork: Artwork, from url: URL) {
        let panel = NSSavePanel()
        let ext = ArtworkImage.fileExtension(forMimeType: artwork.mimeType)
        panel.nameFieldStringValue = "cover.\(ext)"
        if let type = UTType(mimeType: artwork.mimeType) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                let data = try await Self.data(of: artwork, in: url)
                try data.write(to: destination, options: .atomic)
            } catch {
                alert = AppAlert(title: "The artwork couldn't be exported", messages: [error.localizedDescription])
            }
        }
    }

    @concurrent
    private nonisolated static func data(of artwork: Artwork, in url: URL) async throws -> Data {
        try TagIO.data(of: artwork, in: url)
    }

    // MARK: Quitting

    func showMainWindow() {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            openWindow?(id: TaggartApp.mainWindowID)
        }
    }

    /// Asks whether to save before quitting when there are unsaved changes.
    func shouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        let count = library.dirtyItems.count
        guard count > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = count == 1
            ? "Save changes to 1 file before quitting?"
            : "Save changes to \(count) files before quitting?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                let saved = await save()
                if !saved {
                    showMainWindow()
                }
                app.reply(toApplicationShouldTerminate: saved)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            showMainWindow()
            return .terminateCancel
        default:
            return .terminateNow
        }
    }
}

struct RenameRequest: Identifiable {
    let id = UUID()
    var ids: Set<AudioFileItem.ID>
}

struct TagsFromNamesRequest: Identifiable {
    let id = UUID()
    var ids: Set<AudioFileItem.ID>
}

struct FormatTagsRequest: Identifiable {
    let id = UUID()
    /// In list order.
    var ids: [AudioFileItem.ID]
}

struct MusicBrainzRequest: Identifiable {
    let id = UUID()
    /// In list order.
    var ids: [AudioFileItem.ID]
}

struct TrackNumbersRequest: Identifiable {
    let id = UUID()
    /// In list order.
    var ids: [AudioFileItem.ID]
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var messages: [String]
}

enum Preferences {
    static let id3v2VersionKey = "id3v2Version"
    static let keepModificationDatesKey = "keepModificationDates"
    static let writeTagsInPlaceKey = "writeTagsInPlace"
    static let shrinkCoversKey = "shrinkCovers"
    static let maxCoverSizeKey = "maxCoverSize"
    static let defaultMaxCoverSize = 1024
    static let coverSizeRange = 64...10_000

    /// The largest width or height for a newly set cover, or nil to keep
    /// covers as they are. Shrinking is off by default, so covers only change
    /// when the user has asked for it.
    static var coverSizeLimit: Int? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: shrinkCoversKey) else { return nil }
        let size = defaults.integer(forKey: maxCoverSizeKey)
        return size > 0 ? size.clamped(to: coverSizeRange) : defaultMaxCoverSize
    }

    /// Off by default: the safe save (via a copy) is the default.
    static var writeTagsInPlace: Bool {
        UserDefaults.standard.bool(forKey: writeTagsInPlaceKey)
    }

    static var keepModificationDates: Bool {
        UserDefaults.standard.bool(forKey: keepModificationDatesKey)
    }

    static var id3v2Version: ID3v2WriteVersion {
        ID3v2WriteVersion(rawValue: UserDefaults.standard.integer(forKey: id3v2VersionKey)) ?? .keep
    }
}

enum Pasteboard {
    /// Image bytes from the general pasteboard: an image file, or image data.
    static func imageData() -> Data? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first,
           let data = try? Data(contentsOf: url) {
            return data
        }
        let types: [NSPasteboard.PasteboardType] = [.init(UTType.jpeg.identifier), .png, .tiff]
        return types.lazy.compactMap { pasteboard.data(forType: $0) }.first
    }

    /// A web address on the general pasteboard, as a URL or as text.
    static func webURL() -> URL? {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = urls + [text.flatMap { URL(string: $0) }].compactMap { $0 }
        return candidates.first(where: isWebURL)
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
