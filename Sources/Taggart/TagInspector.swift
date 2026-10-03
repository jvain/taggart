import SwiftUI
import TaggartCore

/// Edits the tags of every selected file at once: the common fields and the
/// artwork, or every tag the files have (All Tags).
struct TagInspector: View {
    @Environment(AppController.self) private var controller
    @AppStorage("inspectorShowsAllTags") private var showsAllTags = false

    var body: some View {
        let ids = controller.selection
        if ids.isEmpty {
            ContentUnavailableView(
                "No Selection",
                systemImage: "music.note",
                description: Text("Select one or more files to edit their tags.")
            )
        } else {
            VStack(spacing: 0) {
                Picker("View", selection: $showsAllTags) {
                    Text("Tags").tag(false)
                    Text("All Tags").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .help("Tags shows the common fields and artwork; All Tags lists every tag in the files.")

                if showsAllTags {
                    AllTagsEditor(ids: ids, header: header(for: ids))
                } else {
                    standardForm(ids)
                }
            }
            .disabled(controller.library.isSaving)
        }
    }

    private func standardForm(_ ids: Set<AudioFileItem.ID>) -> some View {
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
        var suggest: ((String) -> [InputSuggestion])?
        if field == .genre {
            suggest = { text in genreSuggestions(for: text) }
        }
        var allowedInput: ((String) -> String)?
        if field.isNumeric {
            allowedInput = { text in field.allowedInput(text) }
        }
        return FieldEditor(
            label: field.label,
            ids: ids,
            state: controller.library.fieldState(field, for: ids),
            multiline: multiline,
            // Number fields are too narrow for the long form.
            mixedPrompt: field.isNumeric ? "Mixed" : "Multiple values",
            help: help(for: field),
            allowedInput: allowedInput,
            suggest: suggest
        ) { value, targets in
            controller.apply(.setField(field, value), to: targets)
        }
    }

    private func help(for field: LogicalField) -> String {
        switch field {
        case .trackNumber: "A number. Type e.g. 3/12 to set the track total too."
        case .discNumber: "A number. Type e.g. 1/2 to set the disc total too."
        case .trackTotal, .discTotal: "A number."
        default: ""
        }
    }

    private func genreSuggestions(for text: String) -> [InputSuggestion] {
        Genres.suggestions(for: text, preferring: controller.library.genres)
            .map { InputSuggestion(label: $0.genre, completion: $0.completion) }
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
