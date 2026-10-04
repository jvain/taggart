import Foundation
import Testing
@testable import TaggartCore

@Suite("Field states")
struct FieldStateTests {
    @Test func combinesValues() {
        #expect(FieldState([String]()) == .uniform(""))
        #expect(FieldState(["a", "a"]) == .uniform("a"))
        #expect(FieldState(["a", "b"]) == .mixed)
        #expect(FieldState(["", ""]) == .uniform(""))
        #expect(FieldState(["a", ""]) == .mixed)
    }

    @Test func combinesArtwork() throws {
        let blue = try newArtwork()
        let withCover = TagSnapshot(artwork: [blue])
        #expect(ArtworkState([TagSnapshot(), TagSnapshot()]) == .none)
        #expect(ArtworkState([withCover, withCover]) == .uniform(blue))
        #expect(ArtworkState([withCover, TagSnapshot()]) == .mixed)
    }
}

@Suite("Genres")
struct GenreTests {
    func completions(_ text: String, _ preferred: [String] = []) -> [String] {
        Genres.suggestions(for: text, preferring: preferred).map(\.completion)
    }

    @Test func hasTheStandardList() {
        #expect(Genres.standard.count >= 148)
        #expect(Genres.standard.first == "Blues")
        #expect(Genres.standard.contains("Synthpop"))
    }

    @Test func suggestsMatchingGenres() {
        // Names starting with the typed text come before names containing it.
        let rock = completions("roc")
        #expect(rock.first == "Rock")
        #expect(rock.firstIndex(of: "Rock & Roll")! < rock.firstIndex(of: "Classic Rock")!)
        // Case and accents are ignored.
        #expect(completions("JAZZ").first == "Jazz")
        // Genres from the loaded files come first, even if not standard.
        #expect(completions("ro", ["Rocksteady Dub"]).first == "Rocksteady Dub")
        #expect(completions("zzzz").isEmpty)
        #expect(completions("r").count == 12)
    }

    @Test func completesTheLastOfSeveralGenres() {
        let results = completions("Ambient; Roc")
        #expect(results.first == "Ambient; Rock")
        // Genres already in the field aren't offered again.
        #expect(!completions("Rock; Ro").contains("Rock; Rock"))
    }

    @Test func suggestsLoadedGenresBeforeTyping() {
        #expect(completions("", ["Ambient", "Jazz"]) == ["Ambient", "Jazz"])
        #expect(completions("Ambient; ", ["Ambient", "Jazz"]) == ["Ambient; Jazz"])
        #expect(completions("").isEmpty)
        // The exact genre already typed isn't suggested.
        #expect(!completions("Jazz").contains("Jazz"))
    }
}

@Suite("Tags from file names")
struct TagsFromNameTests {
    func read(_ pattern: String, _ path: String, underscores: Bool = false) -> [LogicalField: String]? {
        TagsFromNamePattern(pattern).tags(from: URL(fileURLWithPath: path), underscoresAsSpaces: underscores)
    }

    @Test func readsFileNames() {
        #expect(read("%track% - %title%", "/m/01 - Song.flac") == [.trackNumber: "1", .title: "Song"])
        // Text placeholders take as little as they can; the last one takes the rest.
        #expect(read("%track% - %title%", "/m/01 - Song - Live.mp3") == [.trackNumber: "1", .title: "Song - Live"])
        #expect(read("%artist% - %album% - %track% - %title%", "/m/Band - Record - 03 - Name.ogg")
            == [.artist: "Band", .album: "Record", .trackNumber: "3", .title: "Name"])
        // Numbers match digits only, so they need no separator.
        #expect(read("%track%%title%", "/m/07Name.flac") == [.trackNumber: "7", .title: "Name"])
        #expect(read("%year% - %album%", "/m/1999 - Record.flac") == [.date: "1999", .album: "Record"])
        #expect(read("%track% of %tracktotal% %title%", "/m/3 of 12 X.flac")
            == [.trackNumber: "3", .trackTotal: "12", .title: "X"])
        #expect(read("%track% - %title%", "/m/00 - Intro.flac") == [.trackNumber: "0", .title: "Intro"])
    }

    @Test func readsFolderNames() {
        #expect(read("%artist%/%album%/%track% - %title%", "/Music/Band/Record/03 - Song.mp3")
            == [.artist: "Band", .album: "Record", .trackNumber: "3", .title: "Song"])
        // Literal text ignores case.
        #expect(read("CD%disc%/%track% %title%", "/x/cd2/05 Name.flac") == [.discNumber: "2", .trackNumber: "5", .title: "Name"])
        #expect(read("%artist%/%album%/%title%", "/Song.flac") == nil)
    }

    @Test func skipsAndUnderscores() {
        #expect(read("%skip% - %title%", "/m/xyz - Song.flac") == [.title: "Song"])
        #expect(read("%track% - %title%", "/m/01_-_Song_Title.flac", underscores: true) == [.trackNumber: "1", .title: "Song Title"])
        #expect(read("%track% - %title%", "/m/01_-_Song_Title.flac") == nil)
    }

    @Test func reportsNonMatchingNames() {
        #expect(read("%track% - %title%", "/m/Song.mp3") == nil)
        #expect(read("%track% - %title%", "/m/A1 - Song.mp3") == nil)
    }

    @Test func rejectsBadPatterns() {
        #expect(TagsFromNamePattern("%nope% - %title%").error == "Unknown placeholder “%nope%”.")
        #expect(TagsFromNamePattern("%skip%").error != nil)
        #expect(TagsFromNamePattern(" ").error != nil)
        #expect(TagsFromNamePattern("%artist%/").error != nil)
        #expect(TagsFromNamePattern("%artist%//%title%").error != nil)
        #expect(TagsFromNamePattern("(%track%) [%title%]").error == nil)
        #expect(read("(%track%) [%title%]", "/m/(4) [Name].flac") == [.trackNumber: "4", .title: "Name"])
    }
}

@Suite("Format steps")
struct FormatStepTests {
    func step(_ kind: FormatStep.Kind, _ configure: (inout FormatStep) -> Void = { _ in }) -> FormatStep {
        var step = FormatStep(kind)
        configure(&step)
        return step
    }

