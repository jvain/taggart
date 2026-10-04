import SwiftUI
import TaggartCore

/// Applies a quick action (case conversion, text replacement, tidying spaces)
/// to tags of the selected files, with a before/after preview.
struct QuickActionsSheet: View {
    let ids: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    // Remembered between uses.
    @AppStorage("quickActionKind") private var kind = "case"
    @AppStorage("quickActionCase") private var caseStyle = QuickAction.CaseStyle.titleCase.rawValue
    @AppStorage("quickActionFind") private var find = ""
    @AppStorage("quickActionReplacement") private var replacement = ""
    @AppStorage("quickActionMatchCase") private var matchCase = false
    @AppStorage("quickActionRegularExpression") private var regularExpression = false
    @AppStorage("quickActionField") private var fieldChoice = "all"

    /// The preview lists at most this many changes, to stay responsive.
    private static let previewLimit = 1000

    private var action: QuickAction {
        switch kind {
        case "replace":
            .replace(find: find, with: replacement, matchCase: matchCase, regularExpression: regularExpression)
        case "spaces":
            .cleanUpSpaces
        default:
            .changeCase(QuickAction.CaseStyle(rawValue: caseStyle) ?? .titleCase)
        }
    }

    private var fields: [LogicalField] {
        fieldChoice == "all" ? QuickAction.fields : [LogicalField(rawValue: fieldChoice) ?? .title]
    }

    var body: some View {
        let plan = controller.library.planQuickAction(action, fields: fields, in: ids)
        let changes = (try? plan.get()) ?? []
        let fileCount = Set(changes.map(\.itemID)).count

        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? "Format Tags for 1 File" : "Format Tags for \(ids.count) Files")
                .font(.title3.bold())

            Picker("Action", selection: $kind) {
                Text("Change Case").tag("case")
                Text("Replace Text").tag("replace")
                Text("Clean Up Spaces").tag("spaces")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case "replace":
                replaceOptions
            case "spaces":
                Text("Removes spaces at the start and end of each tag, and turns repeated spaces into one.")
                    .foregroundStyle(.secondary)
            default:
                Picker("Case", selection: $caseStyle) {
                    ForEach(QuickAction.CaseStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Picker("Apply to:", selection: $fieldChoice) {
                Text("All text tags").tag("all")
                Divider()
                ForEach(QuickAction.fields) { field in
                    Text(field.label).tag(field.rawValue)
                }
            }
            .fixedSize()

            if case let .failure(error) = plan {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Table(Array(changes.prefix(Self.previewLimit))) {
                TableColumn("File") { change in
                    Text(change.url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(change.url.path)
                }
                .width(min: 100, ideal: 160)
                TableColumn("Tag") { change in
                    Text(change.field.label)
                }
                .width(min: 50, ideal: 80)
                TableColumn("Before") { change in
                    Text(change.before)
                        .foregroundStyle(.secondary)
                        .help(change.before)
                }
                TableColumn("After") { change in
                    Text(change.after)
                        .help(change.after)
                }
            }
            .frame(minHeight: 220)

            Text(summary(changes: changes.count, files: fileCount))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("⌘Z undoes it; save with ⌘S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fileCount == 1 ? "Apply to 1 File" : "Apply to \(fileCount) Files") {
                    controller.applyQuickAction(action, fields: fields, to: ids)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changes.isEmpty)
            }
        }
        // Keep the content at the top when an action has fewer options.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 580)
    }

    private var replaceOptions: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Find:")
                    .gridColumnAlignment(.trailing)
                TextField("Find", text: $find)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            GridRow {
                Text("Replace with:")
                TextField("Replace with", text: $replacement, prompt: Text("Nothing (removes the text)"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                HStack(spacing: 16) {
                    Toggle("Match case", isOn: $matchCase)
                    Toggle("Regular expression", isOn: $regularExpression)
                        .help("Find is a regular expression; in Replace with, $1, $2… insert its groups.")
                }
            }
        }
    }

    private func summary(changes: Int, files: Int) -> String {
        guard changes > 0 else { return "Nothing to change." }
        var text = "\(changes == 1 ? "1 tag" : "\(changes) tags") in \(files == 1 ? "1 file" : "\(files) files") will change."
        if changes > Self.previewLimit {
            text += " The first \(Self.previewLimit) are shown."
        }
        return text
    }
}
