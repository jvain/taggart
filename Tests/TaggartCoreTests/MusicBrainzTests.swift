import Foundation
import Testing
@testable import TaggartCore

/// Answers requests with canned responses, in order, and records them.
actor FakeTransport: HTTPTransport {
    private var responses: [(status: Int, body: Data)]
    private(set) var requests: [URLRequest] = []
    private(set) var times: [ContinuousClock.Instant] = []

    init(_ responses: [(status: Int, body: Data)]) {
        self.responses = responses
    }

    nonisolated func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await respond(to: request)
    }

    private func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        times.append(.now)
        let (status, body) = responses.isEmpty ? (500, Data()) : responses.removeFirst()
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("MusicBrainz")
struct MusicBrainzTests {
    func client(_ responses: [(status: Int, body: Data)]) -> (MusicBrainzClient, FakeTransport) {
        let transport = FakeTransport(responses)
        return (MusicBrainzClient(transport: transport, interval: .milliseconds(50), retryDelay: .milliseconds(50)), transport)
    }

    @Test func searchesReleases() async throws {
        let (client, transport) = client([(200, try fixtureData("musicbrainz-search.json"))])
        let releases = try await client.searchReleases(album: "OK Computer", artist: "Radiohead")
        #expect(releases.count == 5)
        let first = try #require(releases.first)
        #expect(first.title == "OK Computer")
        #expect(first.artist == "Radiohead")
        #expect(first.score == 100)
        #expect(first.trackCount == 12)
        #expect(first.formatSummary == "CD")
        #expect(first.labelSummary.contains("7243 8 55229 2 5"))
        #expect(releases[2].formatSummary == "2×12\" Vinyl")
        #expect(releases[4].trackCount == 15)

        let request = try #require(await transport.requests.first)
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.hasPrefix("Taggart/"))
        #expect(userAgent.hasSuffix(" ( https://github.com/jvain/taggart )"))
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(request.url?.path == "/ws/2/release")
        #expect(items.contains(URLQueryItem(name: "query", value: "release:(OK Computer) AND artist:(Radiohead)")))
        #expect(items.contains(URLQueryItem(name: "fmt", value: "json")))
    }

    @Test func looksUpReleases() async throws {
        let (client, transport) = client([(200, try fixtureData("musicbrainz-release-2cd.json"))])
        let release = try await client.release(id: "abc")
        #expect(release.formatSummary == "2×CD")
        #expect(release.trackCount == 15)
        #expect(release.tracks.count == 15)
        #expect(release.media?[1].title == "Karma Police")
        let karma = release.tracks[12]
        #expect(karma.medium.position == 2)
        #expect(karma.track.position == 1)
        #expect(karma.track.title == "Karma Police")
        #expect(karma.track.artistCredit?.text == "Radiohead")
        #expect(release.releaseGroup?.primaryType == "Album")
        #expect(release.labelInfo?.first?.label?.name == "Parlophone")

        let single = try JSONDecoder().decode(MBRelease.self, from: fixtureData("musicbrainz-release.json"))
        #expect(single.coverArtArchive?.front == true)
        #expect(single.tracks.first?.track.recording.isrcs?.isEmpty == false)
        #expect(single.tracks.first?.track.length == 284400)

        let path = await transport.requests.first?.url?.path
        #expect(path == "/ws/2/release/abc")
    }

    @Test func waitsBetweenRequestsAndRetriesWhenBusy() async throws {
        let search = try fixtureData("musicbrainz-search.json")
        let (client, transport) = client([(503, Data()), (200, search), (200, search)])
        _ = try await client.searchReleases(album: "A", artist: "")
        _ = try await client.searchReleases(album: "B", artist: "")
        let times = await transport.times
        #expect(times.count == 3)
        for (earlier, later) in zip(times, times.dropFirst()) {
            #expect(later - earlier >= .milliseconds(45))
        }

        let (busy, _) = self.client([(503, Data()), (503, Data()), (503, Data())])
        await #expect(throws: MusicBrainzError.busy) { try await busy.searchReleases(album: "A", artist: "") }
        let (missing, _) = self.client([(404, Data())])
        await #expect(throws: MusicBrainzError.notFound) { try await missing.release(id: "x") }
        let (garbled, _) = self.client([(200, Data("<html>".utf8))])
        await #expect(throws: MusicBrainzError.unreadable) { try await garbled.release(id: "x") }
    }

    @Test func buildsQueries() {
        #expect(MusicBrainzClient.searchQuery(album: "OK Computer", artist: "") == "release:(OK Computer)")
        #expect(MusicBrainzClient.searchQuery(album: "", artist: " AC/DC ") == "artist:(AC\\/DC)")
        #expect(MusicBrainzClient.searchQuery(album: "Rock AND Roll (Live)!", artist: "")
            == "release:(Rock and Roll \\(Live\\)\\!)")
        #expect(MusicBrainzClient.searchQuery(album: " ", artist: "") == "")
    }

    @Test func findsReleaseIDsInLinks() {
        let id = "4b3d18cc-8937-36f4-8de0-481088be58e6"
        #expect(MusicBrainzClient.releaseID(in: id) == id)
        #expect(MusicBrainzClient.releaseID(in: "https://musicbrainz.org/release/\(id.uppercased())/discids") == id)
        #expect(MusicBrainzClient.releaseID(in: "https://musicbrainz.org/release-group/\(id)") == nil)
        #expect(MusicBrainzClient.releaseID(in: "OK Computer") == nil)
    }

    @Test func coverArtAddresses() {
        #expect(CoverArtArchive.frontURL(release: "r1", size: .large).absoluteString == "https://coverartarchive.org/release/r1/front-1200")
        #expect(CoverArtArchive.frontURL(releaseGroup: "g1", size: .original).absoluteString
            == "https://coverartarchive.org/release-group/g1/front")
    }
}

