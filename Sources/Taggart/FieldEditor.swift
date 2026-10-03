import AppKit
import SwiftUI
import TaggartCore

/// A text field for one value across the selection. Shows a "Multiple values"
/// prompt when the files disagree, and applies the typed value to every file
/// that was selected when editing began, on Return or when focus leaves the
/// field. Clearing the field (with its clear button) commits an empty value.
struct FieldEditor: View {
    let label: String
    let ids: Set<AudioFileItem.ID>
    let state: FieldState
    let multiline: Bool
    let mixedPrompt: String
    let help: String
    /// Filters typed text (e.g. digits only), beeping when it drops characters.
    let allowedInput: ((String) -> String)?
    /// Completions for the text being typed, if this field offers any.
    let suggest: ((String) -> [InputSuggestion])?
    let commit: (String, Set<AudioFileItem.ID>) -> Void

    init(
        label: String,
        ids: Set<AudioFileItem.ID>,
        state: FieldState,
        multiline: Bool = false,
        mixedPrompt: String = "Multiple values",
        help: String = "",
        allowedInput: ((String) -> String)? = nil,
        suggest: ((String) -> [InputSuggestion])? = nil,
        commit: @escaping (String, Set<AudioFileItem.ID>) -> Void
    ) {
        self.label = label
        self.ids = ids
        self.state = state
        self.multiline = multiline
        self.mixedPrompt = mixedPrompt
        self.help = help
        self.allowedInput = allowedInput
        self.suggest = suggest
        self.commit = commit
    }

    @ViewState private var text = ""
    /// The value last shown from the files, as opposed to typed by the user.
    @ViewState private var syncedText = ""
    @ViewState private var editing: (ids: Set<AudioFileItem.ID>, state: FieldState)?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: $text, prompt: prompt, axis: multiline ? .vertical : .horizontal)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .labelsHidden()
                .lineLimit(multiline ? 2...5 : 1...1)
                .modifier(Suggestions(items: isFocused ? suggest?(text) ?? [] : []))
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
                .onChange(of: text) { rejectDisallowedInput() }
                .help(state == .mixed ? "The selected files have different values. Type to replace them all." : help)
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
            .help(ids.count > 1 ? "Clear \(label) in all selected files" : "Clear \(label)")
            .opacity(state == .uniform("") ? 0 : 1)
            .disabled(state == .uniform(""))
        }
    }

    private var prompt: Text {
        // An empty prompt; otherwise the field would repeat its label.
        state == .mixed ? Text(mixedPrompt) : Text(verbatim: "")
    }

    private func syncText(force: Bool = false) {
        guard force || !isFocused else { return }
        if case let .uniform(value) = state {
            syncedText = value
        } else {
            syncedText = ""
        }
        text = syncedText
    }

    /// Drops characters the field can't hold, with a beep, as an AppKit number
    /// field would. Only typed text is checked: values shown from the files
    /// (even odd ones like "A1" in a number field) stay as they are until edited.
    private func rejectDisallowedInput() {
        guard let allowedInput, isFocused, text != syncedText else { return }
        let allowed = allowedInput(text)
        if allowed != text {
            NSSound.beep()
            text = allowed
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

/// One completion offered under a text field.
struct InputSuggestion: Identifiable, Hashable {
    /// What the list shows.
    var label: String
    /// The whole field text if it's picked.
    var completion: String
    var id: String { completion }
}

/// A list of completions under a text field while typing (macOS 15 and later).
struct Suggestions: ViewModifier {
    let items: [InputSuggestion]

    func body(content: Content) -> some View {
        // Only the OS version decides the branch: switching on `items` would
        // replace the text field and end editing.
        if #available(macOS 15, *) {
            content.textInputSuggestions {
                ForEach(items) { item in
                    Text(item.label)
                        .textInputCompletion(item.completion)
                }
            }
        } else {
            content
        }
    }
}
