import SwiftUI
import TaggartCore

/// A button that inserts a placeholder into a pattern.
struct PatternToken: Identifiable {
    var label: String
    var placeholder: String
    var help: String
    var id: String { placeholder }

    /// For renaming files from tags.
    static let rename = RenamePattern.tokens.map {
        PatternToken(label: $0.label, placeholder: $0.placeholder, help: "Insert \($0.placeholder)")
    } + [PatternToken(label: "Folder /", placeholder: "/", help: "Insert “/” to start a new folder level")]

    /// For reading tags from file names.
    static let tagsFromName = TagsFromNamePattern.tokens.map {
        PatternToken(label: $0.label, placeholder: $0.placeholder,
                     help: $0.name == "skip" ? "Insert %skip% to skip over text you don't want" : "Insert \($0.placeholder)")
    } + [PatternToken(label: "Folder /", placeholder: "/", help: "Insert “/” to read folder names too")]
}

/// The pattern field and the placeholder buttons. On macOS 15 and later the
/// buttons insert at the cursor (replacing any selection); earlier systems
/// lack the text selection API, so there they add to the end.
struct PatternEditor: View {
    @Binding var text: String
    let tokens: [PatternToken]

    var body: some View {
        if #available(macOS 15, *) {
            CursorPatternEditor(text: $text, tokens: tokens)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                PatternField(text: $text)
                PlaceholderButtons(tokens: tokens) { text += $0 }
            }
        }
    }
}

@available(macOS 15, *)
private struct CursorPatternEditor: View {
    @Binding var text: String
    let tokens: [PatternToken]
    @ViewState private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PatternField(text: $text, selection: $selection)
                .focused($isFocused)
            PlaceholderButtons(tokens: tokens, insert: insert)
        }
    }

    private func insert(_ placeholder: String) {
        var range = text.endIndex..<text.endIndex
        if case let .selection(selected) = selection?.indices,
           selected.lowerBound >= text.startIndex, selected.upperBound <= text.endIndex {
            range = selected
        }
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        text.replaceSubrange(range, with: placeholder)
        // Put the cursor after the inserted placeholder, ready for more typing.
        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + placeholder.count))
        isFocused = true
    }
}

private struct PatternField: View {
    @Binding var text: String
    var selection: Any?

    init(text: Binding<String>) {
        _text = text
    }

    @available(macOS 15, *)
    init(text: Binding<String>, selection: Binding<TextSelection?>) {
        _text = text
        self.selection = selection
    }

    var body: some View {
        Group {
            if #available(macOS 15, *), let selection = selection as? Binding<TextSelection?> {
                TextField("Pattern", text: $text, selection: selection, prompt: Text(verbatim: "%track% - %title%"))
            } else {
                TextField("Pattern", text: $text, prompt: Text(verbatim: "%track% - %title%"))
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.body.monospaced())
        .labelsHidden()
    }
}

private struct PlaceholderButtons: View {
    let tokens: [PatternToken]
    let insert: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tokens) { token in
                Button(token.label) { insert(token.placeholder) }
                    .controlSize(.small)
                    .help(token.help)
            }
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
