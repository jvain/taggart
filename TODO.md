# Taggart TODO

Ideas for future work, roughly in order of usefulness.

## Larger features

- [ ] **More formats: M4A/AAC, Ogg Vorbis, Opus.** TagLib already reads and
  writes them. The work: accept the file types in `FileScanner` and the open
  panel, map the few format-specific fields (M4A stores track number and total
  as a pair, like MP3), add fixtures and tests.
- [ ] **All-tags view.** A panel listing every raw tag (MusicBrainz IDs,
  ReplayGain, lyrics, custom tags) that can edit, add and delete any of them,
  across many files at once. The app already preserves these tags but can't
  show them.
- [ ] **Tags from file names.** The reverse of rename: fill in tags from a
  pattern such as `%track% - %title%` applied to the file name, with the same
  kind of preview dialog.
- [ ] **Shrink large covers.** An optional setting to resize covers above
  e.g. 1000 px and convert them to JPEG when they're set. Some players and car
  stereos struggle with huge embedded images.

## Smaller improvements

- [ ] **Remove folders left empty** after renaming files into new folders
  (optional; currently the old folders stay).
- [ ] **Plain `http://` cover downloads from other hosts** may be blocked by
  App Transport Security (only `https://` and local servers were tested).

## Housekeeping

- [ ] Add `*.swp` to `.gitignore`.
- [ ] Offer a `.dmg` as well as the zip for releases.
- [ ] Test the Intel build (Rosetta isn't installed on the development Mac).

## Done

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
