import SwiftUI
import TaggartCore

struct FileTable: View {
    let items: [AudioFileItem]
    @Binding var selection: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @ViewState private var sortOrder: [KeyPathComparator<AudioFileItem>] = []
    @SceneStorage("FileTableColumns") private var columns = TableColumnCustomization<AudioFileItem>()
    @ViewState private var tableReference = TableReference()

    var body: some View {
        // Sorted only when the files or the sort change (see SortedRows).
        let rows = controller.sortedRows.rows(of: items, sortOrder: sortOrder)
        Table(rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("", value: \AudioFileItem.dirtySortKey) { item in
                StatusIcon(item: item)
            }
            .width(18)
            .customizationID("status")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("File", value: \AudioFileItem.fileName) { item in
                Text(item.fileName).help(item.url.path)
            }
            .width(min: 100, ideal: 150)
            .customizationID("file")

            TableColumn("Title", value: \AudioFileItem.title) { cell($0, .title, rows) }
                .width(min: 80, ideal: 140)
                .customizationID("title")
            TableColumn("Artist", value: \AudioFileItem.artist) { cell($0, .artist, rows) }
                .width(min: 60, ideal: 110)
                .customizationID("artist")
            TableColumn("Album", value: \AudioFileItem.album) { cell($0, .album, rows) }
                .width(min: 60, ideal: 110)
                .customizationID("album")

            Group {
                TableColumn("Album Artist", value: \AudioFileItem.albumArtist) { cell($0, .albumArtist, rows) }
                    .width(min: 80, ideal: 130)
                    .customizationID("albumArtist")
                    .defaultVisibility(.hidden)
                TableColumn("#", value: \AudioFileItem.trackSortKey) { cell($0, .trackNumber, rows) }
                .width(min: 28, ideal: 34)
                .customizationID("track")
                TableColumn("Disc", value: \AudioFileItem.discSortKey) { cell($0, .discNumber, rows) }
                .width(min: 28, ideal: 34)
                .customizationID("disc")
                .defaultVisibility(.hidden)
                TableColumn("Year", value: \AudioFileItem.year) { cell($0, .date, rows) }
                    .width(min: 36, ideal: 44)
                    .customizationID("year")
                TableColumn("Genre", value: \AudioFileItem.genre) { cell($0, .genre, rows) }
                    .width(min: 50, ideal: 80)
                    .customizationID("genre")
            }

            Group {
                TableColumn("Format", value: \AudioFileItem.formatSummary) { Text($0.formatSummary) }
                    .width(min: 60, ideal: 110)
                    .customizationID("format")
                    .defaultVisibility(.hidden)
                TableColumn("Time", value: \AudioFileItem.duration) { item in
                    Text(Duration.seconds(item.duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                }
                .width(min: 40, ideal: 48)
                .customizationID("time")
                TableColumn("Cover", value: \AudioFileItem.artworkSortKey) { item in
                    CoverThumbnail(item: item, thumbnails: controller.library.thumbnails)
                }
                .width(min: 36, ideal: 40)
                .customizationID("cover")
            }
        }
        .contextMenu(forSelectionType: AudioFileItem.ID.self) { ids in
            if !ids.isEmpty {
                Button("Reveal in Finder") {
                    controller.selection = ids
                    controller.revealSelectedInFinder()
                }
                Button("Rename from Tags…") {
                    controller.selection = ids
                    controller.showRenameSheet()
                }
                Button("Tags from File Names…") {
                    controller.selection = ids
                    controller.showTagsFromNamesSheet()
                }
                Button("Format Tags…") {
                    controller.selection = ids
                    controller.showFormatTagsSheet()
                }
                let savedSteps = FormatStepStore.savedLists
                if !savedSteps.isEmpty {
                    Menu("Format Tags With") {
                        ForEach(savedSteps) { list in
                            Button(list.name) {
                                controller.selection = ids
                                controller.runFormatSteps(list)
                            }
                        }
                    }
                }
                Button("Number Tracks…") {
                    controller.selection = ids
                    controller.showTrackNumbersSheet()
                }
                Button("Look Up on MusicBrainz…") {
                    controller.selection = ids
                    controller.showMusicBrainzSheet()
                }
                Button("Revert") {
                    controller.selection = ids
                    controller.revertSelected()
                }
                Divider()
                Button("Copy Tags") {
                    controller.selection = ids
                    controller.copyTags()
                }
                Button("Paste Tags") {
                    controller.selection = ids
                    controller.pasteTags()
                }
                .disabled(controller.copiedTags == nil || controller.library.isSaving)
                Divider()
                Button("Remove from List") {
                    controller.selection = ids
                    controller.removeSelected()
                }
            }
        } primaryAction: { _ in
            // Double-click: edit the clicked cell, if its column is a tag.
            beginEditingClickedCell(rows)
        }
        .onDeleteCommand { controller.removeSelected() }
        // Return edits the title of the first selected row.
        .onKeyPress(.return) {
            guard controller.editingCell == nil, !controller.library.isSaving,
                  let first = rows.first(where: { selection.contains($0.id) })
            else { return .ignored }
            controller.editingCell = EditingCell(id: first.id, field: .title)
            return .handled
        }
        .background(FitColumnsOnAppear(reference: tableReference))
    }

    private func cell(_ item: AudioFileItem, _ field: LogicalField, _ rows: [AudioFileItem]) -> some View {
        let cell = EditingCell(id: item.id, field: field)
        return EditableCell(
            item: item,
            field: field,
            isEditing: controller.editingCell == cell,
            commit: { text, end in commit(text, in: cell, end: end, rows: rows) },
            cancel: {
                if controller.editingCell == cell {
                    controller.editingCell = nil
                    focusTable()
                }
            }
        )
    }

    /// The editable columns, by header title.
    private static let editableFields: [String: LogicalField] = [
        "Title": .title, "Artist": .artist, "Album": .album, "Album Artist": .albumArtist,
        "#": .trackNumber, "Disc": .discNumber, "Year": .date, "Genre": .genre,
    ]

    /// Starts editing the cell that was double-clicked. SwiftUI reports only
    /// the rows, so the column comes from the underlying NSTableView.
    private func beginEditingClickedCell(_ rows: [AudioFileItem]) {
        guard !controller.library.isSaving, let table = tableReference.table else { return }
        let row = table.clickedRow
        let column = table.clickedColumn
        guard rows.indices.contains(row), table.tableColumns.indices.contains(column),
              let field = Self.editableFields[table.tableColumns[column].title]
        else { return }
        selection = [rows[row].id]
        controller.editingCell = EditingCell(id: rows[row].id, field: field)
    }

    /// Saves a cell edit (as one undoable step). After Return, editing moves to
    /// the same column on the next row, which gets selected and scrolled to;
    /// on the last row, editing just ends.
    private func commit(_ text: String, in cell: EditingCell, end: CellEditEnd, rows: [AudioFileItem]) {
        if let item = controller.library.item(cell.id),
           text.trimmingCharacters(in: .whitespacesAndNewlines) != item.value(cell.field) {
            controller.apply(.setField(cell.field, text), to: [cell.id])
        }
        // Another cell may already be being edited (it was double-clicked).
        guard controller.editingCell == cell else { return }
        guard end == .enter else {
            controller.editingCell = nil
            return
        }
        if let index = rows.firstIndex(where: { $0.id == cell.id }), index + 1 < rows.count {
            let next = rows[index + 1]
            selection = [next.id]
            controller.editingCell = EditingCell(id: next.id, field: cell.field)
            tableReference.table?.scrollRowToVisible(index + 1)
        } else {
            controller.editingCell = nil
            focusTable()
        }
    }

    /// Gives keyboard focus back to the list, so arrow keys work again.
    private func focusTable() {
        if let table = tableReference.table {
            table.window?.makeFirstResponder(table)
        }
    }
}

private struct StatusIcon: View {
    let item: AudioFileItem

    var body: some View {
        if let error = item.error {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(error)
        } else if item.isDirty {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.tint)
                .help("Modified")
        }
    }
}

private struct CoverThumbnail: View {
    let item: AudioFileItem
    let thumbnails: ThumbnailCache

