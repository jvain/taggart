import SwiftUI
import TaggartCore

@main
struct TaggartApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var controller: AppController { appDelegate.controller }

    var body: some Scene {
        Window("Taggart", id: Self.mainWindowID) {
            ContentView()
                .environment(controller)
        }
        .defaultSize(width: 1280, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { controller.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { Task { await controller.save() } }
                    .keyboardShortcut("s")
                    .disabled(!controller.library.hasUnsavedChanges || controller.library.isSaving)
                Button("Revert Selected") { controller.revertSelected() }
                    .disabled(controller.selection.isEmpty)
                Divider()
                Button("Rename Files from Tags…") { controller.showRenameSheet() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(controller.selection.isEmpty || controller.library.isSaving)
                Button("Tags from File Names…") { controller.showTagsFromNamesSheet() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(controller.selection.isEmpty || controller.library.isSaving)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Remove from List") { controller.removeSelected() }
                    .keyboardShortcut(.delete)
                    .disabled(controller.selection.isEmpty)
            }
            InspectorCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.id3v2VersionKey) private var id3v2Version = ID3v2WriteVersion.keep.rawValue
    @AppStorage(Preferences.keepModificationDatesKey) private var keepModificationDates = false
    @AppStorage(Preferences.writeTagsInPlaceKey) private var writeTagsInPlace = false
    @AppStorage(Preferences.shrinkCoversKey) private var shrinkCovers = false
    @AppStorage(Preferences.maxCoverSizeKey) private var maxCoverSize = Preferences.defaultMaxCoverSize

    var body: some View {
        Form {
            Section {
                Picker("Write MP3 tags as:", selection: $id3v2Version) {
                    ForEach(ID3v2WriteVersion.allCases) { version in
                        Text(version.label).tag(version.rawValue)
                    }
                }
                Text("ID3v2.3 is the most widely supported; ID3v2.4 supports UTF-8 and multiple values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Shrink large covers when setting them", isOn: $shrinkCovers)
                HStack(spacing: 6) {
                    Text("Maximum width or height:")
                    TextField("Maximum size", value: $maxCoverSize, format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Stepper("Maximum size", value: $maxCoverSize, in: Preferences.coverSizeRange, step: 64)
                        .labelsHidden()
                    Text("pixels")
                }
                .disabled(!shrinkCovers)
                .onChange(of: maxCoverSize) {
                    maxCoverSize = maxCoverSize.clamped(to: Preferences.coverSizeRange)
                }
                Text("Larger covers are scaled down to fit and saved as JPEG. Covers already in your files aren't changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Write tags directly into files", isOn: $writeTagsInPlace)
                Text("Speeds up saving files on external drives and network shares. Normally each file is saved to a copy that then replaces it, so an interrupted save can't damage the file. On your Mac's own disk that copy is instant, but on other drives the whole file is copied. Writing directly skips the copy, but a save that's interrupted, for example by unplugging the drive, can damage the file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Keep files' modification dates when saving", isOn: $keepModificationDates)
                Text("Folders sorted by date stay in the same order after retagging. Backup and sync tools that look only at dates and sizes may then miss the changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
