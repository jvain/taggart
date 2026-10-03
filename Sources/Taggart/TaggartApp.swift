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

    var body: some View {
        Form {
            Picker("Write MP3 tags as:", selection: $id3v2Version) {
                ForEach(ID3v2WriteVersion.allCases) { version in
                    Text(version.label).tag(version.rawValue)
                }
            }
            Text("ID3v2.3 is the most widely supported; ID3v2.4 supports UTF-8 and multiple values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
