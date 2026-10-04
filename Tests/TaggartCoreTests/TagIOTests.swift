import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import TaggartCore

@Suite("Reading")
struct ReadingTests {
    @Test func readsFlac() throws {
        let loaded = try TagIO.read(fixture("basic.flac"))
        let tags = loaded.snapshot
        #expect(loaded.info.format == .flac)
        #expect(loaded.info.bitsPerSample == 16)
        #expect(loaded.info.sampleRate == 44100)
        #expect(abs(loaded.info.duration - 1) < 0.1)
        #expect(tags.value(of: .title) == "Flac Title")
        #expect(tags.value(of: .artist) == "Artist One; Artist Two")
        #expect(tags.value(of: .album) == "Flac Album")
        #expect(tags.value(of: .trackNumber) == "3")
        #expect(tags.value(of: .trackTotal) == "12")
        #expect(tags.value(of: .discNumber) == "1")
        #expect(tags.value(of: .discTotal) == "2")
        #expect(tags.value(of: .date) == "2001")
        #expect(tags.value(of: .genre) == "Ambient")
        #expect(tags.fields["CUSTOM_KEY"] == ["keep me"])
    }

    @Test func readsMp3() throws {
        let loaded = try TagIO.read(fixture("basic.mp3"))
        #expect(loaded.info.format == .mp3)
        #expect(loaded.info.id3v2Version == 4)
        #expect(!loaded.info.hasID3v1)
        #expect(loaded.snapshot.value(of: .title) == "Mp3 Title")
        #expect(loaded.snapshot.value(of: .trackNumber) == "5")
        #expect(loaded.snapshot.value(of: .trackTotal) == "9")
        #expect(loaded.snapshot.value(of: .date) == "1999")
        #expect(loaded.snapshot.fields["CUSTOM_KEY"] == ["keep me"])

        let legacy = try TagIO.read(fixture("legacy.mp3"))
        #expect(legacy.info.id3v2Version == 3)
        #expect(legacy.info.hasID3v1)
        #expect(legacy.snapshot.value(of: .title) == "Legacy Title")
    }

    @Test func readsM4A() throws {
        let aac = try TagIO.read(fixture("basic.m4a"))
        #expect(aac.info.format == .mp4)
        #expect(aac.info.codec == .aac)
        #expect(aac.info.summary.hasPrefix("AAC "))
        #expect(aac.snapshot.value(of: .title) == "M4a Title")
        #expect(aac.snapshot.value(of: .albumArtist) == "M4a Band")
        #expect(aac.snapshot.value(of: .trackNumber) == "4")
        #expect(aac.snapshot.value(of: .trackTotal) == "10")
        #expect(aac.snapshot.value(of: .discNumber) == "1")
        #expect(aac.snapshot.value(of: .discTotal) == "2")
        #expect(aac.snapshot.value(of: .date) == "2005")
        #expect(aac.snapshot.value(of: .genre) == "Jazz")

        let alac = try TagIO.read(fixture("cover.m4a"))
        #expect(alac.info.codec == .alac)
        // The sample rate is formatted for the user's locale ("44.1" or "44,1").
        #expect(alac.info.summary.hasPrefix("ALAC 16-bit 44"))
        #expect(alac.info.summary.hasSuffix("1 kHz"))
        // MP4 covers have no picture type; they're the cover.
        #expect(alac.snapshot.artwork.map(\.type) == [.frontCover])
        #expect(alac.snapshot.artwork.first?.mimeType == "image/png")
        #expect(alac.snapshot.artwork.first?.width == 64)
    }

    @Test func readsOggVorbisAndOpus() throws {
        let vorbis = try TagIO.read(fixture("basic.ogg"))
        #expect(vorbis.info.format == .oggVorbis)
        #expect(vorbis.info.summary.hasPrefix("Vorbis"))
        #expect(vorbis.snapshot.value(of: .title) == "Ogg Title")
        #expect(vorbis.snapshot.value(of: .trackNumber) == "2")
        #expect(vorbis.snapshot.value(of: .trackTotal) == "7")
        #expect(vorbis.snapshot.fields["CUSTOM_KEY"] == ["keep me"])

        let opus = try TagIO.read(fixture("basic.opus"))
        #expect(opus.info.format == .opus)
        #expect(opus.info.sampleRate == 48000)
        #expect(opus.snapshot.value(of: .title) == "Opus Title")
        #expect(opus.snapshot.value(of: .trackNumber) == "6")
    }

