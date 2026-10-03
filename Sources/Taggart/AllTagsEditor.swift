import AppKit
import SwiftUI
import TaggartCore

/// Lists every tag in the selected files under the names TagLib uses for all
/// formats (e.g. MUSICBRAINZ_TRACKID), with a field per value. Tags can be
/// edited, deleted and added; like other edits, changes are saved with ⌘S.
struct AllTagsEditor: View {
    let ids: Set<AudioFileItem.ID>
    let header: String
    @Environment(AppController.self) private var controller
    @ViewState private var newKey = ""
    @ViewState private var newValue = ""

    var body: some View {
        let tags = controller.library.rawTags(for: ids)
        Form {
            Section {
                if tags.isEmpty {
                    Text("No tags.")
                        .foregroundStyle(.secondary)
                }
                ForEach(tags) { tag in
                    RawTagRow(tag: tag, ids: ids)
                }
            } header: {
                Text(header)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } footer: {
                Text("Names are as TagLib reports them for every format; each format stores them in its own way. Artwork is on the Tags tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Add a Tag") {
                addTagForm(present: Set(tags.map(\.key)))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func addTagForm(present: Set<String>) -> some View {
        let (key, keyError) = RawTagKey.validate(newKey)
        let error = newKey.isEmpty ? nil
            : keyError ?? (present.contains(key) ? "\(key) is already there: edit it above." : nil)
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        TextField("New tag", text: $newKey, prompt: Text("New tag, e.g. MOOD"))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .multilineTextAlignment(.leading)
            .labelsHidden()
            .modifier(Suggestions(items: RawTagKey.suggestions(for: newKey, excluding: present)
                .map { InputSuggestion(label: $0, completion: $0) }))
        TextField("Value", text: $newValue, prompt: Text("Value"), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .labelsHidden()
            .lineLimit(1...5)
        HStack(alignment: .firstTextBaseline) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Add Tag") {
                controller.apply(.setTag(key, [value]), to: ids)
                newKey = ""
                newValue = ""
            }
            .disabled(newKey.isEmpty || error != nil || value.isEmpty)
            .help(ids.count > 1 ? "Add the tag to all selected files" : "Add the tag")
        }
    }
}

/// One tag: its name, then a field for each of its values. When the selected
/// files differ, a single "Multiple values" field replaces them all.
private struct RawTagRow: View {
    let tag: RawTag
    let ids: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @ViewState private var isAddingValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Always one line: long names shrink a little, and only then
                // are shortened in the middle (the full name shows on hover).
                Text(tag.key)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(tag.key)
                    .contextMenu {
                        Button("Copy Name") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tag.key, forType: .string)
                        }
                    }
                Spacer(minLength: 0)
                if case .uniform = tag.state {
                    Button("Add Value", systemImage: "plus.circle") { isAddingValue = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Add another value to \(tag.key)")
                }
                Button("Delete", systemImage: "trash") {
                    controller.apply(.setTag(tag.key, []), to: ids)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(ids.count > 1 ? "Delete \(tag.key) from all selected files" : "Delete \(tag.key)")
            }

            switch tag.state {
            case let .uniform(values):
                ForEach(values.indices, id: \.self) { index in
                    FieldEditor(label: tag.key, ids: ids, state: .uniform(values[index]), multiline: true) { text, targets in
                        controller.apply(.setTagValue(tag.key, index: index, text), to: targets)
                    }
                }
                if isAddingValue {
                    FieldEditor(label: "New value", ids: ids, state: .uniform(""), multiline: true) { text, targets in
                        isAddingValue = false
                        controller.apply(.addTagValue(tag.key, text), to: targets)
                    }
                }
            case let .mixed(count):
                // Say when only some files have the tag; typing sets it in all.
                let prompt = count < ids.count ? "In \(count) of \(ids.count) files" : "Multiple values"
                FieldEditor(label: tag.key, ids: ids, state: .mixed, multiline: true, mixedPrompt: prompt) { text, targets in
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    controller.apply(.setTag(tag.key, value.isEmpty ? [] : [value]), to: targets)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