    /// Runs steps on a file with these fields (and file name).
    func run(_ steps: [FormatStep], _ fields: [String: [String]], name: String = "file",
             format: AudioFormat = .flac) -> FormatState? {
        guard case let .success(program) = FormatProgram.compile(steps) else { return nil }
        var state = FormatState(tags: TagSnapshot(fields: fields), name: name, format: format)
        program.run(&state)
        return state
    }

    func replace(_ find: String, _ replacement: String, matchCase: Bool = false, regex: Bool = false) -> FormatStep {
        step(.replace) {
            $0.find = find
            $0.replacement = replacement
            $0.matchCase = matchCase
            $0.regularExpression = regex
        }
    }

    @Test func replacesText() {
        let title = ["TITLE": ["A FEAT. B"]]
        #expect(run([replace("feat.", "ft.")], title)?.tags.fields["TITLE"] == ["A ft. B"])
        #expect(run([replace("feat.", "ft.", matchCase: true)], title)?.tags.fields["TITLE"] == ["A FEAT. B"])
        // Regular expressions, with groups; "." is a wildcard there.
        #expect(run([replace("^(\\d+)\\. ", "$1 - ", regex: true)], ["TITLE": ["01. Song"]])?.tags.fields["TITLE"] == ["01 - Song"])
        #expect(run([replace("\\s*\\(remaster(ed)?\\)", "", regex: true)], ["TITLE": ["Song (Remastered)"]])?.tags.fields["TITLE"] == ["Song"])
    }

    func problem(_ steps: [FormatStep]) -> String? {
        if case let .failure(error) = FormatProgram.compile(steps) { error.message } else { nil }
    }

    @Test func rejectsUnusableSteps() {
        #expect(problem([replace("", "x")]) == "Enter the text to find.")
        #expect(problem([FormatStep(.cleanUpSpaces), replace("([", "x", regex: true)]) == "Step 2: The regular expression isn't valid.")
        #expect(FormatProgram.compile([step(.setTag) { $0.pattern = " " }]).isFailure)
        #expect(FormatProgram.compile([step(.splitTag) { $0.splitPattern = "no placeholders" }]).isFailure)
        #expect(FormatProgram.compile([step(.removeTags) { $0.tagNames = " , " }]).isFailure)
        #expect(problem([step(.setTag) { $0.destination = .tag("") }]) == "Enter a tag name.")
    }

    @Test func cleansUpSpaces() {
        let spaces = FormatStep(.cleanUpSpaces)
        #expect(run([spaces], ["TITLE": ["  Too   many \t spaces  "]])?.tags.fields["TITLE"] == ["Too many spaces"])
        #expect(run([spaces], ["COMMENT": ["Line one\nLine  two "]])?.tags.fields["COMMENT"] == ["Line one\nLine two"])
    }

    @Test func changesTheChosenTarget() {
        let fields = ["TITLE": ["a song"], "ARTIST": ["an artist"], "ARTISTSORT": ["artist, an"], "TRACKNUMBER": ["1"]]
        let all = run([FormatStep(.changeCase)], fields, name: "a file")!
        #expect(all.tags.fields["TITLE"] == ["A Song"])
        #expect(all.tags.fields["ARTIST"] == ["An Artist"])
        // Tags outside the text fields, and the file name, only when chosen.
        #expect(all.tags.fields["ARTISTSORT"] == ["artist, an"])
        #expect(all.name == "a file")

        let one = run([step(.changeCase) { $0.target = .field(.artist) }], fields)!
        #expect(one.tags.fields["TITLE"] == ["a song"])
        #expect(one.tags.fields["ARTIST"] == ["An Artist"])

        let raw = run([step(.changeCase) { $0.target = .tag("ARTISTSORT"); $0.caseStyle = .uppercase }], fields)!
        #expect(raw.tags.fields["ARTISTSORT"] == ["ARTIST, AN"])

        let name = run([step(.changeCase) { $0.target = .fileName }], fields, name: "01 - a song")!
        #expect(name.name == "01 - A Song")
        #expect(name.tags.fields == fields)
    }

    @Test func emptiedValuesAreRemoved() {
        let state = run([replace("Ambient", "", matchCase: true)], ["GENRE": ["Ambient"], "TITLE": ["Ambient Song"]])!
        #expect(state.tags.fields["GENRE"] == nil)
        #expect(state.tags.fields["TITLE"] == [" Song"])
    }

    @Test func setsATagFromAPattern() {
        let fields = ["ARTIST": ["Band"], "TITLE": ["Song"], "TRACKNUMBER": ["3/12"], "ALBUMARTIST": ["Other"]]
        let albumArtist = step(.setTag) // Album Artist = %artist%, only if empty
        #expect(run([albumArtist], fields)?.tags.fields["ALBUMARTIST"] == ["Other"])
        #expect(run([albumArtist], ["ARTIST": ["A", "B"]])?.tags.fields["ALBUMARTIST"] == ["A", "B"])
        let always = step(.setTag) { $0.onlyIfEmpty = false }
        #expect(run([always], fields)?.tags.fields["ALBUMARTIST"] == ["Band"])

        // Values as they are (track 3, not 03); the file name; any tag; plain text.
        let title = step(.setTag) {
            $0.destination = .field(.title)
            $0.pattern = "%track%. %title% [%filename%] %MOOD%%nothing%"
            $0.onlyIfEmpty = false
        }
        let result = run([title], fields.merging(["MOOD": ["Calm"]]) { $1 }, name: "song file")!
        #expect(result.tags.fields["TITLE"] == ["3. Song [song file] Calm"])
        #expect(run([step(.setTag) { $0.destination = .tag("MEDIA"); $0.pattern = "Vinyl" }], fields)?.tags.fields["MEDIA"] == ["Vinyl"])
        // A pattern that comes out empty changes nothing.
        let empty = step(.setTag) { $0.destination = .field(.genre); $0.pattern = "%composer%"; $0.onlyIfEmpty = false }
        #expect(run([empty], ["GENRE": ["Jazz"]])?.tags.fields["GENRE"] == ["Jazz"])
        // File names are cleaned.
        let rename = step(.setTag) { $0.destination = .fileName; $0.pattern = "%artist%: %title%"; $0.onlyIfEmpty = false }
        #expect(run([rename], fields)?.name == "Band - Song")
        // Separators an empty placeholder leaves at either end are dropped.
        let numbered = step(.setTag) { $0.destination = .fileName; $0.pattern = "%track% %artist% - %title%"; $0.onlyIfEmpty = false }
        #expect(run([numbered], ["TITLE": ["Song"]])?.name == "Song")
        #expect(run([numbered], ["TITLE": ["Song"], "TRACKNUMBER": ["2"]])?.name == "2  - Song")
    }

