# Taggart TODO

Ideas for future work, roughly in order of usefulness.

## Larger features

- [ ] **Online album lookup:** search MusicBrainz (or Discogs) for an album and
  fill in the tags of a whole set of files at once, with the cover from the
  Cover Art Archive. Both are free and need no account; MusicBrainz asks for
  at most one request per second and a descriptive User-Agent. The main work
  is the screen that matches the database's tracks to the files.
- [ ] **Acoustic fingerprinting (AcoustID):** identify files with no tags.
  Needs the Chromaprint library and an AcoustID API key.

## Smaller improvements

- [ ] **Export and import:** save the tag list as CSV or text; fill tags from a
  text file, such as a pasted track list.
- [ ] **Playback:** a play button, to check which song a badly named file is.

## Housekeeping

- [ ] Test the Intel build (Rosetta isn't installed on the development Mac).

## Done

- [x] **More from Format Tags:** lists of steps run in order, saved and
  loaded by name (and run from the context menu); case changes, replacing
  and space clean-up on any tag or the file name; Set a Tag from a pattern;
  Split a Tag; Remove Tags; MusicBrainz-style Title Case.
- [x] **More formats:** WAV (ID3v2 plus RIFF INFO), AIFF, WavPack, Monkey's
  Audio and WMA. Files whose contents don't match their extension are
  refused. (TagLib also handles DSF, Musepack, TrueAudio and Matroska audio,
  if they're ever wanted.)
- [x] **Number tracks** (auto-numbering): Track 1, 2, 3… in list order,
  optionally starting over in each folder, with the total and leading zeros.
  (Disc numbers could be added the same way.)
- [x] **Copy and paste tags:** all tags and pictures, from one file onto many,
  or from several files onto as many in list order, across formats.
- [x] **Format tags** (quick actions): case conversion, text replacement (plain or regular
  expression) and space clean-up for the selected files' text tags, with a
  preview. (Applying them to file names could be added later.)
- [x] **Fast sorting for big collections:** the sorted order is cached and
  computed with each file's values read once; editing doesn't re-sort (click
  a column header to sort again). With 20 000 files, actions on a sorted list
  went from about 1 s to about 0.1 s.
- [x] **Optional in-place saving** (Settings, off by default) for external
  drives and network shares, where the safety copy is a full copy.
- [x] **Remove folders left empty** after renaming files into new folders: an
  option in the rename dialog (off by default). Protected folders (home,
  Music, Downloads, …) are never removed; undo restores the folders.
- [x] **Plain `http://` cover downloads:** https:// is tried first; plain http
  is allowed as a fallback (App Transport Security exception in Info.plist).
- [x] **`.dmg` for releases:** `scripts/build-app.sh --release` makes one next
  to the zip (signed and notarized with `--sign` / `--notarize`).
- [x] Add `*.swp` to `.gitignore`.
- [x] **Edit in the list:** tag cells are editable in place; Return moves to
  the same column on the next row.
- [x] **Tags from file names:** File → Tags from File Names… reads tags from
  names (and folder names) with a pattern, with a preview.
- [x] **Shrink large covers:** an option in Settings (off by default) scales
  covers wider or taller than a limit (1024 px by default) down to JPEG when
  they're set.
- [x] **All-tags view:** the All Tags tab lists, edits, adds and deletes every
  tag, across many files at once.
- [x] **More formats:** M4A (AAC and Apple Lossless, also .m4b), Ogg Vorbis
  and Opus. M4A covers have no picture type or description; they're shown as
  front covers.
- [x] **Unsaved-changes marker** in the window's close button.
- [x] **Track/Disc numbers are numbers:** other characters are refused with a
  beep; `3/12` sets the total too. Odd values already in files are kept until
  edited.
- [x] **Genre suggestions:** the Genre field suggests genres from the loaded
  files, then TagLib's standard ID3 list (macOS 15 and later).
- [x] **Keep files' modification dates when saving:** an option in Settings.
- [x] **Rename into folders:** `/` in the rename pattern creates folders, in
  each file's folder or a chosen one; undo removes the folders it created.
- [x] **Placeholder buttons insert at the cursor** in the rename dialog
  (macOS 15 and later; on macOS 14 they add to the end).
- [x] **Drop covers straight from a web browser:** dropped or pasted image
  addresses are downloaded.
