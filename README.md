# Taggart

A small, free (MIT) and native macOS app for editing the tags and cover art of
audio files, including many files at once: FLAC, MP3, M4A (AAC and Apple
Lossless), Ogg Vorbis, Opus, WAV, AIFF, WavPack, Monkey's Audio (APE) and WMA.

## Features

- **Load many files:** open files or whole folders (⌘O), drag them onto the
  window or the Dock icon, or use Finder's "Open With". Folders are scanned
  recursively.
- **Edit in the list:** double-click a Title, Artist, Album, Album Artist, #,
  Disc, Year or Genre cell (or press Return to edit the selected row's title).
  Return saves the cell and moves to the same column on the next row; Escape
  cancels.
- **Edit many files at once:** select any number of files and change Title,
  Artist, Album, Album Artist, Track/Disc number and total, Year, Genre,
  Composer or Comment. A field where the files differ shows *Multiple values*
  and is left alone unless you type in it. Separate multiple artists, genres or
  composers with `;`. The Genre field suggests genres as you type: those
  already in the loaded files first, then the standard ID3 genre list (built
  into TagLib). Track and Disc take numbers only; typing `3/12` sets the
  total too.
- **All tags:** the All Tags tab of the side panel lists every tag in the
  selected files under TagLib's names (MusicBrainz IDs, ReplayGain, lyrics,
  custom tags…), with a field for each value. Tags can be edited, deleted and
  added, across many files at once, with suggestions for common tag names.
- **Cover art:** drop an image on the artwork well, paste it (⌘V) or choose a
  file. Images dragged from a web browser, and copied image addresses, are
  downloaded. The new cover replaces the front cover of every selected file and keeps
  other pictures (back cover, artist, …). Covers can also be removed or
  exported. HEIC, TIFF, WebP and other formats are converted to JPEG. If you
  turn it on in Settings, covers larger than a size limit (1024 pixels by
  default) are scaled down to fit, as JPEG, when set.
- **Rename files from tags:** select files and click the rename button in the
  toolbar or choose File → Rename Files from Tags… (⇧⌘R), with a pattern such
  as `%track% - %title%`. `/` in the pattern sorts files into folders, e.g.
  `%albumartist%/%album%/%track% - %title%`, inside each file's folder or a
  folder you choose (optionally removing the folders the files leave empty).
  A preview shows each new name. Files that would collide with an existing file, or with each
  other, are skipped, and files missing a tag the pattern uses are flagged.
  Renames happen right away and can be undone with ⌘Z.
- **Format tags:** click the Aa button in the toolbar, or choose Format
  Tags… from the File menu (⇧⌘K) or a file's context menu. Make a list of
  steps that run in order on every selected file, with a preview of each
  change:
  - **Change Case:** Title Case following MusicBrainz's English style
    ("Dancing in the Dark", "Live at the BBC", "Part II"), Sentence case,
    Capitalize Every Word, UPPERCASE or lowercase. Words such as DJ or AC/DC
    are always written as listed.
  - **Replace Text** (plain or with regular expressions) and **Clean Up
    Spaces**. These and Change Case work on all text tags, one field, any
    tag (as named in All Tags), or the file name.
  - **Set a Tag** from a pattern: Album Artist = `%artist%` where it's
    empty, Title = `%filename%`, or the file name from tags.
  - **Split a Tag** into others: a Title "Band - Song" into Artist and Title.
  - **Remove Tags:** the listed ones, or all but the listed ones.

  Save lists of steps in the Saved Steps menu, and run a saved list on the
  selected files straight from the context menu (Format Tags With). One ⌘Z
  undoes it all; tag changes are saved with ⌘S, and files are renamed right
  away.
- **Look up albums on MusicBrainz:** select an album's files and choose
  File → Look Up on MusicBrainz… (⇧⌘L). Taggart searches by the files' album
  and artist (or a pasted MusicBrainz release link), matches the files to the
  chosen release's tracks by number, title and length (change any pairing
  from its menu), and sets titles, artists, track and disc numbers, the date,
  label and other release details, MusicBrainz IDs and the cover from the
  Cover Art Archive. A Changes tab shows everything before it's applied; it's
  undoable and saved with ⌘S like other edits. Tag names follow MusicBrainz
  Picard's. No account is needed.
- **Tags from file names:** the reverse of renaming. File → Tags from File
  Names… (⇧⌘T) reads tags from names with a pattern such as
  `%track% - %title%`; `/` reads folder names too (e.g.
  `%artist%/%album%/%track% - %title%`) and `%skip%` skips text. A preview
  shows the tags read from each file; names that don't match are skipped.
  Only the tags in the pattern change, and like other edits they're saved
  with ⌘S.