    @Test func splitsATag() {
        let split = FormatStep(.splitTag) // Title → %artist% - %title%
        let state = run([split], ["TITLE": ["Band - Song - Live"]])!
        #expect(state.tags.fields["ARTIST"] == ["Band"])
        #expect(state.tags.fields["TITLE"] == ["Song - Live"])
        // No match: nothing changes.
        #expect(run([split], ["TITLE": ["Just a Song"]])?.tags.fields == ["TITLE": ["Just a Song"]])
        // "/" is ordinary text; numbers are read as numbers, in the file's format.
        let numbers = step(.splitTag) { $0.source = .tag("COMMENT"); $0.splitPattern = "Track %track%/%tracktotal%" }
        let mp3 = run([numbers], ["COMMENT": ["Track 03/12"]], format: .mp3)!
        #expect(mp3.tags.fields["TRACKNUMBER"] == ["3/12"])
    }

    @Test func removesTags() {
        let fields = ["TITLE": ["Song"], "COMMENT": ["Ripped"], "ENCODER": ["Lavf"], "TRACKNUMBER": ["3"], "TRACKTOTAL": ["12"],
                      "TOTALTRACKS": ["12"], "MOOD": ["Calm"]]
        let removed = run([FormatStep(.removeTags)], fields)!.tags.fields // Comment, ENCODER, ENCODEDBY, ENCODING
        #expect(removed.keys.sorted() == ["MOOD", "TITLE", "TOTALTRACKS", "TRACKNUMBER", "TRACKTOTAL"])
        // Fields by name cover every key they're stored under.
        let total = run([step(.removeTags) { $0.tagNames = "Track Total" }], fields)!.tags.fields
        #expect(total["TRACKTOTAL"] == nil && total["TOTALTRACKS"] == nil && total["TRACKNUMBER"] == ["3"])
        let mp3Total = run([step(.removeTags) { $0.tagNames = "track total" }], ["TRACKNUMBER": ["3/12"]], format: .mp3)!
        #expect(mp3Total.tags.fields["TRACKNUMBER"] == ["3"])

        // Keeping a total keeps the number's tag too, which can hold the total ("3/12").
        let kept = run([step(.removeTags) { $0.tagNames = "Title, Track Total, mood"; $0.keepsListedTags = true }], fields)!
        #expect(kept.tags.fields.keys.sorted() == ["MOOD", "TITLE", "TOTALTRACKS", "TRACKNUMBER", "TRACKTOTAL"])
        let keptTrack = run([step(.removeTags) { $0.tagNames = "Track"; $0.keepsListedTags = true }], fields)!
        #expect(keptTrack.tags.fields.keys.sorted() == ["TRACKNUMBER"])
    }

    @Test func runsStepsInOrder() {
        let steps = [
            FormatStep(.splitTag),
            FormatStep(.cleanUpSpaces),
            step(.changeCase) { $0.target = .textTags },
            step(.setTag) { $0.destination = .fileName; $0.pattern = "%artist% - %title%"; $0.onlyIfEmpty = false },
        ]
        let state = run(steps, ["TITLE": ["the  band -  a  song"]], name: "track01")!
        #expect(state.tags.fields["ARTIST"] == ["The Band"])
        #expect(state.tags.fields["TITLE"] == ["A Song"])
        #expect(state.name == "The Band - A Song")
    }

    @Test func savesAndLoadsSteps() throws {
        let list = FormatStepList(name: "Tidy", steps: [step(.replace) { $0.find = "x"; $0.target = .tag("MOOD") }, FormatStep(.removeTags)])
        let decoded = try JSONDecoder().decode(FormatStepList.self, from: JSONEncoder().encode(list))
        #expect(decoded == list)
        // Steps saved without newer settings get the defaults.
        let old = try JSONDecoder().decode(FormatStep.self, from: Data(#"{"kind":"changeCase","caseStyle":"uppercase"}"#.utf8))
        #expect(old.caseStyle == .uppercase)
        #expect(old.target == .textTags)
        #expect(old.keptWords.contains("DJ"))
    }
}

extension Result {
    var isFailure: Bool {
        if case .failure = self { true } else { false }
    }
}

@Suite("Track numbering")
struct TrackNumberingTests {
    let urls = ["/a/x.flac", "/a/y.flac", "/b/z.flac", "/a/w.flac"].map { URL(fileURLWithPath: $0) }

    @Test func numbersInOrder() {
        let numbers = TrackNumbering(restartsInEachFolder: false).numbers(for: urls)
        #expect(numbers.map { $0.number } == ["1", "2", "3", "4"])
        #expect(numbers.allSatisfy { $0.total == nil })
    }

    @Test func startsOverInEachFolder() {
        let numbers = TrackNumbering(setsTotal: true).numbers(for: urls)
        #expect(numbers.map { $0.number } == ["1", "2", "1", "3"])
        #expect(numbers.map { $0.total } == ["3", "3", "1", "3"])
    }

    @Test func startsAnywhereWithLeadingZeros() {
        let sameFolder = [urls[0], urls[1], urls[3]]
        let padded = TrackNumbering(start: 9, setsTotal: true, padsWithZeros: true).numbers(for: sameFolder)
        #expect(padded.map { $0.number } == ["09", "10", "11"])
        #expect(padded.map { $0.total } == ["11", "11", "11"])
        // Past 99, numbers get as many digits as the last one.
        #expect(TrackNumbering(start: 98, padsWithZeros: true).numbers(for: sameFolder).map { $0.number }
            == ["098", "099", "100"])
        #expect(TrackNumbering(start: 98).numbers(for: sameFolder).map { $0.number } == ["98", "99", "100"])
    }
}

@Suite("Raw tag names")
struct RawTagKeyTests {
    @Test func validatesNames() {
        #expect(RawTagKey.validate(" musicbrainz_trackid ") == ("MUSICBRAINZ_TRACKID", nil))
        #expect(RawTagKey.validate("My Tag").key == "MY TAG")
        #expect(RawTagKey.validate("My Tag").error == nil)
        #expect(RawTagKey.validate("  ").error != nil)
        #expect(RawTagKey.validate("A=B").error != nil)
        #expect(RawTagKey.validate("Ääni").error != nil)
    }

