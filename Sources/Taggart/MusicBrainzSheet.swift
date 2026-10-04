import AppKit
import SwiftUI
import TaggartCore

/// The state of a MusicBrainz lookup: the search, the chosen release, which
/// file goes with which track, and the cover.
@MainActor
@Observable
final class MusicBrainzLookup {
    enum Page {
        case search
        case release
    }

    enum CoverState: Equatable {
        case off
        case loading
        case loaded
        case missing
        case failed(String)
    }

    var page = Page.search
    var album = ""
    var artist = ""
    private(set) var results: [MBRelease] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var isLoadingRelease = false
    /// The last search or lookup error.
    private(set) var message: String?
    var selectedResultID: MBRelease.ID?
    private(set) var release: MBRelease?
    /// Each matched file's track, as an index into `release.tracks`.
    private(set) var matches: [AudioFileItem.ID: Int] = [:]
    var options = MusicBrainzSettings.options {
        didSet { MusicBrainzSettings.options = options }
    }
    /// Nil: don't set a cover.
    var coverSize = MusicBrainzSettings.coverSize {
        didSet {
            MusicBrainzSettings.coverSize = coverSize
            loadCover()
        }
    }
    private(set) var cover: Artwork?
    private(set) var coverState = CoverState.off

    /// In list order.
    private(set) var ids: [AudioFileItem.ID] = []
    @ObservationIgnored private weak var library: Library?
    @ObservationIgnored private var coverTask: Task<Void, Never>?

    func start(ids: [AudioFileItem.ID], library: Library) {
        guard self.library == nil else { return }
        self.ids = ids
        self.library = library
        (album, artist) = library.lookupHints(for: ids)
        if !album.isEmpty || !artist.isEmpty {
            Task { await search() }
        }
    }

    func search() async {
        if let id = MusicBrainzClient.releaseID(in: album) ?? MusicBrainzClient.releaseID(in: artist) {
            await open(id: id)
            return
        }
        guard !isSearching, !(album.isEmpty && artist.isEmpty) else { return }
        isSearching = true
        message = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            let found = try await MusicBrainzClient.shared.searchReleases(album: album, artist: artist)
            // Releases with as many tracks as there are files first, otherwise in MusicBrainz's order.
            let count = ids.count
            results = found.enumerated()
                .sorted { a, b in
                    let aFits = a.element.trackCount == count
                    let bFits = b.element.trackCount == count
                    return aFits != bFits ? aFits : a.offset < b.offset
                }
                .map(\.element)
            selectedResultID = results.first?.id
        } catch {
            results = []
            message = error.localizedDescription
        }
    }

    func openSelected() async {
        if let selectedResultID {
            await open(id: selectedResultID)
        }
    }

    /// Looks up the release's tracks, matches the files to them and shows it.
    func open(id: String) async {
        guard !isLoadingRelease else { return }
        isLoadingRelease = true
        message = nil
        defer { isLoadingRelease = false }
        do {
            let release = try await MusicBrainzClient.shared.release(id: id)
            self.release = release
            matches = library?.matchTracks(ids, to: release) ?? [:]
            page = .release
            loadCover()
        } catch {
            message = error.localizedDescription
        }
    }

    func back() {
        coverTask?.cancel()
        page = .search
    }

    private func loadCover() {
        coverTask?.cancel()
        cover = nil
        guard let release, let coverSize else {
            coverState = .off
            return
        }
        coverState = .loading
        coverTask = Task {
            do {
                let artwork = try await CoverArtArchive.front(of: release, size: coverSize, maxPixelSize: Preferences.coverSizeLimit)
                guard !Task.isCancelled else { return }
                cover = artwork
                coverState = artwork == nil ? .missing : .loaded
            } catch {
                guard !Task.isCancelled else { return }
                coverState = .failed(error.localizedDescription)
            }
        }
    }

    var plan: FormatPlan {
        guard let release, let library else { return FormatPlan() }
        return library.planMusicBrainz(release, matches: matches, options: options,
                                       cover: coverState == .loaded ? cover : nil, order: ids)
    }

    /// The file paired with the track at `index`, if any.
    func file(forTrack index: Int) -> AudioFileItem.ID? {
        matches.first { $0.value == index }?.key
    }

    /// Pairs a file with a track (or leaves the track without a file). The
    /// file's previous track, and the track's previous file, lose their pair.
    func assign(_ file: AudioFileItem.ID?, toTrack index: Int) {
        if let previous = self.file(forTrack: index) {
            matches[previous] = nil
        }
        if let file {
            matches[file] = index
        }
    }

    var unmatchedFiles: [AudioFileItem.ID] {
        ids.filter { matches[$0] == nil }
    }
}

