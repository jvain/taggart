import AppKit
import SwiftUI
import TaggartCore

/// A cell of the file list that is being, or can be, edited in place.
struct EditingCell: Hashable {
    var id: AudioFileItem.ID
    var field: LogicalField
}

/// How editing a list cell ended.
enum CellEditEnd {
    /// Return: save, then edit the same column on the next row.
    case enter
    /// Focus moved elsewhere (a click outside the cell): save.
    case focusLost
}

/// A tag shown in the file list, or its text field while it's being edited.
/// (Double-clicks are handled by the table, which knows the clicked column.)
struct EditableCell: View {
    let item: AudioFileItem
    let field: LogicalField
    let isEditing: Bool
    let commit: (String, CellEditEnd) -> Void
    let cancel: () -> Void

    var body: some View {
        let value = item.value(field)
        if isEditing {
            CellTextField(initial: value, field: field, commit: commit, cancel: cancel)
        } else {
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The text field of a list cell being edited. Takes focus when it appears;
/// Return saves (and moves on), Escape cancels, and losing focus saves.
private struct CellTextField: View {
    let field: LogicalField
    let commit: (String, CellEditEnd) -> Void
    let cancel: () -> Void

    @ViewState private var text: String
    private let initial: String
    /// Set once the edit has been saved or cancelled, so it ends only once.
    @ViewState private var hasEnded = false
    @FocusState private var isFocused: Bool

    init(initial: String, field: LogicalField, commit: @escaping (String, CellEditEnd) -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        self.field = field
        self.commit = commit
        self.cancel = cancel
        _text = ViewState(wrappedValue: initial)
    }

    var body: some View {
        TextField(field.label, text: $text)
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($isFocused)
            .onAppear {
                // After the cell is in the window, or focus doesn't stick.
                DispatchQueue.main.async { isFocused = true }
            }
            .onSubmit { end(.enter) }
            // Inside a text field, Escape goes to the field itself (for word
            // completion), so catch the key rather than the exit command.
            .onKeyPress(.escape) {
                cancelEdit()
                return .handled
            }
            .onExitCommand(perform: cancelEdit)
            .onChange(of: isFocused) {
                if !isFocused {
                    end(.focusLost)
                }
            }
            // Removed without losing focus first (e.g. another cell was double-clicked).
            .onDisappear { end(.focusLost) }
            .onChange(of: text) { rejectDisallowedInput() }
    }

    private func cancelEdit() {
        guard !hasEnded else { return }
        hasEnded = true
        cancel()
    }

    private func end(_ reason: CellEditEnd) {
        guard !hasEnded else { return }
        hasEnded = true
        commit(text, reason)
    }

    /// Number fields take digits only (Track and Disc also "3/12"), beeping at
    /// anything else, as in the side panel.
    private func rejectDisallowedInput() {
        guard field.isNumeric, text != initial else { return }
        let allowed = field.allowedInput(text)
        if allowed != text {
            NSSound.beep()
            text = allowed
        }
    }
}