    @Test func suggestsCommonNames() {
        let suggestions = RawTagKey.suggestions(for: "replay", excluding: ["REPLAYGAIN_TRACK_GAIN"])
        #expect(suggestions.allSatisfy { $0.hasPrefix("REPLAYGAIN_") })
        #expect(!suggestions.contains("REPLAYGAIN_TRACK_GAIN"))
        #expect(RawTagKey.suggestions(for: "trackid", excluding: []).contains("MUSICBRAINZ_TRACKID"))
        #expect(RawTagKey.suggestions(for: "", excluding: []).isEmpty)
    }
}

@Suite("File scanning")
struct FileScannerTests {
    @Test func findsAudioFilesRecursively() throws {
        let flac = try fixture("basic.flac")
        let root = flac.deletingLastPathComponent()
        let nested = root.appendingPathComponent("Disc 2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: flac, to: nested.appendingPathComponent("Track.FLAC"))
        try Data("x".utf8).write(to: nested.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: nested.appendingPathComponent(".hidden.mp3"))

        let found = FileScanner.audioFiles(in: [root, flac]).map(\.lastPathComponent)
        #expect(found == ["basic.flac", "Track.FLAC"])
    }
}

@MainActor
@Suite("Library")
struct LibraryTests {
    /// Three files sharing one folder: basic.flac, basic.mp3, cover.flac.
    func loadedLibrary() async throws -> (Library, ids: [AudioFileItem.ID], urls: [URL]) {
        let first = try fixture("basic.flac")
        let folder = first.deletingLastPathComponent()
        for name in ["basic.mp3", "cover.flac"] {
            let source = try fixture(name)
            try FileManager.default.moveItem(at: source, to: folder.appendingPathComponent(name))
        }
        let library = Library()
        let failures = await library.add([folder])
        #expect(failures.isEmpty)
        return (library, library.items.map(\.id), library.items.map(\.url))
    }

    func undoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test func loadsFolderOnce() async throws {
        let (library, _, urls) = try await loadedLibrary()
        #expect(urls.map(\.lastPathComponent) == ["basic.flac", "basic.mp3", "cover.flac"])
        await library.add(urls)
        #expect(library.items.count == 3)
        #expect(!library.isLoading)
    }

    @Test func bulkEditUndoRedo() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let all = Set(ids)
        let undo = undoManager()
        #expect(library.fieldState(.artist, for: all) == .mixed)

        undo.beginUndoGrouping()
        library.apply(.setField(.artist, "Everyone"), to: all, undoManager: undo)
        undo.endUndoGrouping()
        #expect(library.fieldState(.artist, for: all) == .uniform("Everyone"))
        #expect(library.dirtyItems.count == 3)
        #expect(undo.undoActionName == "Edit Artist")

        undo.undo()
        #expect(library.fieldState(.artist, for: all) == .mixed)
        #expect(library.dirtyItems.isEmpty)

        undo.redo()
        #expect(library.fieldState(.artist, for: all) == .uniform("Everyone"))
    }

    @Test func coverAppliesToSelectionOnly() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let blue = try newArtwork()
        let selection: Set = [ids[0], ids[1]]
        library.apply(.setFrontCover(blue), to: selection, undoManager: nil)
        #expect(library.artworkState(for: selection) == .uniform(blue))
        #expect(library.item(ids[2])?.isDirty == false)
        #expect(library.thumbnails[blue.digest] != nil)
    }

    @Test func findsTheFileHoldingTheShownArtwork() async throws {
        let (library, ids, _) = try await loadedLibrary()
        // Only cover.flac has artwork; selecting all must still find it there.
        let source = try #require(library.primaryArtwork(in: Set(ids)))
        #expect(source.url.lastPathComponent == "cover.flac")
        #expect(source.artwork.type == .frontCover)
        let data = try TagIO.data(of: source.artwork, in: source.url)
        #expect(ArtworkImage.mimeType(of: data) == "image/png")
        #expect(library.primaryArtwork(in: [ids[0]]) == nil)
    }

    @Test func savesAndClearsUndo() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let undo = undoManager()
        undo.beginUndoGrouping()
        library.apply(.setField(.album, "Saved Album"), to: Set(ids), undoManager: undo)
        library.apply(.setFrontCover(try newArtwork()), to: [ids[1]], undoManager: undo)
        undo.endUndoGrouping()