    var body: some View {
        if let artwork = item.edited.primaryArtwork, let image = thumbnails[artwork.digest] {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .help("\(artwork.width) × \(artwork.height)")
        }
    }
}

/// Fits the table's columns to its width when it first appears.
///
/// The columns start at their ideal widths, and the underlying NSTableView
/// only refits them when its size changes. In a window narrower than the ideal
/// widths (macOS restores the last window size), the list would start out
/// scrolling sideways until the next resize. SwiftUI has no API for this, so
/// this asks the nearest NSTableView directly; if there is none, it does nothing.
private struct FitColumnsOnAppear: NSViewRepresentable {
    let reference: TableReference

    func makeNSView(context: Context) -> FittingView {
        FittingView(reference: reference)
    }

    func updateNSView(_ view: FittingView, context: Context) {}

    final class FittingView: NSView {
        private var hasFitted = false
        private let reference: TableReference

        init(reference: TableReference) {
            self.reference = reference
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fitOnce()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            fitOnce()
        }

        private func fitOnce() {
            guard !hasFitted, window != nil, frame.width > 0 else { return }
            hasFitted = true
            // After the current layout pass, once the table has its size.
            DispatchQueue.main.async { [weak self] in
                guard let self, let table = nearestTable() else { return }
                reference.table = table
                table.sizeToFit()
            }
        }

        /// The table this view is the background of: the first NSTableView found
        /// searching outward from here.
        private func nearestTable() -> NSTableView? {
            var ancestor = superview
            while let view = ancestor {
                if let table = Self.firstTable(in: view) {
                    return table
                }
                ancestor = view.superview
            }
            return nil
        }

        private static func firstTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView {
                return table
            }
            for subview in view.subviews {
                if let table = firstTable(in: subview) {
                    return table
                }
            }
            return nil
        }
    }
}

/// The NSTableView under the SwiftUI table, once found: used to scroll to the
/// row being edited and to give the list keyboard focus back.
final class TableReference {
    weak var table: NSTableView?
}
