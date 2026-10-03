import SwiftUI
import TaggartCore

/// Edits the tags of every selected file at once.
struct TagInspector: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        let ids = controller.selection
        let library = controller.library
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
                    field(.title, ids)
                    field(.artist, ids)
                    field(.album, ids)
                    field(.albumArtist, ids)
                    LabeledContent("Track") {
                        numberPair(.trackNumber, .trackTotal, ids)
                    }
                    LabeledContent("Disc") {
                        numberPair(.discNumber, .discTotal, ids)
                    }
                    field(.date, ids)
                    field(.genre, ids)
                    field(.composer, ids)
                    field(.comment, ids, multiline: true)
                } footer: {
                    Text("Separate multiple artists, genres or composers with “;”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(library.isSaving)
        }
    }

    private func header(for ids: Set<URL>) -> String {
        if ids.count == 1, let url = ids.first {
            return url.lastPathComponent
        }
        return "\(ids.count) files selected"
    }

    private func field(_ field: LogicalField, _ ids: Set<URL>, multiline: Bool = false) -> some View {
        FieldEditor(
            field: field,
            ids: ids,
            state: controller.library.fieldState(field, for: ids),
            multiline: multiline
        ) { value, targets in
            controller.apply(.setField(field, value), to: targets)
        }
    }

    private func numberPair(_ number: LogicalField, _ total: LogicalField, _ ids: Set<URL>) -> some View {
        HStack(spacing: 6) {
            field(number, ids)
                .labelsHidden()
                .frame(width: 64)
            Text("of").foregroundStyle(.secondary)
            field(total, ids)
                .labelsHidden()
                .frame(width: 64)
        }
    }
}

/// A text field for one tag across the selection. Shows "Multiple values"
/// when the files disagree, and applies the typed value to every file that
/// was selected when editing began, on Return or when focus leaves the field.
private struct FieldEditor: View {
    let field: LogicalField
    let ids: Set<URL>
    let state: FieldState
    let multiline: Bool
    let commit: (String, Set<URL>) -> Void

    @ViewState private var text = ""
    @ViewState private var editing: (ids: Set<URL>, state: FieldState)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(field.label, text: $text, prompt: prompt, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 1...5 : 1...1)
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
            if state != .uniform("") {
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
            }
        }
    }

    private var prompt: Text? {
        state == .mixed ? Text("Multiple values") : nil
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