        let failures = await library.save(undoManager: undo)
        #expect(failures.isEmpty)
        #expect(!library.hasUnsavedChanges)
        #expect(!undo.canUndo)
        for url in urls {
            #expect(try TagIO.read(url).snapshot.value(of: .album) == "Saved Album")
        }
        #expect(try TagIO.read(urls[1]).snapshot.artwork.count == 1)
    }

    @Test func comparesRawTagsAcrossFiles() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let all = library.rawTags(for: Set(ids))
        // basic.flac, basic.mp3 and cover.flac all have a different TITLE.
        #expect(all.first { $0.key == "TITLE" }?.state == .mixed(count: 3))
        // Only the two basic files have CUSTOM_KEY.
        #expect(all.first { $0.key == "CUSTOM_KEY" }?.state == .mixed(count: 2))
        let keys = all.map(\.key)
        #expect(keys == keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending })

        let two = library.rawTags(for: [ids[0], ids[1]])
        #expect(two.first { $0.key == "CUSTOM_KEY" }?.state == .uniform(["keep me"]))
        #expect(library.rawTags(for: [ids[0]]).first { $0.key == "ARTIST" }?.state == .uniform(["Artist One", "Artist Two"]))
    }

    @Test func editsRawTagsWithUndo() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let all = Set(ids)
        let undo = undoManager()
        undo.beginUndoGrouping()
        library.apply(.setTag("MOOD", ["Calm"]), to: all, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Edit MOOD")
        #expect(library.rawTags(for: all).first { $0.key == "MOOD" }?.state == .uniform(["Calm"]))

        undo.beginUndoGrouping()
        library.apply(.setTag("CUSTOM_KEY", []), to: all, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Delete CUSTOM_KEY")
        #expect(!library.rawTags(for: all).contains { $0.key == "CUSTOM_KEY" })

        undo.undo()
        #expect(library.rawTags(for: all).first { $0.key == "CUSTOM_KEY" }?.state == .mixed(count: 2))
        undo.undo()
        #expect(!library.rawTags(for: all).contains { $0.key == "MOOD" })
    }

    @Test func editsOneValueOfATagPerFile() async throws {
        let (library, ids, _) = try await loadedLibrary()
        library.apply(.setTag("ARTISTS", ["A", "B"]), to: [ids[0]], undoManager: nil)
        library.apply(.setTag("ARTISTS", ["A", "C"]), to: [ids[1]], undoManager: nil)

        // Changing the first value keeps each file's own second value.
        library.apply(.setTagValue("ARTISTS", index: 0, "Z"), to: [ids[0], ids[1]], undoManager: nil)
        #expect(library.item(ids[0])?.edited.fields["ARTISTS"] == ["Z", "B"])
        #expect(library.item(ids[1])?.edited.fields["ARTISTS"] == ["Z", "C"])

        library.apply(.addTagValue("ARTISTS", " D "), to: [ids[0], ids[2]], undoManager: nil)
        #expect(library.item(ids[0])?.edited.fields["ARTISTS"] == ["Z", "B", "D"])
        #expect(library.item(ids[2])?.edited.fields["ARTISTS"] == ["D"])

        // An empty value removes it; removing the last value deletes the tag.
        library.apply(.setTagValue("ARTISTS", index: 1, ""), to: [ids[0]], undoManager: nil)
        #expect(library.item(ids[0])?.edited.fields["ARTISTS"] == ["Z", "D"])
        library.apply(.setTagValue("ARTISTS", index: 0, ""), to: [ids[2]], undoManager: nil)
        #expect(library.item(ids[2])?.edited.fields["ARTISTS"] == nil)
    }

    @Test func plansAndAppliesFormatSteps() async throws {
        let (library, ids, _) = try await loadedLibrary()
        var upper = FormatStep(.changeCase)
        upper.caseStyle = .uppercase
        upper.target = .field(.artist)

        // Only the chosen field; multiple values (basic.flac's two artists) each change.
        let plan = try library.planFormat([upper], in: ids).get()
        #expect(plan.changes.map(\.label) == ["Artist", "Artist"])
        #expect(plan.changes.first?.before == "Artist One; Artist Two")
        #expect(plan.changes.first?.after == "ARTIST ONE; ARTIST TWO")
        #expect(plan.fileCount == 2)

        let undo = undoManager()
        library.applyFormat(plan, undoManager: undo)
        #expect(undo.undoActionName == "Format Tags")
        #expect(library.item(ids[0])?.edited.fields["ARTIST"] == ["ARTIST ONE", "ARTIST TWO"])
        #expect(library.item(ids[1])?.artist == "MP3 ARTIST")
        #expect(library.item(ids[0])?.title == "Flac Title")
        #expect(library.item(ids[2])?.isDirty == false)

        undo.undo()
        #expect(library.item(ids[0])?.edited.fields["ARTIST"] == ["Artist One", "Artist Two"])
        // Nothing to change means nothing planned; a bad step fails.
        #expect(try library.planFormat([upper], in: [ids[2]]).get().changes.isEmpty)
        #expect(library.planFormat([FormatStep(.replace)], in: ids).isFailure)
    }

    @Test func listsChangesToAnyTag() async throws {
        let (library, ids, _) = try await loadedLibrary()
        var remove = FormatStep(.removeTags)
        remove.tagNames = "CUSTOM_KEY, Track Total"
        let plan = try library.planFormat([remove], in: [ids[0]]).get()
        #expect(plan.changes.map(\.label) == ["Track Total", "CUSTOM_KEY"])
        #expect(plan.changes.map(\.before) == ["12", "keep me"])
        #expect(plan.changes.map(\.after) == ["", ""])
    }

    @Test func formatsFileNamesWithUndo() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let folder = urls[0].deletingLastPathComponent()
        var upper = FormatStep(.changeCase)
        upper.caseStyle = .uppercase
        upper.target = .fileName
        var retitle = FormatStep(.setTag)
        retitle.destination = .field(.title)
        retitle.pattern = "%filename%"
        retitle.onlyIfEmpty = false

        let plan = try library.planFormat([upper, retitle], in: ids).get()
        #expect(plan.renames.map(\.relativePath) == ["BASIC.flac", "BASIC.mp3", "COVER.flac"])
        #expect(plan.changes.filter { $0.label == "File Name" }.map(\.after) == ["BASIC.flac", "BASIC.mp3", "COVER.flac"])
        // Later steps see the new name.
        #expect(plan.changes.first { $0.label == "Title" }?.after == "BASIC")

        let undo = undoManager()
        #expect(library.applyFormat(plan, undoManager: undo).isEmpty)
        #expect(try names(in: folder) == ["BASIC.flac", "BASIC.mp3", "COVER.flac"])
        #expect(library.item(ids[0])?.title == "BASIC")
        #expect(undo.undoActionName == "Format Tags")

        // One undo puts back both the names and the tags.
        undo.undo()
        #expect(try names(in: folder) == ["basic.flac", "basic.mp3", "cover.flac"])
        #expect(library.item(ids[0])?.title == "Flac Title")
        #expect(library.item(ids[0])?.url.lastPathComponent == "basic.flac")
    }

    @Test func fileNameCollisionsAreSkipped() async throws {
        let (library, ids, _) = try await loadedLibrary()
        var same = FormatStep(.setTag)
        same.destination = .fileName
        same.pattern = "Same"
        same.onlyIfEmpty = false
        // basic.flac and cover.flac would both become "Same.flac"; basic.mp3 can.
        let plan = try library.planFormat([same], in: ids).get()
        let renames = plan.changes.filter { $0.label == "File Name" }
        #expect(renames.map(\.after) == ["Same.flac", "Same.mp3", "Same.flac"])
        #expect(renames.map { $0.problem != nil } == [true, false, true])
        #expect(plan.fileCount == 1)

        var empty = same
        empty.pattern = "..."
        #expect(try library.planFormat([empty], in: [ids[0]]).get().changes.first?.problem == "The new name would be empty.")
    }

    @Test func listsGenresInUseByFrequency() async throws {
        let (library, ids, _) = try await loadedLibrary()
        #expect(library.genres == ["Ambient"])
        library.apply(.setField(.genre, "Jazz; Ambient"), to: [ids[1], ids[2]], undoManager: nil)
        #expect(library.genres == ["Ambient", "Jazz"])
    }

    @Test func savesKeepingModificationDates() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: urls[0].path)
        await library.revert([ids[0]], undoManager: nil)
        library.apply(.setField(.title, "Kept Date"), to: [ids[0]], undoManager: nil)
        library.keepModificationDates = true
        #expect(await library.save(undoManager: nil).isEmpty)
        #expect(TagIO.modificationDate(of: urls[0]) == old)
        #expect(library.item(ids[0])?.modificationDate == old)
    }

    @Test func saveFailureKeepsEdits() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        library.apply(.setField(.title, "X"), to: [ids[0]], undoManager: nil)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: urls[0].path)

        let failures = await library.save(undoManager: nil)
        #expect(failures.count == 1)
        let item = try #require(library.item(ids[0]))
        #expect(item.isDirty)
        #expect(item.error != nil)
    }

    @Test func revertReloadsAndIsUndoable() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let undo = undoManager()
        undo.beginUndoGrouping()
        library.apply(.setField(.title, "Edited"), to: [ids[0]], undoManager: undo)
        undo.endUndoGrouping()

        undo.beginUndoGrouping()
        await library.revert([ids[0]], undoManager: undo)
        undo.endUndoGrouping()
        #expect(library.item(ids[0])?.title == "Flac Title")
        #expect(library.item(ids[0])?.isDirty == false)

        undo.undo()
        #expect(library.item(ids[0])?.title == "Edited")
    }

    @Test func setsTagsFromFileNamesWithUndo() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let folder = urls[0].deletingLastPathComponent()
        // basic.flac → "07 - First.flac", basic.mp3 → "08 - Second.mp3"; cover.flac doesn't match.
        try FileManager.default.moveItem(at: urls[0], to: folder.appendingPathComponent("07 - First.flac"))
        try FileManager.default.moveItem(at: urls[1], to: folder.appendingPathComponent("08 - Second.mp3"))
        library.remove(Set(ids))
        await library.add([folder])
        let items = library.items
        #expect(items.map(\.fileName) == ["07 - First.flac", "08 - Second.mp3", "cover.flac"])

        let plans = library.planTagsFromNames(Set(items.map(\.id)), pattern: TagsFromNamePattern("%track% - %title%"))
        #expect(plans.map(\.summary) == ["Track 7 · Title First", "Track 8 · Title Second", ""])
        #expect(plans[2].tags == nil)

        let undo = undoManager()
        undo.beginUndoGrouping()
        library.applyTagsFromNames(plans, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Tags from File Names")
        #expect(items[0].title == "First")
        #expect(items[0].value(.trackNumber) == "7")
        // Other fields stay, including the FLAC's track total and the MP3's
        // n/total pair (its total 9 is kept).
        #expect(items[0].value(.trackTotal) == "12")
        #expect(items[0].album == "Flac Album")
        #expect(items[1].edited.fields["TRACKNUMBER"] == ["8/9"])
        #expect(!items[2].isDirty)

        undo.undo()
        #expect(items[0].title == "Flac Title")
        #expect(!library.hasUnsavedChanges)
    }

    @Test func renamesFilesAndUndoes() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let folder = urls[0].deletingLastPathComponent()
        let undo = undoManager()
        let plans = library.planRename(Set(ids), pattern: RenamePattern("%track% - %title%"))
        #expect(plans.map(\.destination.lastPathComponent) == ["03 - Flac Title.flac", "05 - Mp3 Title.mp3", "Covered.flac"])
        #expect(plans.map(\.status) == [.rename, .rename, .rename])
        #expect(plans[2].missing == [.trackNumber])

        undo.beginUndoGrouping()
        let failures = library.rename(plans, undoManager: undo)
        undo.endUndoGrouping()
        #expect(failures.isEmpty)
        #expect(library.item(ids[0])?.fileName == "03 - Flac Title.flac")
        #expect(library.item(at: folder.appendingPathComponent("05 - Mp3 Title.mp3"))?.id == ids[1])
        #expect(try TagIO.read(folder.appendingPathComponent("03 - Flac Title.flac")).snapshot.value(of: .title) == "Flac Title")
        #expect(try names(in: folder) == ["03 - Flac Title.flac", "05 - Mp3 Title.mp3", "Covered.flac"])

        // Edits and saving follow the renamed file.
        library.apply(.setField(.album, "After Rename"), to: [ids[0]], undoManager: nil)
        #expect(await library.save(undoManager: nil).isEmpty)
        #expect(try TagIO.read(folder.appendingPathComponent("03 - Flac Title.flac")).snapshot.value(of: .album) == "After Rename")

        let undo2 = undoManager()
        undo2.beginUndoGrouping()
        library.rename(library.planRename([ids[1]], pattern: RenamePattern("%artist%")), undoManager: undo2)
        undo2.endUndoGrouping()
        #expect(undo2.undoActionName == "Rename File")
        #expect(library.item(ids[1])?.fileName == "Mp3 Artist.mp3")
        undo2.undo()
        #expect(library.item(ids[1])?.fileName == "05 - Mp3 Title.mp3")
        #expect(try names(in: folder).contains("05 - Mp3 Title.mp3"))
        undo2.redo()
        #expect(library.item(ids[1])?.fileName == "Mp3 Artist.mp3")
    }

    @Test func skipsCollisions() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let folder = urls[0].deletingLastPathComponent()
        library.apply(.setField(.title, "Same"), to: [ids[0], ids[2]], undoManager: nil)
        try Data().write(to: folder.appendingPathComponent("Mp3 Title.mp3"))

        let plans = library.planRename(Set(ids), pattern: RenamePattern("%title%"))
        #expect(plans[0].status == .skipped("Another selected file would get the same name."))
        #expect(plans[1].status == .skipped("A file with this name already exists."))
        #expect(plans[2].status == plans[0].status)
        #expect(library.rename(plans, undoManager: nil).isEmpty)
        #expect(try names(in: folder) == ["basic.flac", "basic.mp3", "cover.flac", "Mp3 Title.mp3"])
    }

    @Test func renamesCaseOnly() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        library.apply(.setField(.title, "BASIC"), to: [ids[0]], undoManager: nil)
        let plans = library.planRename([ids[0]], pattern: RenamePattern("%title%"))
        #expect(plans.first?.status == .rename)
        #expect(library.rename(plans, undoManager: nil).isEmpty)
        #expect(try names(in: urls[0].deletingLastPathComponent()).contains("BASIC.flac"))
    }

    @Test func explainsEmptyNames() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let plans = library.planRename([ids[1]], pattern: RenamePattern("%genre%/%title%"))
        #expect(plans.first?.status == .skipped("No Genre in this file's tags, which leaves a name empty."))
    }

    @Test func unchangedNamesAreLeftAlone() async throws {
        let (library, ids, _) = try await loadedLibrary()
        library.apply(.setField(.title, "basic"), to: [ids[0]], undoManager: nil)
        let plans = library.planRename([ids[0]], pattern: RenamePattern("%title%"))
        #expect(plans.first?.status == .unchanged)
    }

    @Test func renamesIntoFoldersAndUndoes() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let folder = urls[0].deletingLastPathComponent()
        library.apply(.setField(.artist, "Band"), to: Set(ids), undoManager: nil)
        library.apply(.setField(.album, "Record"), to: Set(ids), undoManager: nil)
        let undo = undoManager()
        let plans = library.planRename(Set(ids), pattern: RenamePattern("%artist%/%album%/%title%"))
        #expect(plans.map(\.relativePath) == ["Band/Record/Flac Title.flac", "Band/Record/Mp3 Title.mp3", "Band/Record/Covered.flac"])

        undo.beginUndoGrouping()
        #expect(library.rename(plans, undoManager: undo).isEmpty)
        undo.endUndoGrouping()
        let record = folder.appendingPathComponent("Band/Record")
        #expect(try names(in: record) == ["Covered.flac", "Flac Title.flac", "Mp3 Title.mp3"])
        #expect(try names(in: folder) == ["Band"])
        #expect(library.item(ids[1])?.url.path == record.appendingPathComponent("Mp3 Title.mp3").path)

        // Undo moves the files back and removes the folders it made.
        undo.undo()
        #expect(try names(in: folder) == ["basic.flac", "basic.mp3", "cover.flac"])
        undo.redo()
        #expect(try names(in: record).count == 3)
    }

    /// Three files in "<temp>/Old Album", loaded; returns the library, ids and the two folders.
    func filesInOldAlbum(extra: String? = nil) async throws -> (Library, [AudioFileItem.ID], root: URL, old: URL) {
        let (setup, _, urls) = try await loadedLibrary()
        let root = urls[0].deletingLastPathComponent()
        let old = root.appendingPathComponent("Old Album")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        for url in urls {
            try FileManager.default.moveItem(at: url, to: old.appendingPathComponent(url.lastPathComponent))
        }
        if let extra {
            try Data().write(to: old.appendingPathComponent(extra))
        }
        _ = setup
        let library = Library()
        await library.add([old])
        return (library, library.items.map(\.id), root, old)
    }

    @Test func sortsLikeKeyPathComparators() async throws {
        let (library, ids, _) = try await loadedLibrary()
        library.apply(.setField(.title, "Track 10"), to: [ids[0]], undoManager: nil)
        library.apply(.setField(.title, "track 2"), to: [ids[1]], undoManager: nil)
        library.apply(.setField(.title, "Äbc"), to: [ids[2]], undoManager: nil)
        let items = library.items
        let orders: [[KeyPathComparator<AudioFileItem>]] = [
            [KeyPathComparator(\.title)],
            [KeyPathComparator(\.title, order: .reverse)],
            [KeyPathComparator(\.trackSortKey)],
            [KeyPathComparator(\.duration, order: .reverse), KeyPathComparator(\.fileName)],
            [KeyPathComparator(\.artworkSortKey), KeyPathComparator(\.album)],
        ]
        for order in orders {
            #expect(SortedRows.sorted(items, by: order).map(\.id) == items.sorted(using: order).map(\.id))
        }
        // Numbers in text sort numerically and case is ignored: "track 2" before "Track 10".
        #expect(SortedRows.sorted(items, by: [KeyPathComparator(\.title)]).map(\.title) == ["Äbc", "track 2", "Track 10"])
    }

    @Test func recomputesTheOrderOnlyWhenNeeded() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let cache = SortedRows()
        let order = [KeyPathComparator(\AudioFileItem.title)]
        let before = cache.rows(of: library.items, sortOrder: order)
        _ = cache.rows(of: library.items, sortOrder: order)
        #expect(cache.computations == 1)

        // Editing tags keeps the order (rows don't jump while editing)…
        library.apply(.setField(.title, "AAA"), to: [ids[2]], undoManager: nil)
        #expect(cache.rows(of: library.items, sortOrder: order).map(\.id) == before.map(\.id))
        #expect(cache.computations == 1)

        // …until the sort is chosen again (a header click), which uses the new values.
        let resorted = cache.rows(of: library.items, sortOrder: [KeyPathComparator(\.title, order: .reverse)])
        #expect(resorted.last?.id == ids[2])
        // A different set of files (e.g. filtered) sorts again too.
        _ = cache.rows(of: Array(library.items.prefix(2)), sortOrder: order)
        #expect(cache.computations == 3)
    }

    @Test func removesFoldersLeftEmpty() async throws {
        // Finder's .DS_Store doesn't keep a folder.
        let (library, ids, root, old) = try await filesInOldAlbum(extra: ".DS_Store")
        let plans = library.planRename(Set(ids), pattern: RenamePattern("New/%title%"), baseFolder: root)
        let undo = undoManager()
        undo.beginUndoGrouping()
        #expect(library.rename(plans, removeFoldersLeftEmpty: true, undoManager: undo).isEmpty)
        undo.endUndoGrouping()
        #expect(!FileManager.default.fileExists(atPath: old.path))
        // The folder the files went into is still there, so the walk up stopped.
        #expect(FileManager.default.fileExists(atPath: root.path))

        undo.undo()
        #expect(try names(in: old) == ["basic.flac", "basic.mp3", "cover.flac"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("New").path))
        undo.redo()
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func keepsFoldersThatAreNotEmpty() async throws {
        let (library, ids, root, old) = try await filesInOldAlbum(extra: "notes.txt")
        let plans = library.planRename(Set(ids), pattern: RenamePattern("New/%title%"), baseFolder: root)
        #expect(library.rename(plans, removeFoldersLeftEmpty: true, undoManager: nil).isEmpty)
        #expect(try names(in: old) == ["notes.txt"])

        // Without the option, even an emptied folder stays.
        let (library2, ids2, root2, old2) = try await filesInOldAlbum()
        let plans2 = library2.planRename(Set(ids2), pattern: RenamePattern("New/%title%"), baseFolder: root2)
        #expect(library2.rename(plans2, undoManager: nil).isEmpty)
        #expect(try names(in: old2).isEmpty)
    }

    @Test func neverRemovesImportantFolders() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(!FileRenamer.isRemovableWhenEmpty(home))
        #expect(!FileRenamer.isRemovableWhenEmpty(home.appendingPathComponent("Music")))
        #expect(!FileRenamer.isRemovableWhenEmpty(home.appendingPathComponent("Downloads")))
        #expect(!FileRenamer.isRemovableWhenEmpty(URL(fileURLWithPath: "/Volumes/Some Disk")))
        #expect(!FileRenamer.isRemovableWhenEmpty(URL(fileURLWithPath: "/Users")))
        #expect(FileRenamer.isRemovableWhenEmpty(home.appendingPathComponent("Music/Some Album")))
    }

    @Test func renamesIntoAnotherFolder() async throws {
        let (library, ids, urls) = try await loadedLibrary()
        let destination = urls[0].deletingLastPathComponent().appendingPathComponent("Sorted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let plans = library.planRename([ids[0]], pattern: RenamePattern("%album%/%title%"), baseFolder: destination)
        #expect(plans.first?.destination.path == destination.appendingPathComponent("Flac Album/Flac Title.flac").path)
        #expect(library.rename(plans, undoManager: nil).isEmpty)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Flac Album/Flac Title.flac").path))
    }

    private func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0 != ".DS_Store" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

@Suite("Rename patterns")
struct RenamePatternTests {
    let tags = TagSnapshot(fields: [
        "TITLE": ["Part 1: Intro / Reprise"],
        "ARTIST": ["A", "B"],
        "ALBUM": ["Album"],
        "TRACKNUMBER": ["7"],
        "TRACKTOTAL": ["12"],
        "DATE": ["2001-05-03"],
    ])

    func name(_ pattern: String) -> String {
        RenamePattern(pattern).relativePath(for: tags, extension: "flac").path
    }

    @Test func expandsPlaceholders() {
        #expect(name("%track% - %title%") == "07 - Part 1 - Intro - Reprise.flac")
        #expect(name("%ARTIST% - %Album% (%year%)") == "A, B - Album (2001).flac")
        #expect(name("%track% of %tracktotal%") == "07 of 12.flac")
        #expect(name("100% %title") == "100% %title.flac")
    }

    @Test func reportsMissingFields() {
        let result = RenamePattern("%disc%-%track% %genre%").relativePath(for: tags, extension: "mp3")
        #expect(result.path == "07.mp3")
        // Without missing fields, the name is kept as is.
        #expect(RenamePattern("-%track%-").relativePath(for: tags, extension: "mp3").path == "-07-.mp3")
        #expect(result.missing == [.discNumber, .genre])
        #expect(RenamePattern("%genre%").relativePath(for: tags, extension: "mp3").path == "")
    }

    @Test func cleansNames() {
        #expect(name("...%album%.  ") == "Album.flac")
        #expect(RenamePattern.clean("Line\nbreak\u{7}") == "Line break")
        let long = RenamePattern(String(repeating: "x", count: 300)).relativePath(for: tags, extension: "flac").path
        #expect(long.utf8.count == 255)
        #expect(long.hasSuffix("x.flac"))
    }

    @Test func rejectsBadPatterns() {
        #expect(RenamePattern("%nope%").error == "Unknown placeholder “%nope%”.")
        #expect(RenamePattern("  ").error != nil)
        #expect(RenamePattern("/%artist%/%title%").error != nil)
        #expect(RenamePattern("%artist%/").error != nil)
        #expect(RenamePattern("%artist%//%title%").error != nil)
        #expect(RenamePattern("%track% - %title%").error == nil)
        #expect(RenamePattern("%artist%/%title%").error == nil)
    }

    @Test func makesFolders() {
        let pattern = RenamePattern("%artist%/%album% (%year%)/%track% - %title%")
        #expect(pattern.createsFolders)
        #expect(!RenamePattern("%title%").createsFolders)
        // "/" in a tag value never makes a folder; only the pattern's own "/" does.
        #expect(name("%artist%/%album% (%year%)/%track% - %title%")
            == "A, B/Album (2001)/07 - Part 1 - Intro - Reprise.flac")
        #expect(name("Music/%album%/%title%") == "Music/Album/Part 1 - Intro - Reprise.flac")
    }

    @Test func missingTagsCantEmptyAFolderName() {
        let result = RenamePattern("%genre%/%title%").relativePath(for: tags, extension: "flac")
        #expect(result.path == "")
        #expect(result.missing == [.genre])
        // Separators are trimmed per folder name.
        #expect(name("%album% - %genre%/%genre% - %title%") == "Album/Part 1 - Intro - Reprise.flac")
        // A folder named ".." can't be produced.
        #expect(name("../%title%") == "")
    }
}