    @Test func readsArtwork() throws {
        let flac = try TagIO.read(fixture("cover.flac")).snapshot.artwork
        #expect(flac.map(\.type) == [.frontCover, .backCover])
        #expect(flac.map(\.mimeType) == ["image/png", "image/jpeg"])
        #expect(flac[0].width == 64 && flac[0].height == 64)

        let mp3 = try TagIO.read(fixture("cover.mp3")).snapshot.artwork
        #expect(mp3.count == 1)
        #expect(mp3.first?.type == .frontCover)
        // ID3v2 doesn't store dimensions; they come from the image itself.
        #expect(mp3.first?.width == 64)
    }

    @Test func makesThumbnails() throws {
        let cache = ThumbnailCache()
        let loaded = try TagIO.read(fixture("cover.flac"), thumbnails: cache)
        for artwork in loaded.snapshot.artwork {
            #expect(cache[artwork.digest] != nil)
        }
    }

    @Test func rejectsNonAudio() throws {
        let url = try fixture("blue.jpg")
        let renamed = url.deletingPathExtension().appendingPathExtension("mp3")
        try FileManager.default.moveItem(at: url, to: renamed)
        #expect(throws: TagIOError.self) { try TagIO.read(renamed) }
    }
}

@Suite("Writing")
struct WritingTests {
    static let files = [
        "basic.flac", "basic.mp3", "legacy.mp3", "cover.flac", "cover.mp3",
        "basic.m4a", "cover.m4a", "basic.ogg", "basic.opus",
    ]

    @Test(arguments: files)
    func roundTripsEveryField(_ name: String) throws {
        let url = try fixture(name)
        let values: [LogicalField: String] = [
            .title: "Ťitle ✓", .artist: "Artist", .album: "Album", .albumArtist: "Album Artist",
            .trackNumber: "7", .trackTotal: "14", .discNumber: "2", .discTotal: "3", .date: "2024",
            .genre: "Jazz", .composer: "Composer", .comment: "A comment",
        ]
        let reloaded = try edit(url) { tags, format in
            for (field, value) in values {
                tags.set(field, to: value, format: format)
            }
        }
        for (field, value) in values {
            #expect(reloaded.snapshot.value(of: field) == value, "\(field)")
        }
    }

    @Test(arguments: files)
    func leavesAudioUntouched(_ name: String) throws {
        let url = try fixture(name)
        let before = try audioDigest(of: url)
        try edit(url) { tags, format in
            tags.set(.title, to: String(repeating: "Long title ", count: 500), format: format)
            tags = tags.applying(.setFrontCover(try newArtwork()), format: format)
        }
        #expect(try audioDigest(of: url) == before)
    }

    @Test func keepsUntouchedFieldsAndCustomTags() throws {
        let flac = try edit(fixture("basic.flac")) { tags, format in
            tags.set(.title, to: "New", format: format)
        }
        #expect(flac.snapshot.fields["ARTIST"] == ["Artist One", "Artist Two"])
        #expect(flac.snapshot.fields["CUSTOM_KEY"] == ["keep me"])
        #expect(flac.snapshot.fields["TRACKTOTAL"] == ["12"])

        let mp3 = try edit(fixture("basic.mp3")) { tags, format in
            tags.set(.title, to: "New", format: format)
        }
        #expect(mp3.snapshot.fields["CUSTOM_KEY"] == ["keep me"])
        #expect(mp3.snapshot.value(of: .trackTotal) == "9")
    }

    @Test(arguments: ["basic.ogg", "basic.opus"])
    func keepsCustomTagsInOgg(_ name: String) throws {
        let loaded = try edit(fixture(name)) { tags, format in
            tags.set(.title, to: "New", format: format)
        }
        #expect(loaded.snapshot.fields["CUSTOM_KEY"] == ["keep me"])
        #expect(loaded.snapshot.fields["ARTIST"]?.isEmpty == false)
    }