@Suite("Track matching")
struct TrackMatchingTests {
    let single: MBRelease
    let double: MBRelease

    init() throws {
        single = try JSONDecoder().decode(MBRelease.self, from: fixtureData("musicbrainz-release.json"))
        double = try JSONDecoder().decode(MBRelease.self, from: fixtureData("musicbrainz-release-2cd.json"))
    }

    func file(disc: Int? = nil, track: Int? = nil, title: String = "", name: String = "file", seconds: Double = 0) -> TrackMatcher.File {
        TrackMatcher.File(id: UUID(), disc: disc, track: track, title: title, name: name, duration: seconds)
    }

    /// The titles the files were matched to, in file order ("—" if none).
    func titles(_ files: [TrackMatcher.File], _ release: MBRelease) -> [String] {
        let matches = TrackMatcher.match(files, to: release)
        return files.map { matches[$0.id].map { release.tracks[$0].track.title } ?? "—" }
    }

    @Test func matchesByTrackNumbers() {
        // Numbers win over wrong titles; list order doesn't matter.
        let files = [file(track: 3, title: "x"), file(track: 1, title: "y"), file(track: 2, title: "z")]
        #expect(titles(files, single) == ["Subterranean Homesick Alien", "Airbag", "Paranoid Android"])
    }

    @Test func matchesDiscsByNumberOrStraightThrough() {
        #expect(titles([file(disc: 2, track: 1), file(disc: 1, track: 1)], double) == ["Karma Police", "Airbag"])
        // Numbered 1–15 across both discs, without disc numbers.
        #expect(titles([file(track: 13), file(track: 14), file(track: 1)], double) == ["Karma Police", "A Reminder", "Airbag"])
    }

    @Test func matchesUntaggedFilesByName() {
        let files = [file(name: "02 Paranoid Android"), file(name: "Airbag"), file(name: "12 - The Tourist")]
        #expect(titles(files, single) == ["Paranoid Android", "Airbag", "The Tourist"])
    }

    @Test func matchesByTitleAndDuration() {
        // Remastered titles and slightly different lengths still match.
        let files = [file(title: "Let Down (Remastered)", seconds: 299), file(title: "Karma police", seconds: 264)]
        #expect(titles(files, single) == ["Let Down", "Karma Police"])
    }

    @Test func fallsBackToListOrder() throws {
        // No numbers or titles: the same count and matching lengths pair them in order.
        let lengths = single.tracks.map { Double($0.track.length ?? 0) / 1000 }
        let files = lengths.map { file(name: "track", seconds: $0 + 1) }
        #expect(titles(files, single) == single.tracks.map(\.track.title))
    }

