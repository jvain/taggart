import CryptoKit
import Foundation
import Observation

/// One loaded file. Used only on the main actor (through `Library`).
@Observable
public final class AudioFileItem: Identifiable {
    /// Stable for the item's lifetime, unlike `url`, which changes on rename.
    public let id = UUID()
    public fileprivate(set) var url: URL
    public private(set) var info: AudioInfo
    /// The tags as they are on disk.
    public fileprivate(set) var original: TagSnapshot
    /// The tags including unsaved edits.
    public fileprivate(set) var edited: TagSnapshot
    public fileprivate(set) var modificationDate: Date?
    /// The last load or save error, if any.
    public fileprivate(set) var error: String?

    init(_ loaded: LoadedFile) {
        url = loaded.url
        info = loaded.info
        original = loaded.snapshot
        edited = loaded.snapshot
        modificationDate = loaded.modificationDate
    }

    fileprivate func reload(from loaded: LoadedFile, keepingEdits: Bool = false) {
        info = loaded.info
        original = loaded.snapshot
        if !keepingEdits {
            edited = loaded.snapshot
        }
        modificationDate = loaded.modificationDate
        error = nil
    }

    public var isDirty: Bool { edited != original }

    public func value(_ field: LogicalField) -> String { edited.value(of: field) }

    // Sortable column values.
    public var fileName: String { url.lastPathComponent }
    public var title: String { value(.title) }
    public var artist: String { value(.artist) }
    public var album: String { value(.album) }
    public var albumArtist: String { value(.albumArtist) }
    public var year: String { value(.date) }
    public var genre: String { value(.genre) }
    public var trackSortKey: Int { Int(value(.trackNumber)) ?? Int.max }
    public var discSortKey: Int { Int(value(.discNumber)) ?? Int.max }
    public var duration: TimeInterval { info.duration }
    public var formatSummary: String { info.summary }
    public var hasArtwork: Bool { !edited.artwork.isEmpty }
    public var artworkSortKey: Int { edited.artwork.count }
    public var dirtySortKey: Int { isDirty ? 0 : 1 }
}

/// The set of loaded files and their unsaved edits.
@MainActor
@Observable
public final class Library {
    public private(set) var items: [AudioFileItem] = []
    public var isLoading: Bool { activeLoads > 0 }
    public private(set) var isSaving = false
    /// Progress of the current load, as (done, total).
    public private(set) var loadProgress = (done: 0, total: 0)
    public var id3v2Version: ID3v2WriteVersion = .keep
    public let thumbnails = ThumbnailCache()

    @ObservationIgnored private var itemsByID: [AudioFileItem.ID: AudioFileItem] = [:]
    @ObservationIgnored private var itemsByURL: [URL: AudioFileItem] = [:]
    private var activeLoads = 0

    public init() {}

    public func item(_ id: AudioFileItem.ID) -> AudioFileItem? { itemsByID[id] }

    public func item(at url: URL) -> AudioFileItem? { itemsByURL[url] }

    /// The items with these IDs, in list order.
    public func items(_ ids: Set<AudioFileItem.ID>) -> [AudioFileItem] {
        items.filter { ids.contains($0.id) }
    }

    public var dirtyItems: [AudioFileItem] { items.filter(\.isDirty) }
    public var hasUnsavedChanges: Bool { items.contains(where: \.isDirty) }

    // MARK: Loading

    /// Loads the supported files in `urls` (descending into folders), skipping
    /// files already loaded. Returns an error message for each file that failed.
    @discardableResult
    public func add(_ urls: [URL]) async -> [String] {
        activeLoads += 1
        defer { activeLoads -= 1 }
        let files = await Self.scan(urls).filter { itemsByURL[$0] == nil }
        loadProgress = (0, files.count)

        var failures: [String] = []
        let results = await read(files) { [weak self] done in
            self?.loadProgress = (done, files.count)
        }
        for (url, result) in zip(files, results) {
            switch result {
            case let .success(loaded):
                // Another load may have added the file in the meantime.
                guard itemsByURL[url] == nil else { continue }
                let item = AudioFileItem(loaded)
                items.append(item)
                itemsByID[item.id] = item
                itemsByURL[url] = item
            case let .failure(error):
                failures.append(error.localizedDescription)
            }
        }
        return failures
    }

    /// Removes files from the list (the files themselves are untouched).
    public func remove(_ ids: Set<AudioFileItem.ID>) {
        for item in items(ids) {
            itemsByID[item.id] = nil
            itemsByURL[item.url] = nil
        }
        items.removeAll { ids.contains($0.id) }
    }

    // MARK: Editing

    public func fieldState(_ field: LogicalField, for ids: Set<AudioFileItem.ID>) -> FieldState {
        FieldState(items(ids).lazy.map { $0.value(field) })
    }

    public func artworkState(for ids: Set<AudioFileItem.ID>) -> ArtworkState {
        ArtworkState(items(ids).lazy.map(\.edited))
    }