    @Test(arguments: files)
    func roundTripsRawTags(_ name: String) throws {
        let tags: [String: [String]] = [
            "MUSICBRAINZ_TRACKID": ["7f7c3e7a-9d43-4b7b-a2a3-1d5a7c1f0e11"],
            "REPLAYGAIN_TRACK_GAIN": ["-6.50 dB"],
            "LYRICS": ["First line; still the first\nSecond line"],
            "MY TAG": ["custom value"],
        ]
        let reloaded = try edit(fixture(name)) { snapshot, format in
            for (key, values) in tags {
                snapshot = snapshot.applying(.setTag(key, values), format: format)
            }
        }
        for (key, values) in tags {
            #expect(reloaded.snapshot.fields[key] == values, "\(key)")
        }

        // Deleting a raw tag removes it from the file.
        let deleted = try edit(reloaded.url) { snapshot, format in
            snapshot = snapshot.applying(.setTag("MY TAG", []), format: format)
        }
        #expect(deleted.snapshot.fields["MY TAG"] == nil)
        #expect(deleted.snapshot.fields["LYRICS"] == tags["LYRICS"])
    }

    @Test(arguments: ["basic.flac", "basic.mp3", "basic.m4a", "basic.ogg", "basic.opus"])
    func roundTripsMultipleRawValues(_ name: String) throws {
        let reloaded = try edit(fixture(name)) { snapshot, format in
            snapshot = snapshot.applying(.setTag("ARTISTS", ["First Artist", "Second Artist"]), format: format)
        }
        #expect(reloaded.snapshot.fields["ARTISTS"] == ["First Artist", "Second Artist"])
    }

    @Test func keepsCustomTagsInM4A() throws {
        let url = try fixture("basic.m4a")
        try edit(url) { tags, _ in tags.fields["CUSTOM_KEY"] = ["keep me"] }
        let loaded = try edit(url) { tags, format in tags.set(.title, to: "New", format: format) }
        #expect(loaded.snapshot.fields["CUSTOM_KEY"] == ["keep me"])
        #expect(loaded.snapshot.value(of: .albumArtist) == "M4a Band")
    }

    @Test func m4aTrackTotalLivesInTrackNumber() throws {
        let loaded = try edit(fixture("basic.m4a")) { tags, format in
            tags.set(.trackTotal, to: "11", format: format)
            tags.set(.discNumber, to: "2", format: format)
        }
        #expect(loaded.snapshot.fields["TRACKNUMBER"] == ["4/11"])
        #expect(loaded.snapshot.fields["DISCNUMBER"] == ["2/2"])
        #expect(loaded.snapshot.fields["TRACKTOTAL"] == nil)
    }

    @Test func splitsMultipleValues() throws {
        let loaded = try edit(fixture("basic.flac")) { tags, format in
            tags.set(.artist, to: "A ; B;; C", format: format)
            tags.set(.title, to: "Part 1; Part 2", format: format)
        }
        #expect(loaded.snapshot.fields["ARTIST"] == ["A", "B", "C"])
        #expect(loaded.snapshot.fields["TITLE"] == ["Part 1; Part 2"])
    }

    @Test func clearingRemovesField() throws {
        let loaded = try edit(fixture("basic.flac")) { tags, format in
            tags.set(.genre, to: "  ", format: format)
            tags.set(.trackTotal, to: "", format: format)
        }
        #expect(loaded.snapshot.fields["GENRE"] == nil)
        #expect(loaded.snapshot.fields["TRACKTOTAL"] == nil)
        #expect(loaded.snapshot.value(of: .trackNumber) == "3")
    }

    @Test func mp3TrackTotalLivesInTrackNumber() throws {
        let loaded = try edit(fixture("basic.mp3")) { tags, format in
            tags.set(.trackTotal, to: "10", format: format)
        }
        #expect(loaded.snapshot.fields["TRACKNUMBER"] == ["5/10"])
    }

    @Test func numberFieldsAcceptOnlyNumbers() {
        #expect(LogicalField.trackNumber.allowedInput("12") == "12")
        #expect(LogicalField.trackNumber.allowedInput("A1x2") == "12")
        #expect(LogicalField.trackNumber.allowedInput("3/12") == "3/12")
        #expect(LogicalField.trackNumber.allowedInput("3/1/2") == "3/12")
        #expect(LogicalField.discNumber.allowedInput(" 1 / 2 ") == "1/2")
        #expect(LogicalField.trackTotal.allowedInput("3/12") == "312")
        #expect(LogicalField.trackTotal.allowedInput("１２") == "")
        #expect(LogicalField.title.allowedInput("Track 1/2") == "Track 1/2")
    }

