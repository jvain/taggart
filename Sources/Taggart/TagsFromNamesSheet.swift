import SwiftUI
import TaggartCore

/// Previews reading tags from the selected files' names, then sets them.
struct TagsFromNamesSheet: View {
    let ids: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tagsFromNamesPattern") private var patternText = "%track% - %title%"
    @AppStorage("tagsFromNamesUnderscoresAsSpaces") private var underscoresAsSpaces = false

    var body: some View {
        let pattern = TagsFromNamePattern(patternText)
        let plans = pattern.error == nil
            ? controller.library.planTagsFromNames(ids, pattern: pattern, underscoresAsSpaces: underscoresAsSpaces)
            : []
        let matching = plans.filter { $0.tags != nil }.count
        // Show as many trailing folder names as the pattern reads.
        let pathDepth = pattern.error == nil ? patternText.filter { $0 == "/" }.count + 1 : 1

        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? "Tags from File Name" : "Tags from \(ids.count) File Names")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                PatternEditor(text: $patternText, tokens: PatternToken.tagsFromName)
                if let error = pattern.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("The file extension is ignored. Use “/” to read folder names too, e.g. %artist%/%album%/%track% - %title%, and %skip% for text you don't want.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Treat underscores as spaces", isOn: $underscoresAsSpaces)
            }

            Table(plans) {
                TableColumn(pathDepth > 1 ? "Folders and File" : "File") { plan in
                    Text(plan.url.pathComponents.suffix(pathDepth).joined(separator: "/"))
                        .foregroundStyle(.secondary)
                        .help(plan.url.path)
                }
                // Leave most of the width to the tags read.
                .width(min: 140, ideal: 220)
                TableColumn("Tags Read") { plan in
                    ReadTagsCell(plan: plan)
                }
            }
            .frame(minHeight: 220)

            Text(summary(plans))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("Only the tags in the pattern change. ⌘Z undoes it; save with ⌘S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(matching == 1 ? "Set Tags for 1 File" : "Set Tags for \(matching) Files") {
                    controller.applyTagsFromNames(plans)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(matching == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
    }

    private func summary(_ plans: [TagsFromNamePlan]) -> String {
        guard !plans.isEmpty else { return "" }
        let matching = plans.filter { $0.tags != nil }.count
        let other = plans.count - matching
        var text = matching == 1 ? "1 name matches" : "\(matching) names match"
        if other > 0 {
            text += other == 1 ? " · 1 doesn't and is skipped" : " · \(other) don't and are skipped"
        }
        return text
    }
}

private struct ReadTagsCell: View {
    let plan: TagsFromNamePlan

    var body: some View {
        if plan.tags == nil {
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Doesn't match the pattern")
                    .foregroundStyle(.secondary)
            }
            .help("Skipped: the name doesn't match the pattern.")
        } else {
            Text(plan.summary)
                .help(plan.summary)
        }
    }
}