    /// The first selected file's displayed picture, with the file holding it
    /// (embedded pictures can only be read back from their own file).
    public func primaryArtwork(in ids: Set<AudioFileItem.ID>) -> (artwork: Artwork, url: URL)? {
        for item in items(ids) {
            if let artwork = item.edited.primaryArtwork {
                return (artwork, item.url)
            }
        }
        return nil
    }

    /// Applies one edit to every file in `ids`, as one undoable action.
    public func apply(_ edit: TagEdit, to ids: Set<AudioFileItem.ID>, undoManager: UndoManager?) {
        if case let .setFrontCover(artwork) = edit, case let .new(data) = artwork.source {
            thumbnails.add(data, digest: artwork.digest)
        }
        var snapshots: [AudioFileItem.ID: TagSnapshot] = [:]
        for item in items(ids) {
            let snapshot = item.edited.applying(edit, format: item.info.format)
            if snapshot != item.edited {
                snapshots[item.id] = snapshot
            }
        }
        setEdited(snapshots, actionName: edit.actionName, undoManager: undoManager)
    }

    /// Discards unsaved edits, re-reading the files from disk so changes made by
    /// other apps are picked up. Undoable: undo re-applies the edits.
    public func revert(_ ids: Set<AudioFileItem.ID>, undoManager: UndoManager?) async {
        let targets = items(ids)
        let results = await read(targets.map(\.url))
        var snapshots: [AudioFileItem.ID: TagSnapshot] = [:]
        for (item, result) in zip(targets, results) {
            snapshots[item.id] = item.edited
            switch result {
            case let .success(loaded):
                item.reload(from: loaded)
            case let .failure(error):
                item.edited = item.original
                item.error = error.localizedDescription
            }
        }
        // `snapshots` holds the edits being discarded: register their restoration.
        let restored = snapshots.filter { id, snapshot in itemsByID[id]?.edited != snapshot }
        registerUndo(restoring: restored, actionName: "Revert", undoManager: undoManager)
    }

    private func setEdited(_ snapshots: [AudioFileItem.ID: TagSnapshot], actionName: String, undoManager: UndoManager?) {
        var previous: [AudioFileItem.ID: TagSnapshot] = [:]
        for (id, snapshot) in snapshots {
            guard let item = itemsByID[id] else { continue }
            previous[id] = item.edited
            item.edited = snapshot
        }
        registerUndo(restoring: previous, actionName: actionName, undoManager: undoManager)
    }