    @Test func typingNumberAndTotalSetsBoth() {
        var flac = TagSnapshot(fields: ["TRACKNUMBER": ["1"], "TRACKTOTAL": ["9"]])
        flac.set(.trackNumber, to: "3/12", format: .flac)
        #expect(flac.fields == ["TRACKNUMBER": ["3"], "TRACKTOTAL": ["12"]])
        flac.set(.trackNumber, to: "4/", format: .flac)
        #expect(flac.fields == ["TRACKNUMBER": ["4"], "TRACKTOTAL": ["12"]])

        var mp3 = TagSnapshot(fields: ["DISCNUMBER": ["1"]])
        mp3.set(.discNumber, to: "2/3", format: .mp3)
        #expect(mp3.fields == ["DISCNUMBER": ["2/3"]])
    }

    @Test func flacTrackNumberWithEmbeddedTotalIsSplit() throws {
        var tags = TagSnapshot(fields: ["TRACKNUMBER": ["4/8"]])
        tags.set(.trackNumber, to: "5", format: .flac)
        #expect(tags.fields["TRACKNUMBER"] == ["5"])
        #expect(tags.fields["TRACKTOTAL"] == ["8"])
    }

    @Test func flacTotalSpellingIsKeptUnlessEdited() throws {
        var tags = TagSnapshot(fields: ["TRACKNUMBER": ["4"], "TOTALTRACKS": ["8"]])
        tags.set(.trackNumber, to: "5", format: .flac)
        #expect(tags.fields == ["TRACKNUMBER": ["5"], "TOTALTRACKS": ["8"]])
        tags.set(.trackTotal, to: "9", format: .flac)
        #expect(tags.fields == ["TRACKNUMBER": ["5"], "TRACKTOTAL": ["9"]])
    }

    @Test(arguments: [true, false])
    func keepsModificationDateWhenAsked(_ keep: Bool) throws {
        let url = try fixture("basic.mp3")
        let old = Date(timeIntervalSince1970: 1_000_000_000.25)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        let loaded = try TagIO.read(url)
        var edited = loaded.snapshot
        edited.set(.title, to: "New", format: .mp3)
        try TagIO.write(edited, original: loaded.snapshot, to: url,
                        expectedModificationDate: loaded.modificationDate, keepModificationDate: keep)

        let date = try #require(TagIO.modificationDate(of: url))
        if keep {
            #expect(abs(date.timeIntervalSince(old)) < 0.001)
        } else {
            #expect(date.timeIntervalSinceNow > -60)
        }
        #expect(try TagIO.read(url).snapshot.value(of: .title) == "New")
    }

    @Test func unchangedSnapshotDoesNotTouchFile() throws {
        let url = try fixture("basic.mp3")
        let before = try Data(contentsOf: url)
        let loaded = try TagIO.read(url)
        try TagIO.write(loaded.snapshot, original: loaded.snapshot, to: url, expectedModificationDate: nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func refusesToOverwriteExternalChanges() throws {
        let url = try fixture("basic.flac")
        let loaded = try TagIO.read(url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: url.path)
        var edited = loaded.snapshot
        edited.set(.title, to: "New", format: .flac)
        #expect(throws: TagIOError.modifiedOnDisk(url)) {
            try TagIO.write(edited, original: loaded.snapshot, to: url, expectedModificationDate: loaded.modificationDate)
        }
    }

    @Test func failedWriteLeavesOriginalIntact() throws {
        let url = try fixture("cover.flac")
        let before = try Data(contentsOf: url)
        let loaded = try TagIO.read(url)
        var edited = loaded.snapshot
        edited.set(.title, to: "New", format: .flac)
        edited.artwork[0].source = .embedded(index: 7)  // Can't be resolved: the write must fail.
        edited.artwork[0].description = "changed"
        #expect(throws: TagIOError.artworkUnavailable(url)) {
            try TagIO.write(edited, original: loaded.snapshot, to: url, expectedModificationDate: loaded.modificationDate)
        }
        #expect(try Data(contentsOf: url) == before)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        #expect(leftovers == ["cover.flac"])
    }
}