/// Remembered lookup settings.
enum MusicBrainzSettings {
    private static let optionsKey = "musicBrainzOptions"
    private static let coverSizeKey = "musicBrainzCoverSize"

    static var options: MusicBrainzOptions {
        get {
            UserDefaults.standard.data(forKey: optionsKey)
                .flatMap { try? JSONDecoder().decode(MusicBrainzOptions.self, from: $0) } ?? MusicBrainzOptions()
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: optionsKey)
        }
    }

    /// 1200 pixels by default; nil when the user chose not to set covers.
    static var coverSize: CoverArtArchive.Size? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: coverSizeKey) else { return .large }
            return CoverArtArchive.Size(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue ?? "none", forKey: coverSizeKey)
        }
    }
}

/// Finds the selected files' album on MusicBrainz and tags them from it.
struct MusicBrainzSheet: View {
    /// In list order.
    let ids: [AudioFileItem.ID]
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @ViewState private var lookup = MusicBrainzLookup()

    var body: some View {
        Group {
            switch lookup.page {
            case .search:
                SearchPage(lookup: lookup, fileCount: ids.count, cancel: { dismiss() })
            case .release:
                ReleasePage(lookup: lookup, cancel: { dismiss() }, apply: { plan in
                    controller.applyMusicBrainz(plan)
                    dismiss()
                })
            }
        }
        .padding(20)
        .frame(minWidth: 820, idealWidth: 900, minHeight: 620, idealHeight: 700)
        .onAppear {
            lookup.start(ids: ids, library: controller.library)
        }
    }
}

private struct SearchPage: View {
    @Bindable var lookup: MusicBrainzLookup
    let fileCount: Int
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(fileCount == 1 ? "Look Up 1 File on MusicBrainz" : "Look Up \(fileCount) Files on MusicBrainz")
                .font(.title3.bold())

