import SwiftUI
import TaggartCore

/// Edits the tags of every selected file at once.
struct TagInspector: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        let ids = controller.selection
        if ids.isEmpty {
            ContentUnavailableView(
                "No Selection",
                systemImage: "music.note",
                description: Text("Select one or more files to edit their tags.")
            )
        } else {
            Form {
                Section {
                    ArtworkWell(ids: ids)
                } header: {
                    Text(header(for: ids))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Section {
                    row(.title, ids)
                    row(.artist, ids)
                    row(.album, ids)
                    row(.albumArtist, ids)
                    labeled("Track") {
                        numberPair(.trackNumber, .trackTotal, ids)
                    }
                    labeled("Disc") {
                        numberPair(.discNumber, .discTotal, ids)
                    }
                    row(.date, ids)
                    row(.genre, ids)
                    row(.composer, ids)
                    row(.comment, ids, multiline: true)
                } footer: {
                    Text("Separate multiple artists, genres or composers with “;”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(controller.library.isSaving)
        }
    }

    private func header(for ids: Set<AudioFileItem.ID>) -> String {
        if ids.count == 1, let id = ids.first, let item = controller.library.item(id) {
            return item.fileName
        }
        return "\(ids.count) files selected"
    }

    private func row(_ field: LogicalField, _ ids: Set<AudioFileItem.ID>, multiline: Bool = false) -> some View {
        labeled(field.label) {
            editor(field, ids, multiline: multiline)
        }
    }

    /// A label in a fixed-width column, so every field starts at the same place
    /// and fills the rest of the row.
    private func labeled(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: 84, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func editor(_ field: LogicalField, _ ids: Set<AudioFileItem.ID>, multiline: Bool = false) -> some View {
        FieldEditor(
            field: field,
            ids: ids,
            state: controller.library.fieldState(field, for: ids),
            multiline: multiline
        ) { value, targets in
            controller.apply(.setField(field, value), to: targets)
        }
    }

    private func numberPair(_ number: LogicalField, _ total: LogicalField, _ ids: Set<AudioFileItem.ID>) -> some View {
        HStack(spacing: 6) {
            editor(number, ids)
                .frame(minWidth: 56, maxWidth: 80)
            Text("of")
                .foregroundStyle(.secondary)
                .fixedSize()
            editor(total, ids)
                .frame(minWidth: 56, maxWidth: 80)
        }
    }
}

/// A text field for one tag across the selection. Shows "Multiple values"
/// when the files disagree, and applies the typed value to every file that
/// was selected when editing began, on Return or when focus leaves the field.
private struct FieldEditor: View {
    let field: LogicalField
    let ids: Set<AudioFileItem.ID>
    let state: FieldState
    let multiline: Bool
    let commit: (String, Set<AudioFileItem.ID>) -> Void

    @ViewState private var text = ""
    @ViewState private var editing: (ids: Set<AudioFileItem.ID>, state: FieldState)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(field.label, text: $text, prompt: prompt, axis: multiline ? .vertical : .horizontal)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .labelsHidden()
                .lineLimit(multiline ? 2...5 : 1...1)
                .focused($isFocused)
                .onSubmit(commitIfChanged)
                .onChange(of: isFocused) {
                    if isFocused {
                        editing = (ids, state)
                    } else {
                        commitIfChanged()
                        editing = nil
                        syncText()
                    }
                }
                .onChange(of: state, initial: true) { syncText() }
                .onChange(of: ids) {
                    // Selection changed while editing: commit to the files the edit began with.
                    if isFocused {
                        commitIfChanged()
                        editing = (ids, state)
                        syncText(force: true)
                    }
                }
                .help(state == .mixed ? "The selected files have different values. Type to replace them all." : "")
            // Always laid out, so fields line up whether or not it's shown.
            Button("Clear", systemImage: "xmark.circle.fill") {
                let targets = editing?.ids ?? ids
                text = ""
                commit("", targets)
                // Leaving the field must not re-commit text typed before clearing.
                editing = (targets, .uniform(""))
                isFocused = false
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help(ids.count > 1 ? "Clear \(field.label) in all selected files" : "Clear \(field.label)")
            .opacity(state == .uniform("") ? 0 : 1)
            .disabled(state == .uniform(""))
        }
    }

    private var prompt: Text {
        // An empty prompt; otherwise the field would repeat its label.
        guard state == .mixed else { return Text(verbatim: "") }
        // Number fields are too narrow for the long form.
        return Text(field.isNumeric ? "Mixed" : "Multiple values")
    }

    private func syncText(force: Bool = false) {
        guard force || !isFocused else { return }
        if case let .uniform(value) = state {
            text = value
        } else {
            text = ""
        }
    }

    private func commitIfChanged() {
        let start = editing?.state ?? state
        let targets = editing?.ids ?? ids
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let unchanged = switch start {
        case let .uniform(value): trimmed == value
        // An untouched "Multiple values" field leaves every file as it is.
        case .mixed: trimmed.isEmpty
        }
        guard !unchanged, !targets.isEmpty else { return }
        commit(text, targets)
        editing = (targets, .uniform(trimmed))
    }
}