- **Number tracks:** File → Number Tracks… (⇧⌘N) sets Track to 1, 2, 3… for
  the selected files in list order (sort the list first, e.g. by File). It
  can start at any number, start over in each folder, set Track Total to the
  last number, and add leading zeros. A preview shows each file's number
  before and after.
- **Copy and paste tags:** Edit → Copy Tags (⇧⌘C) copies all tags and
  pictures of the selected files; Edit → Paste Tags (⇧⌘V) replaces the
  selected files' tags and pictures with them. One file's tags paste onto any
  number of files; several files' tags paste onto as many files, in list
  order (e.g. from a FLAC album onto its MP3 copies). Copying works between
  formats, and copied tags stay until you copy again or quit.
- **Undo/redo** (⌘Z / ⌘⇧Z) for every edit until you save. Edits stay pending
  (marked with a dot, in the list and in the window's close button) until you
  save with ⌘S. **Revert Selected** re-reads
  files from disk.
- **Safe saving:** each file is written to an instant APFS clone, which then
  replaces the original, so a failed save can't damage a file. On external
  drives and network shares that clone is a full copy; Settings can switch to
  writing tags directly into the files there, which is much faster but less
  safe if a save is interrupted. Taggart won't
  overwrite a file that another app changed after it was loaded.
- **Leaves everything else alone:** tags you don't edit (MusicBrainz IDs,
  ReplayGain, …), the audio data, and an existing ID3v1 tag are preserved.
  Taggart never adds an ID3v1 tag. MP3, WAV and AIFF files keep their ID3v2
  version unless you choose ID3v2.3 or 2.4 in Settings. Settings can also keep
  files' modification dates when saving.
- **Format notes:**
  - WAV files get an ID3v2 tag, and their RIFF INFO tag, which some apps read
    instead, is kept in step with it (INFO holds only the common tags).
  - WavPack and Monkey's Audio use APEv2 tags, which hold one front and one
    back cover.
  - WMA keeps one value per tag: several artists or genres are stored as one
    value, separated by "; ". WMA can only store the tags it knows (the common
    ones, MusicBrainz IDs, ReplayGain, lyrics, …); saving any other tag fails
    and names it, leaving the file unchanged.

## Building

Requirements: macOS 14 or later to run, and Swift 6.2 or later (Xcode or just
the Command Line Tools) to build.

```sh
scripts/build-app.sh      # → build/Taggart.app (for this Mac, ad-hoc signed)
open build/Taggart.app

swift run Taggart         # debug build, run directly
scripts/test.sh           # run the test suite
```

To install, drag `build/Taggart.app` into Applications.

### Releases

```sh
scripts/build-app.sh --release
```

This makes a universal (Apple silicon + Intel) build and packages it as
`build/Taggart-<version>.zip` and as a disk image, `build/Taggart-<version>.dmg`,
with an Applications shortcut to drag the app to. The license files are in
`Taggart.app/Contents/Resources/Licenses`. The version comes from
`CFBundleShortVersionString` in `Resources/Info.plist`; bump it (and
`CFBundleVersion`) before a release.

Such a build is ad-hoc signed, so on other Macs people must allow it once in
System Settings → Privacy & Security → Open Anyway. To make it open normally
everywhere, sign it with a Developer ID certificate (Apple Developer Program)
and have Apple notarize it:

```sh
# Once: save notarization credentials (uses an app-specific password).
xcrun notarytool store-credentials taggart --apple-id <Apple ID> --team-id <team ID>

scripts/build-app.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize taggart
```

This signs with the hardened runtime, has Apple's notary service check the zip
and the disk image, and staples the tickets to the app and the disk image.

`scripts/test.sh` wraps `swift test`, because with only the Command Line Tools
installed SwiftPM doesn't find Swift Testing's macro plugin by itself. For the
same reason (the macOS 27 SDK makes `@State` a macro whose plugin ships only
with Xcode) the app uses a small `@ViewState` wrapper instead of `@State`.

## Layout

| Path | What |
| --- | --- |
| `Sources/TagBridge` | A small C API over [TagLib](https://taglib.org), so Swift needs no C++ interop |
| `Sources/TaggartCore` | UI-free model: reading and writing tags, field mapping, artwork, bulk edits and undo, safe saving |
| `Sources/Taggart` | The SwiftUI app |
| `Tests/TaggartCoreTests` | Round-trip tests against tiny fixture files (`scripts/make-fixtures.sh` regenerates them with ffmpeg, metaflac and python3) |
| `scripts/make-icon.swift` | Draws `Resources/AppIcon.icns` |

## License

MIT; see `LICENSE`. TagLib and the other bundled libraries keep their own
licenses; see `THIRD_PARTY_NOTICES.md`.