    @Test func leavesDoubtfulFilesUnmatched() {
        let files = [file(track: 1, title: "Airbag"), file(title: "Something Else Entirely", name: "bonus", seconds: 1000)]
        #expect(titles(files, single) == ["Airbag", "—"])
    }

    @Test func comparesTitles() {
        #expect(TrackMatcher.normalized("Paranoid Android (Remastered)") == "paranoid android remastered")
        #expect(TrackMatcher.normalized("Ääni & Öljy") == "aani oljy")
        #expect(TrackMatcher.similarity("airbag", "airbag") == 1)
        #expect(TrackMatcher.similarity("airbag remastered", "airbag") == 0.9)
        #expect(TrackMatcher.similarity("lucky", "the tourist") < 0.3)
        #expect(TrackMatcher.leadingNumber("07 Lucky") == 7)
        #expect(TrackMatcher.leadingNumber("2024 Remix") == nil)
        #expect(TrackMatcher.withoutLeadingNumber("07 - Lucky") == "Lucky")
    }
}

@Suite("MusicBrainz tagging")
struct MusicBrainzTaggingTests {
    let release: MBRelease
    let double: MBRelease

    init() throws {
        release = try JSONDecoder().decode(MBRelease.self, from: fixtureData("musicbrainz-release.json"))
        double = try JSONDecoder().decode(MBRelease.self, from: fixtureData("musicbrainz-release-2cd.json"))
    }

    /// basic.flac (track 3), basic.mp3 (track 5) and cover.flac (no number) in one folder.
    @MainActor
    func library() async throws -> (Library, [AudioFileItem.ID]) {
        let first = try fixture("basic.flac")
        for name in ["basic.mp3", "cover.flac"] {
            try FileManager.default.moveItem(at: fixture(name), to: first.deletingLastPathComponent().appendingPathComponent(name))
        }
        let library = Library()
        await library.add([first.deletingLastPathComponent()])
        return (library, library.items.map(\.id))
    }

    func tags(_ release: MBRelease, track: Int, options: MusicBrainzOptions = MusicBrainzOptions(),
              from fields: [String: [String]] = [:], format: AudioFormat = .flac) -> [String: [String]] {
        var snapshot = TagSnapshot(fields: fields)
        release.apply(track: track, options: options, to: &snapshot, format: format)
        return snapshot.fields
    }

    @Test func setsPicardsTags() {
        let fields = tags(release, track: 1, from: ["DISCNUMBER": ["1"], "DISCTOTAL": ["2"], "CUSTOM_KEY": ["keep me"], "BARCODE": ["old"]])
        #expect(fields["TITLE"] == ["Paranoid Android"])
        #expect(fields["ARTIST"] == ["Radiohead"])
        #expect(fields["ARTISTS"] == nil)
        #expect(fields["ALBUM"] == ["OK Computer"])
        #expect(fields["ALBUMARTIST"] == ["Radiohead"])
        #expect(fields["TRACKNUMBER"] == ["2"])
        #expect(fields["TRACKTOTAL"] == ["12"])
        // A single disc gets no disc number; tags the release lacks are removed.
        #expect(fields["DISCNUMBER"] == nil && fields["DISCTOTAL"] == nil)
        #expect(fields["DATE"] == ["1997"])
        #expect(fields["ORIGINALDATE"] == ["1997"])
        #expect(fields["RELEASETYPE"] == ["album"])
        #expect(fields["RELEASESTATUS"] == ["official"])
        #expect(fields["MEDIA"] == ["CD"])
        #expect(fields["CATALOGNUMBER"] == ["7243 8 55229 2 5"])
        #expect(fields["BARCODE"] != ["old"])
        #expect(fields["ISRC"]?.isEmpty == false)
        #expect(fields["MUSICBRAINZ_ALBUMID"] == [release.id])
        #expect(fields["MUSICBRAINZ_TRACKID"] == [release.tracks[1].track.recording.id])
        #expect(fields["MUSICBRAINZ_RELEASETRACKID"] == [release.tracks[1].track.id])
        #expect(fields["MUSICBRAINZ_ARTISTID"] == ["a74b1b7f-71a5-4011-9441-d0b5e4122711"])
        #expect(fields["CUSTOM_KEY"] == ["keep me"])
    }

