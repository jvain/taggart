import Foundation

/// Which tags a MusicBrainz release sets. Tag names follow MusicBrainz
/// Picard, so other apps understand them.
public struct MusicBrainzOptions: Codable, Equatable, Sendable {
    /// Title, Artist (and ARTISTS when several are credited), Album, Album Artist.
    public var titlesAndArtists = true
    /// Track and disc numbers and totals. Single-disc releases get no disc number.
    public var numbers = true
    /// The release date (kept when MusicBrainz has none).
    public var date = true
    /// "1997" rather than "1997-05-21", for the date and original date.
    public var yearOnly = true
    /// Label, catalog number, barcode, country, status, type, media, disc
    /// subtitle, original date and ISRC. Ones the release lacks are removed,
    /// so none are left over from another release.
    public var releaseDetails = true
    /// The MusicBrainz IDs of the release, release group, recording, track
    /// and artists, which other apps (and later lookups) use.
    public var identifiers = true

    public init() {}
}

extension MBRelease {
    /// Sets the tags for the track at `index` (into `tracks`) in `tags`.
    func apply(track index: Int, options: MusicBrainzOptions, to tags: inout TagSnapshot, format: AudioFormat) {
        let (medium, track) = tracks[index]
        let mediumCount = media?.count ?? 1
        func date(_ text: String?) -> String? {
            guard let text, !text.isEmpty else { return nil }
            return options.yearOnly ? String(text.prefix(4)) : text
        }
        func setRaw(_ key: String, _ values: [String?]) {
            let values = values.compactMap { $0 }.filter { !$0.isEmpty }
            tags.fields[key] = values.isEmpty ? nil : values
        }

        if options.titlesAndArtists {
            let credit = track.artistCredit ?? artistCredit ?? []
            tags.set(.title, to: track.title, format: format)
            tags.fields[LogicalField.artist.simpleKey!] = credit.isEmpty ? nil : [credit.text]
            // Each artist on their own, when several are credited.
            setRaw("ARTISTS", credit.count > 1 ? credit.map(\.artist.name) : [])
            tags.set(.album, to: title, format: format)
            tags.fields[LogicalField.albumArtist.simpleKey!] = artist.isEmpty ? nil : [artist]
        }
        if options.numbers {
            tags.set(.trackNumber, to: String(track.position), format: format)
            tags.set(.trackTotal, to: String(medium.trackCount), format: format)
            let isMultiDisc = mediumCount > 1
            tags.set(.discNumber, to: isMultiDisc ? String(medium.position ?? 1) : "", format: format)
            tags.set(.discTotal, to: isMultiDisc ? String(mediumCount) : "", format: format)
        }
        if options.date, let date = date(self.date) {
            tags.set(.date, to: date, format: format)
        }
        if options.releaseDetails {
            setRaw("LABEL", (labelInfo ?? []).map { $0.label?.name })
            setRaw("CATALOGNUMBER", (labelInfo ?? []).map(\.catalogNumber))
            setRaw("BARCODE", [barcode])
            setRaw("RELEASECOUNTRY", [country])
            setRaw("RELEASESTATUS", [status?.lowercased()])
            setRaw("RELEASETYPE", ([releaseGroup?.primaryType] + (releaseGroup?.secondaryTypes ?? [])).map { $0?.lowercased() })
            setRaw("MEDIA", [medium.format])
            setRaw("DISCSUBTITLE", [medium.title])
            setRaw("ORIGINALDATE", [date(releaseGroup?.firstReleaseDate)])
            setRaw("ISRC", track.recording.isrcs ?? [])
        }
        if options.identifiers {
            setRaw("MUSICBRAINZ_ALBUMID", [id])
            setRaw("MUSICBRAINZ_RELEASEGROUPID", [releaseGroup?.id])
            setRaw("MUSICBRAINZ_TRACKID", [track.recording.id])
            setRaw("MUSICBRAINZ_RELEASETRACKID", [track.id])
            setRaw("MUSICBRAINZ_ARTISTID", (track.artistCredit ?? artistCredit ?? []).map(\.artist.id))
            setRaw("MUSICBRAINZ_ALBUMARTISTID", (artistCredit ?? []).map(\.artist.id))
        }
    }
}

extension Library {
    /// Pairs the files in `ids` (in list order) with the release's tracks:
    /// each matched file's track, as an index into `release.tracks`.
    public func matchTracks(_ ids: [AudioFileItem.ID], to release: MBRelease) -> [AudioFileItem.ID: Int] {
        let files = ids.compactMap { item($0) }.map { item in
            TrackMatcher.File(
                id: item.id,
                disc: Int(item.value(.discNumber)),
                track: Int(item.value(.trackNumber)),
                title: item.title,
                name: item.url.deletingPathExtension().lastPathComponent,
                duration: item.duration
            )
        }
        return TrackMatcher.match(files, to: release)
    }

    /// What to search for: the album and artist most of the files have
    /// (preferring the album artist).
    public func lookupHints(for ids: [AudioFileItem.ID]) -> (album: String, artist: String) {
        let items = ids.compactMap { item($0) }
        func mostCommon(_ values: [String]) -> String {
            var counts: [String: Int] = [:]
            for value in values where !value.isEmpty {
                counts[value, default: 0] += 1
            }
            return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
        }
        let albumArtist = mostCommon(items.map(\.albumArtist))
        return (mostCommon(items.map(\.album)), albumArtist.isEmpty ? mostCommon(items.map(\.artist)) : albumArtist)
    }

    /// What tagging the matched files from the release would change.
    /// `cover`, if given, becomes each matched file's front cover.
    public func planMusicBrainz(_ release: MBRelease, matches: [AudioFileItem.ID: Int], options: MusicBrainzOptions,
                                cover: Artwork?, order ids: [AudioFileItem.ID]) -> FormatPlan {
        var plan = FormatPlan()
        for id in ids {
            guard let item = item(id), let index = matches[id], release.tracks.indices.contains(index) else { continue }
            var tags = item.edited
            release.apply(track: index, options: options, to: &tags, format: item.info.format)
            if let cover {
                tags = tags.applying(.setFrontCover(cover), format: item.info.format)
            }
            guard tags != item.edited else { continue }
            plan.tags[id] = tags
            plan.changes += FormatPlan.differences(from: item.edited, to: tags).map {
                FormatChange(itemID: id, url: item.url, label: $0.label, before: $0.before, after: $0.after)
            }
            if item.edited.artwork != tags.artwork {
                let describe = { (artwork: Artwork?) in artwork.map { "\($0.width) × \($0.height)" } ?? "" }
                plan.changes.append(FormatChange(itemID: id, url: item.url, label: "Cover",
                                                 before: describe(item.edited.primaryArtwork),
                                                 after: describe(tags.primaryArtwork)))
            }
        }
        return plan
    }
}
