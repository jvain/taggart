# Taggart TODO

Ideas for future work, roughly in order of usefulness.

## Larger features

None left; see Done below.

## Smaller improvements

None left; see Done below.

## Housekeeping

- [ ] Test the Intel build (Rosetta isn't installed on the development Mac).

## Done

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
