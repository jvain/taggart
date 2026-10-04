import AppKit
import SwiftUI
import TaggartCore

/// Previews renaming the selected files from their tags, then renames them.
struct RenameSheet: View {
    let ids: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @AppStorage("renamePattern") private var patternText = "%track% - %title%"
    /// Where a pattern with folders puts them: each file's own folder, or this one.
    @AppStorage("renameIntoChosenFolder") private var intoChosenFolder = false
    @AppStorage("renameChosenFolder") private var chosenFolderPath = ""
    /// Off by default: folders are only removed when the user asks for it.
    @AppStorage("renameRemovesEmptyFolders") private var removesEmptyFolders = false

    var body: some View {
        let pattern = RenamePattern(patternText)
        let plans = controller.library.planRename(ids, pattern: pattern, baseFolder: baseFolder(for: pattern))
        let renameCount = plans.filter { $0.status == .rename }.count

        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? "Rename File from Tags" : "Rename \(ids.count) Files from Tags")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                PatternEditor(text: $patternText, tokens: PatternToken.rename)
                if let error = pattern.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Use “/” to make folders, e.g. %artist%/%album%/%track% - %title%. The file extension is kept. “/” and “:” in tags become “-”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if pattern.createsFolders && pattern.error == nil {
                destinationPicker
            }

            Table(plans) {
                TableColumn("Current Name") { plan in
                    Text(plan.source.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(plan.source.path)
                }
                TableColumn("New Name") { plan in
                    NewNameCell(plan: plan)
                }
            }
            .frame(minHeight: 220)

            Text(summary(plans))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("Files are renamed right away. ⌘Z undoes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(renameCount == 1 ? "Rename 1 File" : "Rename \(renameCount) Files") {
                    controller.rename(plans, removeFoldersLeftEmpty: pattern.createsFolders && removesEmptyFolders)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameCount == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
    }

    private var chosenFolder: URL? {
        guard !chosenFolderPath.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: chosenFolderPath, isDirectory: &isDirectory), isDirectory.boolValue
        else { return nil }
        return URL(fileURLWithPath: chosenFolderPath, isDirectory: true)
    }

    private func baseFolder(for pattern: RenamePattern) -> URL? {
        pattern.createsFolders && intoChosenFolder ? chosenFolder : nil
    }

    private var destinationPicker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Create folders in:")
            VStack(alignment: .leading, spacing: 6) {
                Picker("Create folders in:", selection: Binding(
                    get: { intoChosenFolder && chosenFolder != nil },
                    set: { chooseFolder in
                        if chooseFolder && chosenFolder == nil {
                            showFolderPanel()
                        } else {
                            intoChosenFolder = chooseFolder
                        }
                    }
                )) {
                    Text("Each file's current folder").tag(false)
                    Text(chosenFolder.map { "“\($0.lastPathComponent)”" } ?? "Another folder…").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if intoChosenFolder, let chosenFolder {
                    HStack(spacing: 6) {
                        Text(chosenFolder.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…", action: showFolderPanel)
                            .controlSize(.small)
                    }
                }
                Toggle("Remove folders left empty", isOn: $removesEmptyFolders)
                    .help("After moving the files, remove the folders they came from if nothing else is left in them (Finder's hidden .DS_Store files don't count). Undo puts them back.")
            }
        }
    }

    private func showFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder to create the new folders in. It must be on the same disk as the files."
        if let chosenFolder {
            panel.directoryURL = chosenFolder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chosenFolderPath = url.path(percentEncoded: false)
        intoChosenFolder = true
    }

    private func summary(_ plans: [RenamePlan]) -> String {
        guard !plans.isEmpty else { return "" }
        var renamed = 0, unchanged = 0, skipped = 0, missing = 0
        for plan in plans {
            switch plan.status {
            case .rename: renamed += 1
            case .unchanged: unchanged += 1
            case .skipped: skipped += 1
            }
            if !plan.missing.isEmpty {
                missing += 1
            }
        }
        var parts = ["\(renamed) to rename"]
        if unchanged > 0 {
            parts.append("\(unchanged) unchanged")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        var text = parts.joined(separator: " · ")
        if missing > 0 {
            text += missing == 1
                ? ". 1 file lacks some of the tags used."
                : ". \(missing) files lack some of the tags used."
        }
        if controller.library.items(ids).contains(where: \.isDirty) {
            text += " Names include unsaved tag edits."
        }
        return text
    }
}

private struct NewNameCell: View {
    let plan: RenamePlan

    var body: some View {
        switch plan.status {
        case .rename:
            HStack(spacing: 4) {
                Text(plan.relativePath)
                if !plan.missing.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("No \(plan.missing.map(\.label).joined(separator: ", ")) in this file's tags.")
                }
            }
        case .unchanged:
            Text("\(plan.relativePath) (unchanged)")
                .foregroundStyle(.secondary)
        case let .skipped(reason):
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(plan.relativePath.isEmpty ? reason : plan.relativePath)
                    .strikethrough(!plan.relativePath.isEmpty)
            }
            .help("Skipped: \(reason)")
        }
    }
}