@Suite("ID3v2 versions")
struct ID3v2VersionTests {
    @Test func keepsExistingVersion() throws {
        let legacy = try fixture("legacy.mp3")
        try edit(legacy) { tags, format in tags.set(.title, to: "New", format: format) }
        #expect(try id3v2MajorVersion(of: legacy) == 3)

        let modern = try fixture("basic.mp3")
        try edit(modern) { tags, format in tags.set(.title, to: "New", format: format) }
        #expect(try id3v2MajorVersion(of: modern) == 4)
    }

    @Test func convertsWhenAsked() throws {
        let legacy = try fixture("legacy.mp3")
        try edit(legacy, id3v2Version: .v2_4) { tags, format in tags.set(.title, to: "New", format: format) }
        #expect(try id3v2MajorVersion(of: legacy) == 4)

        let modern = try fixture("basic.mp3")
        let reloaded = try edit(modern, id3v2Version: .v2_3) { tags, format in
            tags.set(.title, to: "New", format: format)
        }
        #expect(try id3v2MajorVersion(of: modern) == 3)
        #expect(reloaded.snapshot.value(of: .date) == "1999")
    }

    @Test func updatesButNeverCreatesID3v1() throws {
        let legacy = try fixture("legacy.mp3")
        let reloaded = try edit(legacy) { tags, format in tags.set(.title, to: "Updated", format: format) }
        #expect(try hasID3v1(legacy))
        #expect(reloaded.info.hasID3v1)
        let trailer = try Data(contentsOf: legacy).suffix(125).prefix(30)
        #expect(String(decoding: trailer, as: UTF8.self).hasPrefix("Updated"))

        let modern = try fixture("basic.mp3")
        try edit(modern) { tags, format in tags.set(.title, to: "Updated", format: format) }
        #expect(try !hasID3v1(modern))
    }
}

@Suite("Artwork")
struct ArtworkTests {
    @Test func replacesFrontCoverAndKeepsOthers() throws {
        let url = try fixture("cover.flac")
        let backCover = try TagIO.read(url).snapshot.artwork[1]
        let blue = try newArtwork()
        let reloaded = try edit(url) { tags, format in
            tags = tags.applying(.setFrontCover(blue), format: format)
        }
        let artwork = reloaded.snapshot.artwork
        #expect(artwork.map(\.type) == [.frontCover, .backCover])
        #expect(artwork[0].digest == blue.digest)
        #expect(artwork[0].mimeType == "image/jpeg")
        #expect(artwork[0].width == 32)
        #expect(artwork[1].digest == backCover.digest)
        #expect(try TagIO.data(of: artwork[0], in: url) == fixtureData("blue.jpg"))
    }

    @Test(arguments: ["basic.mp3", "cover.mp3", "basic.flac", "basic.m4a", "cover.m4a", "basic.ogg", "basic.opus"])
    func setsCover(_ name: String) throws {
        let url = try fixture(name)
        let blue = try newArtwork()
        let reloaded = try edit(url) { tags, format in
            tags = tags.applying(.setFrontCover(blue), format: format)
        }
        #expect(reloaded.snapshot.artwork.count == 1)
        #expect(reloaded.snapshot.primaryArtwork?.digest == blue.digest)
    }

    @Test func oggKeepsOtherPictureTypes() throws {
        let url = try fixture("basic.ogg")
        var back = try newArtwork()
        back.type = .backCover
        try edit(url) { tags, _ in tags.artwork = [back] }
        let front = try ArtworkImage.artwork(from: TagIO.data(of: TagIO.read(fixture("cover.flac")).snapshot.artwork[0],
                                                              in: fixture("cover.flac")))
        let reloaded = try edit(url) { tags, format in
            tags = tags.applying(.setFrontCover(front), format: format)
        }
        #expect(reloaded.snapshot.artwork.map(\.type) == [.frontCover, .backCover])
        #expect(reloaded.snapshot.artwork.map(\.digest) == [front.digest, back.digest])
    }

