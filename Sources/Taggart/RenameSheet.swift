import SwiftUI
import TaggartCore

/// Previews renaming the selected files from their tags, then renames them.
struct RenameSheet: View {
    let ids: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @AppStorage("renamePattern") private var patternText = "%track% - %title%"

    var body: some View {
        let pattern = RenamePattern(patternText)
        let plans = controller.library.planRename(ids, pattern: pattern)
        let renameCount = plans.filter { $0.status == .rename }.count

        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? "Rename File from Tags" : "Rename \(ids.count) Files from Tags")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                TextField("Pattern", text: $patternText, prompt: Text("%track% - %title%"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .labelsHidden()
                FlowLayout(spacing: 6) {
                    ForEach(RenamePattern.tokens) { token in
                        Button(token.label) { patternText += token.placeholder }
                            .controlSize(.small)
                            .help("Add \(token.placeholder) to the pattern")
                    }
                }
                if let error = pattern.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("The file extension is kept. “/” and “:” in tags become “-”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    controller.rename(plans)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameCount == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 720, minHeight: 500, idealHeight: 560)
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
                Text(plan.destination.lastPathComponent)
                if !plan.missing.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("No \(plan.missing.map(\.label).joined(separator: ", ")) in this file's tags.")
                }
            }
        case .unchanged:
            Text("\(plan.destination.lastPathComponent) (unchanged)")
                .foregroundStyle(.secondary)
        case let .skipped(reason):
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(plan.destination.lastPathComponent.isEmpty ? reason : plan.destination.lastPathComponent)
                    .strikethrough(!plan.destination.lastPathComponent.isEmpty)
            }
            .help("Skipped: \(reason)")
        }
    }
}

/// Lays out views left to right, wrapping onto new rows as needed.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