            HStack(spacing: 8) {
                TextField("Album", text: $lookup.album, prompt: Text("Album, or a MusicBrainz release link"))
                    .textFieldStyle(.roundedBorder)
                TextField("Artist", text: $lookup.artist, prompt: Text("Artist"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                Button("Search") { Task { await lookup.search() } }
                    .disabled(lookup.isSearching || (lookup.album.isEmpty && lookup.artist.isEmpty))
            }
            .onSubmit { Task { await lookup.search() } }

            Table(lookup.results, selection: $lookup.selectedResultID) {
                TableColumn("") { release in
                    if release.trackCount == fileCount {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("As many tracks as files selected")
                    }
                }
                .width(18)
                TableColumn("Title") { release in
                    HStack(spacing: 4) {
                        Text(release.title)
                        if let note = release.disambiguation, !note.isEmpty {
                            Text("(\(note))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(release.title)
                }
                .width(min: 140, ideal: 220)
                TableColumn("Artist") { release in
                    Text(release.artist)
                }
                .width(min: 80, ideal: 140)
                TableColumn("Date") { release in
                    Text(release.date ?? "")
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 80)
                TableColumn("Country") { release in
                    Text(release.country ?? "")
                }
                .width(min: 30, ideal: 50)
                TableColumn("Format") { release in
                    Text(release.formatSummary)
                }
                .width(min: 50, ideal: 90)
                TableColumn("Tracks") { release in
                    Text(String(release.trackCount))
                        .monospacedDigit()
                }
                .width(min: 36, ideal: 44)
                TableColumn("Label") { release in
                    Text(release.labelSummary)
                        .help(release.labelSummary)
                }
                .width(min: 80, ideal: 160)
            }
            .contextMenu(forSelectionType: MBRelease.ID.self) { _ in
            } primaryAction: { selection in
                if let id = selection.first {
                    lookup.selectedResultID = id
                    Task { await lookup.open(id: id) }
                }
            }

            HStack(spacing: 6) {
                if lookup.isSearching || lookup.isLoadingRelease {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(status)
                    .foregroundStyle(lookup.message == nil ? Color.secondary : Color.red)
            }
            .font(.callout)

            HStack {
                Text("Data from MusicBrainz, the open music encyclopedia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Next") { Task { await lookup.openSelected() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(lookup.selectedResultID == nil || lookup.isLoadingRelease)
            }
        }
    }

    private var status: String {
        if let message = lookup.message {
            return message
        }
        if lookup.isLoadingRelease {
            return "Getting the release's tracks…"
        }
        if lookup.isSearching {
            return "Searching…"
        }
        if lookup.results.isEmpty {
            return lookup.hasSearched ? "No releases found. Try fewer words, or only the album or the artist." : "Enter an album and artist, then search."
        }
        let fitting = lookup.results.filter { $0.trackCount == fileCount }.count
        var text = lookup.results.count == 1 ? "1 release." : "\(lookup.results.count) releases."
        if fitting > 0 {
            text += " The \(fitting == 1 ? "one" : "\(fitting)") marked ✓ \(fitting == 1 ? "has" : "have") as many tracks as files selected."
        }
        return text + " Choose one and click Next."
    }
}

private struct ReleasePage: View {
    @Bindable var lookup: MusicBrainzLookup
    let cancel: () -> Void
    let apply: (FormatPlan) -> Void
    @Environment(AppController.self) private var controller
    @ViewState private var showsChanges = false

    var body: some View {
        let plan = lookup.plan
        VStack(alignment: .leading, spacing: 14) {
            if let release = lookup.release {
                header(release)
                Picker("Show", selection: $showsChanges) {
                    Text("Tracks").tag(false)
                    Text(plan.changes.isEmpty ? "Changes" : "Changes (\(plan.changes.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if showsChanges {
                    ChangesTable(changes: plan.changes)
                } else {
                    tracksTable(release)
                }
                Text(matchSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(unmatchedNames)
                optionsGrid
            }
            HStack {
                Button("Back") { lookup.back() }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(plan.fileCount == 1 ? "Apply to 1 File" : "Apply to \(plan.fileCount) Files") { apply(plan) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.fileCount == 0 || lookup.coverState == .loading)
            }
        }
    }

    private func header(_ release: MBRelease) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CoverView(artwork: lookup.cover, state: lookup.coverState)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(release.title)
                    .font(.title3.bold())
                Text(release.artist)
                let details = [release.date, release.country, release.formatSummary, release.labelSummary,
                               release.trackCount == 1 ? "1 track" : "\(release.trackCount) tracks"]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                Text(details.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                Link("Open in MusicBrainz", destination: release.webURL)
                    .font(.callout)
            }
            Spacer()
        }
    }

    private struct TrackRow: Identifiable {
        var index: Int
        var medium: MBMedium
        var track: MBTrack
        var id: Int { index }
    }

    private func tracksTable(_ release: MBRelease) -> some View {
        let isMultiDisc = (release.media?.count ?? 1) > 1
        let rows = release.tracks.enumerated().map { TrackRow(index: $0.offset, medium: $0.element.medium, track: $0.element.track) }
        let files = lookup.ids.compactMap { controller.library.item($0) }
        return Table(rows) {
            TableColumn("#") { row in
                Text(isMultiDisc ? "\(row.medium.position ?? 1)-\(row.track.number ?? String(row.track.position))"
                                 : row.track.number ?? String(row.track.position))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 24, ideal: 36)
            TableColumn("Title") { row in
                Text(row.track.title)
                    .help(row.track.title)
            }
            .width(min: 120, ideal: 240)
            TableColumn("Length") { row in
                LengthCell(track: row.track, file: lookup.file(forTrack: row.index).flatMap { controller.library.item($0) })
            }
            .width(min: 50, ideal: 90)
            TableColumn("File") { row in
                Picker("File", selection: Binding(
                    get: { lookup.file(forTrack: row.index) },
                    set: { lookup.assign($0, toTrack: row.index) }
                )) {
                    Text("No file").tag(AudioFileItem.ID?.none)
                    Divider()
                    ForEach(files) { item in
                        Text(item.fileName).tag(AudioFileItem.ID?.some(item.id))
                    }
                }
                .labelsHidden()
            }
            .width(min: 160, ideal: 260)
        }
    }

    private var matchSummary: String {
        let matched = lookup.matches.count
        let unmatched = lookup.unmatchedFiles.count
        var text = "\(matched) of \(lookup.ids.count) files matched to tracks."
        if unmatched > 0 {
            text += unmatched == 1 ? " 1 file is left unchanged." : " \(unmatched) files are left unchanged."
        }
        return text + " Choose another file for a track from its menu."
    }

    private var unmatchedNames: String {
        lookup.unmatchedFiles.compactMap { controller.library.item($0)?.fileName }.joined(separator: "\n")
    }

    private var optionsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Toggle("Titles and artists", isOn: $lookup.options.titlesAndArtists)
                Toggle("Track and disc numbers", isOn: $lookup.options.numbers)
                HStack(spacing: 10) {
                    Toggle("Date", isOn: $lookup.options.date)
                    Toggle("Year only", isOn: $lookup.options.yearOnly)
                        .disabled(!lookup.options.date && !lookup.options.releaseDetails)
                }
            }
            GridRow {
                Toggle("Label, catalog number and other release details", isOn: $lookup.options.releaseDetails)
                    .help("Label, catalog number, barcode, country, release status and type, media, disc subtitle, original date and ISRC. Ones the release lacks are removed, so none are left from another release.")
                Toggle("MusicBrainz IDs", isOn: $lookup.options.identifiers)
                    .help("The IDs other apps (and later lookups) use to find the release and its tracks.")
                HStack(spacing: 6) {
                    Picker("Cover:", selection: $lookup.coverSize) {
                        Text("Don't set").tag(CoverArtArchive.Size?.none)
                        Divider()
                        ForEach(CoverArtArchive.Size.allCases) { size in
                            Text(size.label).tag(CoverArtArchive.Size?.some(size))
                        }
                    }
                    .fixedSize()
                    coverStatus
                }
            }
        }
    }

    @ViewBuilder
    private var coverStatus: some View {
        switch lookup.coverState {
        case .off, .loaded:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .missing:
            Text("None on the Cover Art Archive")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(message)
        }
    }
}

/// The track's length, and the file's when it differs by more than a few seconds.
private struct LengthCell: View {
    let track: MBTrack
    let file: AudioFileItem?

    var body: some View {
        HStack(spacing: 4) {
            Text(track.length.map { Self.format(Double($0) / 1000) } ?? "")
                .monospacedDigit()
            if let file, let length = track.length, abs(file.duration - Double(length) / 1000) > 5 {
                Text("(\(Self.format(file.duration)))")
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .help("The file is \(Self.format(file.duration)) long: it may not be this track.")
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
    }
}

private struct CoverView: View {
    let artwork: Artwork?
    let state: MusicBrainzLookup.CoverState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if state == .loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var image: NSImage? {
        guard let artwork, case let .new(data) = artwork.source else { return nil }
        return NSImage(data: data)
    }
}

/// Every tag change, file by file.
struct ChangesTable: View {
    let changes: [FormatChange]

    var body: some View {
        Table(changes) {
            TableColumn("File") { change in
                Text(change.url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .help(change.url.path)
            }
            .width(min: 100, ideal: 170)
            TableColumn("Tag") { change in
                Text(change.label)
            }
            .width(min: 50, ideal: 140)
            TableColumn("Before") { change in
                Text(change.before)
                    .foregroundStyle(.secondary)
                    .help(change.before)
            }
            TableColumn("After") { change in
                if change.after.isEmpty {
                    Text("Removed")
                        .italic()
                        .foregroundStyle(.secondary)
                } else {
                    Text(change.after)
                        .help(change.after)
                }
            }
        }
    }
}
