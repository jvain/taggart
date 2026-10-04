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

@Suite("Quick actions")
struct QuickActionTests {
    func run(_ action: QuickAction, _ text: String) -> String? {
        guard case let .success(transform) = action.transform() else { return nil }
        return transform(text)
    }

    @Test func changesCase() {
        let title = QuickAction.changeCase(.titleCase)
        #expect(run(title, "the BEST of me") == "The Best Of Me")
        #expect(run(title, "don't stop (live version)") == "Don't Stop (Live Version)")
        #expect(run(title, "hip-hop/r&b") == "Hip-Hop/R&b")
        #expect(run(title, "the 2nd time") == "The 2nd Time")
        #expect(run(title, "ääni ja öljy") == "Ääni Ja Öljy")
        #expect(run(title, "r.e.m. [remastered]") == "R.E.M. [Remastered]")

        #expect(run(.changeCase(.sentenceCase), "THE SONG OF THE YEAR") == "The song of the year")
        #expect(run(.changeCase(.sentenceCase), "(intro) PART ONE") == "(Intro) part one")
        #expect(run(.changeCase(.uppercase), "Ääni") == "ÄÄNI")
        #expect(run(.changeCase(.lowercase), "ÄÄNI") == "ääni")
    }

    @Test func replacesText() {
        #expect(run(.replace(find: "feat.", with: "ft.", matchCase: false, regularExpression: false), "A FEAT. B") == "A ft. B")
        #expect(run(.replace(find: "feat.", with: "ft.", matchCase: true, regularExpression: false), "A FEAT. B") == "A FEAT. B")
        // Regular expressions, with groups; "." is a wildcard there.
        #expect(run(.replace(find: "^(\\d+)\\. ", with: "$1 - ", matchCase: false, regularExpression: true), "01. Song") == "01 - Song")
        #expect(run(.replace(find: "\\s*\\(remaster(ed)?\\)", with: "", matchCase: false, regularExpression: true), "Song (Remastered)") == "Song")
    }

    @Test func rejectsInvalidActions() {
        #expect(QuickAction.replace(find: "", with: "x", matchCase: false, regularExpression: false).transform().isFailure)
        #expect(QuickAction.replace(find: "([", with: "x", matchCase: false, regularExpression: true).transform().isFailure)
    }

    @Test func cleansUpSpaces() {
        #expect(run(.cleanUpSpaces, "  Too   many \t spaces  ") == "Too many spaces")
        #expect(run(.cleanUpSpaces, "Line one\nLine  two ") == "Line one\nLine two")
    }
}

extension Result {
    var isFailure: Bool {
        if case .failure = self { true } else { false }
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

    @Test func appliesQuickActionsToSelectedFields() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let all = Set(ids)
        let upper = QuickAction.changeCase(.uppercase)

        // Only the chosen fields; multiple values (basic.flac's two artists) each change.
        let plan = try library.planQuickAction(upper, fields: [.artist], in: all).get()
        #expect(plan.map(\.field) == [.artist, .artist])
        #expect(plan.first?.before == "Artist One; Artist Two")
        #expect(plan.first?.after == "ARTIST ONE; ARTIST TWO")

        let undo = undoManager()
        undo.beginUndoGrouping()
        library.applyQuickAction(upper, fields: [.artist], to: all, undoManager: undo)
        undo.endUndoGrouping()
        #expect(undo.undoActionName == "Change Case")
        #expect(library.item(ids[0])?.edited.fields["ARTIST"] == ["ARTIST ONE", "ARTIST TWO"])
        #expect(library.item(ids[1])?.artist == "MP3 ARTIST")
        #expect(library.item(ids[0])?.title == "Flac Title")
        #expect(library.item(ids[2])?.isDirty == false)

        undo.undo()
        #expect(library.item(ids[0])?.edited.fields["ARTIST"] == ["Artist One", "Artist Two"])
    }

    @Test func quickActionsCanEmptyATag() async throws {
        let (library, ids, _) = try await loadedLibrary()
        let remove = QuickAction.replace(find: "Ambient", with: "", matchCase: true, regularExpression: false)
        library.applyQuickAction(remove, fields: QuickAction.fields, to: [ids[0]], undoManager: nil)
        #expect(library.item(ids[0])?.edited.fields["GENRE"] == nil)
        // Nothing to change means nothing planned.
        #expect(try library.planQuickAction(remove, fields: QuickAction.fields, in: [ids[0]]).get().isEmpty)
        #expect(library.planQuickAction(.replace(find: "", with: "", matchCase: false, regularExpression: false),
                                        fields: [.title], in: [ids[0]]).isFailure)
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
