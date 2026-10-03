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
