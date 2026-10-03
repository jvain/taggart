import SwiftUI
import TaggartCore

struct ContentView: View {
    @Environment(AppController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @ViewState private var showInspector = true
    @ViewState private var query = ""
    @ViewState private var isDropTargeted = false

    var body: some View {
        @Bindable var controller = controller
        let library = controller.library

        FileTable(items: filteredItems, selection: $controller.selection)
            .overlay {
                if library.items.isEmpty && !library.isLoading {
                    ContentUnavailableView {
                        Label("No Files", systemImage: "music.note.list")
                    } description: {
                        Text("Drop FLAC or MP3 files or folders here, or press ⌘O.")
                    } actions: {
                        Button("Open…") { controller.showOpenPanel() }
                    }
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                controller.add(urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBar(library: library, selectionCount: controller.selection.count)
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Filter")
            .inspector(isPresented: $showInspector) {
                TagInspector()
                    .inspectorColumnWidth(min: 300, ideal: 330, max: 460)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Open", systemImage: "plus") { controller.showOpenPanel() }
                        .help("Add files or folders (⌘O)")
                    Button("Save", systemImage: "square.and.arrow.down") { Task { await controller.save() } }
                        .help("Save all modified files (⌘S)")
                        .disabled(!library.hasUnsavedChanges || library.isSaving)
                    Button("Rename", systemImage: "rectangle.and.pencil.and.ellipsis") { controller.showRenameSheet() }
                        .help("Rename the selected files from their tags (⇧⌘R)")
                        .disabled(controller.selection.isEmpty || library.isSaving)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                        .help("Show or hide the tag editor")
                }
            }
            .navigationSubtitle(subtitle)
            .alert(
                controller.alert?.title ?? "",
                isPresented: Binding(get: { controller.alert != nil }, set: { if !$0 { controller.alert = nil } }),
                presenting: controller.alert
            ) { _ in
                Button("OK") {}
            } message: { alert in
                Text(alert.messages.prefix(10).joined(separator: "\n\n")
                    + (alert.messages.count > 10 ? "\n\n…and \(alert.messages.count - 10) more." : ""))
            }
            .sheet(item: $controller.renameRequest) { request in
                RenameSheet(ids: request.ids)
                    .environment(controller)
            }
            .onAppear {
                controller.undoManager = undoManager
                controller.openWindow = openWindow
            }
            .onChange(of: undoManager) { controller.undoManager = undoManager }
            .onChange(of: query) {
                // Never edit files the filter hides.
                controller.selection.formIntersection(filteredItems.map(\.id))
            }
    }

    private var filteredItems: [AudioFileItem] {
        let items = controller.library.items
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { item in
            [item.fileName, item.title, item.artist, item.album, item.albumArtist, item.genre]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var subtitle: String {
        let modified = controller.library.dirtyItems.count
        return modified > 0 ? "\(modified) modified" : ""
    }
}

private struct StatusBar: View {
    let library: Library
    let selectionCount: Int

    var body: some View {
        HStack(spacing: 12) {
            if library.isLoading {
                ProgressView(value: Double(library.loadProgress.done), total: Double(max(library.loadProgress.total, 1)))
                    .frame(width: 120)
                Text("Loading \(library.loadProgress.done) of \(library.loadProgress.total)…")
            } else if library.isSaving {
                ProgressView().controlSize(.small)
                Text("Saving…")
            } else {
                Text(summary)
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        let total = library.items.count
        var parts = [total == 1 ? "1 file" : "\(total) files"]
        if selectionCount > 0 {
            parts.append("\(selectionCount) selected")
        }
        let modified = library.dirtyItems.count
        if modified > 0 {
            parts.append("\(modified) modified")
        }
        return parts.joined(separator: " · ")
    }
}
