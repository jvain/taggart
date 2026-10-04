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
    /// Whether saving keeps the files' modification dates.
    public var keepModificationDates = false
    /// Whether saving writes into the files directly, skipping the safety copy
    /// (faster on external drives and network shares; see `TagIO.write`).
    public var writeInPlace = false
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

    /// The genres used in the loaded files, most used first.
    public var genres: [String] {
        var counts: [String: Int] = [:]
        for item in items {
            for genre in item.edited.fields["GENRE"] ?? [] where !genre.isEmpty {
                counts[genre, default: 0] += 1
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.key)
    }
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

    /// Every tag in the selected files, sorted by name, with how it compares
    /// across them.
    public func rawTags(for ids: Set<AudioFileItem.ID>) -> [RawTag] {
        let selected = items(ids)
        let keys = Set(selected.flatMap(\.edited.fields.keys))
        return keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { key in
            let values = selected.map { $0.edited.fields[key] }
            if let first = values.first ?? nil, values.allSatisfy({ $0 == first }) {
                return RawTag(key: key, state: .uniform(first))
            }
            return RawTag(key: key, state: .mixed(count: values.filter { $0 != nil }.count))
        }
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

        let options = SaveOptions(id3v2Version: id3v2Version, keepModificationDate: keepModificationDates,
                                  inPlace: writeInPlace)
        let thumbnails = thumbnails
        let results = await withTaskGroup(of: (Int, Result<LoadedFile, Error>).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    (index, await Self.perform(job, options: options, thumbnails: thumbnails))
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

    private struct SaveOptions: Sendable {
        var id3v2Version: ID3v2WriteVersion
        var keepModificationDate: Bool
        var inPlace: Bool
    }

    @concurrent
    private nonisolated static func perform(
        _ job: SaveJob,
        options: SaveOptions,
        thumbnails: ThumbnailCache
    ) async -> Result<LoadedFile, Error> {
        Result {
            try TagIO.write(
                job.edited,
                original: job.original,
                to: job.url,
                expectedModificationDate: job.modificationDate,
                id3v2Version: options.id3v2Version,
                keepModificationDate: options.keepModificationDate,
                inPlace: options.inPlace
            )
            return try TagIO.read(job.url, thumbnails: thumbnails)
        }
    }

    // MARK: Format Tags

    /// What running the steps on the files in `ids` (in this order) would do.
    /// Fails if a step can't be used (e.g. a bad regular expression).
    public func planFormat(_ steps: [FormatStep], in ids: [AudioFileItem.ID]) -> Result<FormatPlan, FormatStepError> {
        FormatProgram.compile(steps).map { program in
            var plan = FormatPlan()
            var changes: [AudioFileItem.ID: [FormatChange]] = [:]
            var renames: [RenamePlan] = []
            let items = ids.compactMap { itemsByID[$0] }
            for item in items {
                let name = item.url.deletingPathExtension().lastPathComponent
                var state = FormatState(tags: item.edited, name: name, format: item.info.format)
                program.run(&state)
                if state.tags != item.edited {
                    plan.tags[item.id] = state.tags
                    changes[item.id] = FormatPlan.differences(from: item.edited, to: state.tags).map {
                        FormatChange(itemID: item.id, url: item.url, label: $0.label, before: $0.before, after: $0.after)
                    }
                }
                if state.name != name {
                    let cleaned = RenamePattern.clean(state.name)
                    let fileExtension = item.url.pathExtension
                    let path = cleaned.isEmpty ? "" : fileExtension.isEmpty ? cleaned : "\(cleaned).\(fileExtension)"
                    renames.append(renamePlan(for: item, path: path, base: item.url.deletingLastPathComponent(),
                                              emptyReason: "The new name would be empty."))
                }
            }
            plan.renames = Self.skippingDuplicates(renames)
            for rename in plan.renames where rename.status != .unchanged {
                guard let item = itemsByID[rename.id] else { continue }
                var problem: String?
                if case let .skipped(reason) = rename.status {
                    problem = reason
                }
                changes[item.id, default: []].append(FormatChange(
                    itemID: item.id, url: item.url, label: "File Name", before: item.url.lastPathComponent,
                    after: rename.relativePath, problem: problem
                ))
            }
            plan.changes = items.flatMap { changes[$0.id] ?? [] }
            return plan
        }
    }

    /// Makes the planned changes, as one undoable action: tag changes are
    /// pending until saved, like other edits; renames happen right away.
    /// Returns an error message for each file that couldn't be renamed.
    @discardableResult
    public func applyFormat(_ plan: FormatPlan, undoManager: UndoManager?) -> [String] {
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.setActionName("Format Tags")
            undoManager?.endUndoGrouping()
        }
        setEdited(plan.tags, actionName: "Format Tags", undoManager: undoManager)
        return rename(plan.renames, undoManager: undoManager)
    }

    // MARK: Track numbers

    /// What numbering the files in `ids` would do, numbering them in this order.
    public func planTrackNumbers(_ ids: [AudioFileItem.ID], numbering: TrackNumbering) -> [TrackNumberChange] {
        numbered(ids, numbering).map { item, tags in
            TrackNumberChange(id: item.id, url: item.url, before: TrackNumberChange.display(item.edited),
                              after: TrackNumberChange.display(tags))
        }
    }

    /// Numbers the files in `ids` in this order, as one undoable edit.
    public func applyTrackNumbers(_ ids: [AudioFileItem.ID], numbering: TrackNumbering, undoManager: UndoManager?) {
        var snapshots: [AudioFileItem.ID: TagSnapshot] = [:]
        for (item, tags) in numbered(ids, numbering) where tags != item.edited {
            snapshots[item.id] = tags
        }
        setEdited(snapshots, actionName: "Number Tracks", undoManager: undoManager)
    }

    private func numbered(_ ids: [AudioFileItem.ID], _ numbering: TrackNumbering) -> [(AudioFileItem, TagSnapshot)] {
        let targets = ids.compactMap { itemsByID[$0] }
        return zip(targets, numbering.numbers(for: targets.map(\.url))).map { item, numbers in
            var tags = item.edited
            tags.set(.trackNumber, to: numbers.number, format: item.info.format)
            if let total = numbers.total {
                tags.set(.trackTotal, to: total, format: item.info.format)
            }
            return (item, tags)
        }
    }

    // MARK: Copying tags

    /// Copies the tags and pictures of the files in `ids`, in this order. The
    /// pictures' bytes are read from the files (each distinct picture once).
    public func copyTags(_ ids: [AudioFileItem.ID]) async throws -> CopiedTags {
        try await Self.copy(ids.compactMap { itemsByID[$0] }.map { CopySource(url: $0.url, tags: $0.edited) })
    }

    private struct CopySource: Sendable {
        var url: URL
        var tags: TagSnapshot
    }

    @concurrent
    private nonisolated static func copy(_ sources: [CopySource]) async throws -> CopiedTags {
        var pictures: [SHA256.Digest: Data] = [:]
        let files = try sources.map { source in
            var tags = source.tags
            tags.artwork = try tags.artwork.map { artwork in
                let data = try pictures[artwork.digest] ?? TagIO.data(of: artwork, in: source.url)
                pictures[artwork.digest] = data
                var copy = artwork
                copy.source = .new(data)
                return copy
            }
            return tags
        }
        return CopiedTags(files: files)
    }

    /// Replaces the tags and pictures of the files in `ids` with copied ones,
    /// as one undoable edit. One file's tags go onto every file; several
    /// files' tags go onto as many files, in this order. Does nothing if the
    /// counts don't match (see `CopiedTags.canPaste(onto:)`).
    public func pasteTags(_ copied: CopiedTags, to ids: [AudioFileItem.ID], undoManager: UndoManager?) {
        guard copied.canPaste(onto: ids.count) else { return }
        var snapshots: [AudioFileItem.ID: TagSnapshot] = [:]
        for (index, id) in ids.enumerated() {
            guard let item = itemsByID[id] else { continue }
            let source = copied.files[copied.files.count == 1 ? 0 : index]
            for artwork in source.artwork {
                if case let .new(data) = artwork.source {
                    thumbnails.add(data, digest: artwork.digest)
                }
            }
            let tags = source.converted(to: item.info.format)
            if tags != item.edited {
                snapshots[id] = tags
            }
        }
        setEdited(snapshots, actionName: "Paste Tags", undoManager: undoManager)
    }

    // MARK: Tags from file names

    /// What reading tags from the names of the files in `ids` would do, in list order.
    public func planTagsFromNames(_ ids: Set<AudioFileItem.ID>, pattern: TagsFromNamePattern,
                                  underscoresAsSpaces: Bool = false) -> [TagsFromNamePlan] {
        let fields = pattern.fields
        return items(ids).map { item in
            TagsFromNamePlan(id: item.id, url: item.url,
                             tags: pattern.tags(from: item.url, underscoresAsSpaces: underscoresAsSpaces), fields: fields)
        }
    }

    /// Sets the tags read from file names, as one undoable edit. Files whose
    /// names didn't match are left alone; so are fields the pattern doesn't use.
    public func applyTagsFromNames(_ plans: [TagsFromNamePlan], undoManager: UndoManager?) {
        var snapshots: [AudioFileItem.ID: TagSnapshot] = [:]
        for plan in plans {
            guard let tags = plan.tags, let item = itemsByID[plan.id] else { continue }
            var snapshot = item.edited
            for field in LogicalField.allCases {
                if let value = tags[field] {
                    snapshot.set(field, to: value, format: item.info.format)
                }
            }
            if snapshot != item.edited {
                snapshots[item.id] = snapshot
            }
        }
        setEdited(snapshots, actionName: "Tags from File Names", undoManager: undoManager)
    }

    // MARK: Renaming

    /// What renaming the files in `ids` with `pattern` would do, in list order.
    /// New names (and folders) go in `baseFolder`, or by default in each
    /// file's current folder. Files that would collide with an existing file
    /// or with each other are skipped rather than renamed.
    public func planRename(_ ids: Set<AudioFileItem.ID>, pattern: RenamePattern, baseFolder: URL? = nil) -> [RenamePlan] {
        guard pattern.error == nil else { return [] }
        let plans = items(ids).map { item in
            let (path, missing) = pattern.relativePath(for: item.edited, extension: item.url.pathExtension)
            return renamePlan(
                for: item, path: path, base: baseFolder ?? item.url.deletingLastPathComponent(), missing: missing,
                emptyReason: "No \(missing.map(\.label).joined(separator: " or ")) in this file's tags, which leaves a name empty."
            )
        }
        return Self.skippingDuplicates(plans)
    }

    /// Renaming one file to `path` (relative to `base`): skipped if the path
    /// is empty or the name is taken by another file.
    private func renamePlan(for item: AudioFileItem, path: String, base: URL, missing: [LogicalField] = [],
                            emptyReason: String) -> RenamePlan {
        let destination = base.appendingPathComponent(path)
        let status: RenamePlan.Status =
            if path.isEmpty {
                .skipped(emptyReason)
            } else if destination.standardizedFileURL.path == item.url.standardizedFileURL.path {
                .unchanged
            } else if FileRenamer.exists(destination) && !FileRenamer.isSameFile(item.url, destination) {
                .skipped("A file with this name already exists.")
            } else {
                .rename
            }
        return RenamePlan(id: item.id, source: item.url, destination: destination, status: status,
                          relativePath: path, missing: missing)
    }

    /// Skips renames that would give several files the same name.
    private static func skippingDuplicates(_ plans: [RenamePlan]) -> [RenamePlan] {
        // Default APFS volumes ignore case and Unicode normalization.
        func key(_ url: URL) -> String { url.path.precomposedStringWithCanonicalMapping.lowercased() }
        var plans = plans
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
    ///
    /// With `removeFoldersLeftEmpty`, folders that files moved out of are
    /// removed if that left them empty (see `FileRenamer.removeFoldersLeftEmpty`).
    public func rename(_ plans: [RenamePlan], removeFoldersLeftEmpty: Bool = false, undoManager: UndoManager?) -> [String] {
        rename(plans, removingEmptyFolders: [], removeFoldersLeftEmpty: removeFoldersLeftEmpty, undoManager: undoManager)
    }

    private func rename(
        _ plans: [RenamePlan],
        removingEmptyFolders cleanup: [URL],
        removeFoldersLeftEmpty: Bool = false,
        undoManager: UndoManager?
    ) -> [String] {
        var reversed: [RenamePlan] = []
        var vacatedFolders = Set<URL>()
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
                if plan.source.deletingLastPathComponent() != plan.destination.deletingLastPathComponent() {
                    vacatedFolders.insert(plan.source.deletingLastPathComponent())
                }
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
        // Undo moves the files back, recreating these folders as needed.
        if removeFoldersLeftEmpty {
            FileRenamer.removeFoldersLeftEmpty(vacatedFolders)
        }
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