    @Test func followsTheOptions() {
        var options = MusicBrainzOptions()
        options.yearOnly = false
        #expect(tags(release, track: 0, options: options)["DATE"] == [release.date!])

        var idsOnly = MusicBrainzOptions()
        idsOnly.titlesAndArtists = false
        idsOnly.numbers = false
        idsOnly.date = false
        idsOnly.releaseDetails = false
        let fields = tags(release, track: 0, options: idsOnly, from: ["TITLE": ["Mine"]])
        #expect(fields["TITLE"] == ["Mine"])
        #expect(fields.keys.allSatisfy { $0 == "TITLE" || $0.hasPrefix("MUSICBRAINZ_") })
    }

    @Test func numbersDiscsAndTheirTitles() {
        let karma = tags(double, track: 12, format: .mp3)
        #expect(karma["TRACKNUMBER"] == ["1/3"])
        #expect(karma["DISCNUMBER"] == ["2/2"])
        #expect(karma["DISCSUBTITLE"] == ["Karma Police"])
    }

    @Test @MainActor func plansAppliesAndSaves() async throws {
        let (library, ids) = try await library()
        // The test files' titles are made up, and they're a second long: a
        // file whose number fits but whose title and length don't is left
        // unmatched (it's likely from another release).
        #expect(library.matchTracks(ids, to: release).isEmpty)
        // Like real rips, give them their titles.
        library.apply(.setField(.title, "Subterranean Homesick Alien"), to: [ids[0]], undoManager: nil)
        library.apply(.setField(.title, "Let Down"), to: [ids[1]], undoManager: nil)
        let matches = library.matchTracks(ids, to: release)
        // basic.flac is track 3, basic.mp3 track 5; cover.flac ("Covered", no number) doesn't fit.
        #expect(matches[ids[0]] == 2)
        #expect(matches[ids[1]] == 4)
        #expect(matches[ids[2]] == nil)

        let cover = try newArtwork()
        let plan = library.planMusicBrainz(release, matches: matches, options: MusicBrainzOptions(), cover: cover, order: ids)
        #expect(plan.fileCount == 2)
        let flacChanges = plan.changes.filter { $0.itemID == ids[0] }
        #expect(flacChanges.first { $0.label == "Album" }?.after == "OK Computer")
        #expect(flacChanges.first { $0.label == "Cover" }?.after == "32 × 32")

        let undo = UndoManager()
        undo.groupsByEvent = false
        library.applyFormat(plan, actionName: "MusicBrainz Tags", undoManager: undo)
        #expect(undo.undoActionName == "MusicBrainz Tags")
        #expect(library.item(ids[1])?.title == "Let Down")
        #expect(library.item(ids[2])?.isDirty == false)
        #expect(library.thumbnails[cover.digest] != nil)

        #expect(await library.save(undoManager: nil).isEmpty)
        let mp3 = try TagIO.read(try #require(library.item(ids[1])).url).snapshot
        #expect(mp3.value(of: .trackNumber) == "5")
        #expect(mp3.value(of: .trackTotal) == "12")
        #expect(mp3.fields["MUSICBRAINZ_TRACKID"] == [release.tracks[4].track.recording.id])
        #expect(mp3.fields["MUSICBRAINZ_ALBUMID"] == [release.id])
        #expect(mp3.primaryArtwork?.digest == cover.digest)
    }

    @Test @MainActor func suggestsWhatToSearchFor() async throws {
        let (library, ids) = try await library()
        library.apply(.setField(.album, "OK Computer"), to: [ids[0], ids[1]], undoManager: nil)
        let hints = library.lookupHints(for: ids)
        #expect(hints.album == "OK Computer")
        #expect(["Artist One; Artist Two", "Mp3 Artist"].contains(hints.artist))
        library.apply(.setField(.albumArtist, "Radiohead"), to: [ids[2]], undoManager: nil)
        #expect(library.lookupHints(for: ids).artist == "Radiohead")
    }
}