    private func registerUndo(restoring snapshots: [AudioFileItem.ID: TagSnapshot], actionName: String, undoManager: UndoManager?) {
        guard let undoManager, !snapshots.isEmpty else { return }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] library in
            MainActor.assumeIsolated {
                library.setEdited(snapshots, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Saving

    /// Saves every file with unsaved edits. Returns an error message for each
    /// file that failed; those stay modified. Clears the undo history.
    @discardableResult
    public func save(undoManager: UndoManager?) async -> [String] {
        let jobs = dirtyItems.map {
            SaveJob(id: $0.id, url: $0.url, original: $0.original, edited: $0.edited, modificationDate: $0.modificationDate)
        }
        guard !jobs.isEmpty else { return [] }
        isSaving = true
        defer { isSaving = false }

        let version = id3v2Version
        let thumbnails = thumbnails
        let results = await withTaskGroup(of: (Int, Result<LoadedFile, Error>).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    (index, await Self.perform(job, id3v2Version: version, thumbnails: thumbnails))
                }
            }
            var results = [Result<LoadedFile, Error>?](repeating: nil, count: jobs.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results.map { $0! }
        }

        var failures: [String] = []
        for (job, result) in zip(jobs, results) {
            guard let item = itemsByID[job.id] else { continue }
            switch result {
            case let .success(loaded):
                // Keep edits made while saving (e.g. an undo); they stay pending.
                item.reload(from: loaded, keepingEdits: item.edited != job.edited)
            case let .failure(error):
                item.error = error.localizedDescription
                failures.append(error.localizedDescription)
            }
        }
        undoManager?.removeAllActions()
        return failures
    }

    private struct SaveJob: Sendable {
        var id: AudioFileItem.ID
        var url: URL
        var original: TagSnapshot
        var edited: TagSnapshot
        var modificationDate: Date?
    }

    @concurrent
    private nonisolated static func perform(
        _ job: SaveJob,
        id3v2Version: ID3v2WriteVersion,
        thumbnails: ThumbnailCache
    ) async -> Result<LoadedFile, Error> {
        Result {
            try TagIO.write(
                job.edited,
                original: job.original,
                to: job.url,
                expectedModificationDate: job.modificationDate,
                id3v2Version: id3v2Version
            )
            return try TagIO.read(job.url, thumbnails: thumbnails)
        }
    }

    // MARK: Renaming

    /// What renaming the files in `ids` with `pattern` would do, in list order.
    /// New names (and folders) go in `baseFolder`, or by default in each
    /// file's current folder. Files that would collide with an existing file
    /// or with each other are skipped rather than renamed.
    public func planRename(_ ids: Set<AudioFileItem.ID>, pattern: RenamePattern, baseFolder: URL? = nil) -> [RenamePlan] {
        guard pattern.error == nil else { return [] }
        var plans = items(ids).map { item in
            let (path, missing) = pattern.relativePath(for: item.edited, extension: item.url.pathExtension)
            let base = baseFolder ?? item.url.deletingLastPathComponent()
            let destination = base.appendingPathComponent(path)
            let status: RenamePlan.Status =
                if path.isEmpty {
                    .skipped("No \(missing.map(\.label).joined(separator: " or ")) in this file's tags, which leaves a name empty.")
                } else if destination.standardizedFileURL.path == item.url.standardizedFileURL.path {
                    .unchanged
                } else if FileRenamer.exists(destination) && !FileRenamer.isSameFile(item.url, destination) {
                    .skipped("A file with this name already exists.")
                } else {
                    .rename
                }
            return RenamePlan(
                id: item.id,
                source: item.url,
                destination: destination,
                status: status,
                relativePath: path,
                missing: missing
            )
        }

        // Default APFS volumes ignore case and Unicode normalization.
        func key(_ url: URL) -> String { url.path.precomposedStringWithCanonicalMapping.lowercased() }
        var counts: [String: Int] = [:]
        for plan in plans where plan.status == .rename {
            counts[key(plan.destination), default: 0] += 1
        }
        for index in plans.indices where plans[index].status == .rename && counts[key(plans[index].destination)]! > 1 {
            plans[index].status = .skipped("Another selected file would get the same name.")
        }
        return plans
    }

    /// Renames (or moves) files on disk right away; renames aren't staged like
    /// tag edits. Creates folders as needed. Undoable: undo moves the files
    /// back and removes the folders it created, if they're empty.
    /// Returns an error message for each file that couldn't be renamed.
    @discardableResult
    public func rename(_ plans: [RenamePlan], undoManager: UndoManager?) -> [String] {
        rename(plans, removingEmptyFolders: [], undoManager: undoManager)
    }

    private func rename(_ plans: [RenamePlan], removingEmptyFolders cleanup: [URL], undoManager: UndoManager?) -> [String] {
        var reversed: [RenamePlan] = []
        var createdFolders: [URL] = []
        var failures: [String] = []
        for plan in plans where plan.status == .rename {
            guard let item = itemsByID[plan.id], item.url == plan.source else { continue }
            do {
                let created = try FileRenamer.createParentFolders(of: plan.destination)
                do {
                    try FileRenamer.move(plan.source, to: plan.destination)
                } catch {
                    FileRenamer.removeEmptyFolders(created)
                    throw error
                }
                createdFolders += created
                itemsByURL[plan.source] = nil
                item.url = plan.destination
                itemsByURL[plan.destination] = item
                reversed.append(RenamePlan(
                    id: plan.id,
                    source: plan.destination,
                    destination: plan.source,
                    status: .rename,
                    relativePath: plan.source.lastPathComponent
                ))
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        FileRenamer.removeEmptyFolders(cleanup)
        if let undoManager, !reversed.isEmpty {
            undoManager.registerUndo(withTarget: self) { [weak undoManager] library in
                MainActor.assumeIsolated {
                    _ = library.rename(reversed, removingEmptyFolders: createdFolders, undoManager: undoManager)
                }
            }
            undoManager.setActionName(reversed.count == 1 ? "Rename File" : "Rename Files")
        }
        return failures
    }

    // MARK: Background work

    @concurrent
    private nonisolated static func scan(_ urls: [URL]) async -> [URL] {
        FileScanner.audioFiles(in: urls)
    }

    @concurrent
    private nonisolated static func readFile(_ url: URL, thumbnails: ThumbnailCache) async -> Result<LoadedFile, Error> {
        Result { try TagIO.read(url, thumbnails: thumbnails) }
    }

    /// Reads files in parallel (a few at a time), preserving order.
    private func read(_ urls: [URL], progress: ((Int) -> Void)? = nil) async -> [Result<LoadedFile, Error>] {
        let thumbnails = thumbnails
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
        return await withTaskGroup(of: (Int, Result<LoadedFile, Error>).self) { group in
            var results = [Result<LoadedFile, Error>?](repeating: nil, count: urls.count)
            var next = 0
            var done = 0
            func addNext() {
                guard next < urls.count else { return }
                let index = next
                let url = urls[index]
                next += 1
                group.addTask { (index, await Self.readFile(url, thumbnails: thumbnails)) }
            }
            for _ in 0..<width {
                addNext()
            }
            for await (index, result) in group {
                results[index] = result
                done += 1
                progress?(done)
                addNext()
            }
            return results.map { $0! }
        }
    }
}