    @Test(arguments: ["cover.mp3", "cover.flac", "cover.m4a"])
    func removesArtwork(_ name: String) throws {
        let url = try fixture(name)
        let reloaded = try edit(url) { tags, format in
            tags = tags.applying(.removeArtwork, format: format)
        }
        #expect(reloaded.snapshot.artwork.isEmpty)
    }

    @Test func downloadsImages() async throws {
        // URLSession treats file URLs like web addresses, so no network is needed.
        let artwork = try await ArtworkImage.download(from: fixture("blue.jpg"))
        #expect(artwork.mimeType == "image/jpeg")
        #expect(artwork.width == 32)

        let notAnImage = try fixture("basic.mp3")
        await #expect(throws: TagIOError.cannotDownload(notAnImage, reason: "It isn't an image Taggart can read.")) {
            try await ArtworkImage.download(from: notAnImage)
        }
        let missing = URL(fileURLWithPath: "/nonexistent/cover.jpg")
        await #expect(throws: TagIOError.self) { try await ArtworkImage.download(from: missing) }
    }

    /// A red image of the given size as PNG; optionally the left half is transparent.
    func pngImage(width: Int, height: Int, transparentLeftHalf: Bool = false) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if transparentLeftHalf {
            context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func shrinksLargeCovers() throws {
        let landscape = try ArtworkImage.artwork(from: pngImage(width: 2000, height: 1500), maxPixelSize: 1024)
        #expect(landscape.mimeType == "image/jpeg")
        #expect((landscape.width, landscape.height) == (1024, 768))
        // The stored bytes really are that image.
        guard case let .new(bytes) = landscape.source else { Issue.record("not new"); return }
        #expect(ArtworkImage.metrics(of: bytes).width == 1024)
        #expect(landscape.byteCount == bytes.count)

        let portrait = try ArtworkImage.artwork(from: pngImage(width: 1000, height: 3000), maxPixelSize: 1024)
        #expect(portrait.height == 1024)
        #expect(abs(portrait.width - 341) <= 1)
    }

    @Test func keepsCoversWithinTheLimit() throws {
        for (width, height) in [(800, 600), (1024, 1024)] {
            let png = try pngImage(width: width, height: height)
            let artwork = try ArtworkImage.artwork(from: png, maxPixelSize: 1024)
            #expect(artwork.mimeType == "image/png")
            #expect(artwork.digest == SHA256.hash(data: png))
        }
        // Without a limit nothing is shrunk.
        let large = try ArtworkImage.artwork(from: pngImage(width: 2000, height: 1500))
        #expect((large.width, large.mimeType) == (2000, "image/png"))
    }

    @Test func shrunkTransparentCoversGetAWhiteBackground() throws {
        let artwork = try ArtworkImage.artwork(from: pngImage(width: 2000, height: 2000, transparentLeftHalf: true), maxPixelSize: 512)
        guard case let .new(bytes) = artwork.source,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { Issue.record("no image"); return }
        // Read back one pixel from the once-transparent half and one from the red half.
        var pixels = [UInt8](repeating: 0, count: 4 * image.width * image.height)
        let context = try #require(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: 4 * image.width, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(4 * (y * image.width + x))..<(4 * (y * image.width + x) + 3)]) }
        #expect(pixel(50, 256).allSatisfy { $0 > 240 })
        #expect(pixel(450, 256)[0] > 200 && pixel(450, 256)[1] < 60)
    }

    @Test func shrinksDownloadedCovers() async throws {
        let url = try fixture("blue.jpg").deletingLastPathComponent().appendingPathComponent("big.png")
        try pngImage(width: 3000, height: 3000).write(to: url)
        let artwork = try await ArtworkImage.download(from: url, maxPixelSize: 1024)
        #expect((artwork.width, artwork.height, artwork.mimeType) == (1024, 1024, "image/jpeg"))
    }

    @Test func convertsUncommonImageFormatsToJPEG() throws {
        let image = try #require(ArtworkImage.thumbnail(of: fixtureData("blue.jpg")))
        let tiff = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(tiff, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let artwork = try ArtworkImage.artwork(from: tiff as Data)
        #expect(artwork.mimeType == "image/jpeg")
        #expect(artwork.width == 32)
        #expect(throws: TagIOError.unsupportedImage) { try ArtworkImage.artwork(from: Data("nope".utf8)) }
    }
}
