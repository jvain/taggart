# Taggart

A small, free (MIT) and native macOS app for editing the tags and cover art of
FLAC and MP3 files, including many files at once.

## Features

- **Load many files:** open files or whole folders (⌘O), drag them onto the
  window or the Dock icon, or use Finder's "Open With". Folders are scanned
  recursively.
- **Edit many files at once:** select any number of files and change Title,
  Artist, Album, Album Artist, Track/Disc number and total, Year, Genre,
  Composer or Comment. A field where the files differ shows *Multiple values*
  and is left alone unless you type in it. Separate multiple artists, genres or
  composers with `;`.
- **Cover art:** drop an image on the artwork well, paste it (⌘V) or choose a
  file. The new cover replaces the front cover of every selected file and keeps
  other pictures (back cover, artist, …). Covers can also be removed or
  exported. HEIC, TIFF, WebP and other formats are converted to JPEG.
- **Undo/redo** (⌘Z / ⌘⇧Z) for every edit until you save. Edits stay pending
  (marked with a dot) until you save with ⌘S. **Revert Selected** re-reads
  files from disk.
- **Safe saving:** each file is written to an instant APFS clone, which then
  replaces the original, so a failed save can't damage a file. Taggart won't
  overwrite a file that another app changed after it was loaded.
- **Leaves everything else alone:** tags without UI (MusicBrainz IDs,
  ReplayGain, …), the audio data, and an existing ID3v1 tag are preserved.
  Taggart never adds an ID3v1 tag. MP3 files keep their ID3v2 version unless
  you choose ID3v2.3 or 2.4 in Settings.

## Building

Requirements: macOS 14 or later to run, and Swift 6.2 or later (Xcode or just
the Command Line Tools) to build.

```sh
scripts/build-app.sh      # → build/Taggart.app (release, ad-hoc signed)
open build/Taggart.app

swift run Taggart         # debug build, run directly
scripts/test.sh           # run the test suite
```

To install, copy `build/Taggart.app` to `/Applications`.

The app is ad-hoc signed, not notarized. A copy built on another Mac must be
allowed once in System Settings → Privacy & Security. A copy you build
yourself opens normally.

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
| `Tests/TaggartCoreTests` | Round-trip tests against tiny fixture files (`scripts/make-fixtures.sh` regenerates them with ffmpeg and metaflac) |
| `scripts/make-icon.swift` | Draws `Resources/AppIcon.icns` |

## License

MIT; see `LICENSE`. TagLib and the other bundled libraries keep their own
licenses; see `THIRD_PARTY_NOTICES.md`.
