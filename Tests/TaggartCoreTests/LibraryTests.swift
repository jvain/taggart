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
    /// Three files sharing one folder.
    func loadedLibrary() async throws -> (Library, [URL]) {
        let first = try fixture("basic.flac")
        let folder = first.deletingLastPathComponent()
        for name in ["basic.mp3", "cover.flac"] {
            let source = try fixture(name)
            try FileManager.default.moveItem(at: source, to: folder.appendingPathComponent(name))
        }
        let library = Library()
        let failures = await library.add([folder])
        #expect(failures.isEmpty)
        return (library, library.items.map(\.url))
    }

    func undoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    @Test func loadsFolderOnce() async throws {
        let (library, urls) = try await loadedLibrary()
        #expect(urls.map(\.lastPathComponent) == ["basic.flac", "basic.mp3", "cover.flac"])
        await library.add(urls)
        #expect(library.items.count == 3)
        #expect(!library.isLoading)
    }

    @Test func bulkEditUndoRedo() async throws {
        let (library, urls) = try await loadedLibrary()
        let all = Set(urls)
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
        let (library, urls) = try await loadedLibrary()
        let blue = try newArtwork()
        let selection: Set = [urls[0], urls[1]]
        library.apply(.setFrontCover(blue), to: selection, undoManager: nil)
        #expect(library.artworkState(for: selection) == .uniform(blue))
        #expect(library.item(urls[2])?.isDirty == false)
        #expect(library.thumbnails[blue.digest] != nil)
    }

    @Test func findsTheFileHoldingTheShownArtwork() async throws {
        let (library, urls) = try await loadedLibrary()
        // Only cover.flac has artwork; selecting all must still find it there.
        let source = try #require(library.primaryArtwork(in: Set(urls)))
        #expect(source.url.lastPathComponent == "cover.flac")
        #expect(source.artwork.type == .frontCover)
        let data = try TagIO.data(of: source.artwork, in: source.url)
        #expect(ArtworkImage.mimeType(of: data) == "image/png")
        #expect(library.primaryArtwork(in: [urls[0]]) == nil)
    }

    @Test func savesAndClearsUndo() async throws {
        let (library, urls) = try await loadedLibrary()
        let undo = undoManager()
        undo.beginUndoGrouping()
        library.apply(.setField(.album, "Saved Album"), to: Set(urls), undoManager: undo)
        library.apply(.setFrontCover(try newArtwork()), to: [urls[1]], undoManager: undo)
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

    @Test func saveFailureKeepsEdits() async throws {
        let (library, urls) = try await loadedLibrary()
        library.apply(.setField(.title, "X"), to: [urls[0]], undoManager: nil)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: urls[0].path)

        let failures = await library.save(undoManager: nil)
        #expect(failures.count == 1)
        let item = try #require(library.item(urls[0]))
        #expect(item.isDirty)
        #expect(item.error != nil)
    }

    @Test func revertReloadsAndIsUndoable() async throws {
        let (library, urls) = try await loadedLibrary()
        let undo = undoManager()
        undo.beginUndoGrouping()
        library.apply(.setField(.title, "Edited"), to: [urls[0]], undoManager: undo)
        undo.endUndoGrouping()

        undo.beginUndoGrouping()
        await library.revert([urls[0]], undoManager: undo)
        undo.endUndoGrouping()
        #expect(library.item(urls[0])?.title == "Flac Title")
        #expect(library.item(urls[0])?.isDirty == false)

        undo.undo()
        #expect(library.item(urls[0])?.title == "Edited")
    }
}
