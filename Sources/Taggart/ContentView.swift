import SwiftUI
import TaggartCore

struct ContentView: View {
    @Environment(AppController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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
                        Text("Drop audio files or folders here, or press ⌘O.\nFLAC, MP3, M4A (AAC and ALAC), Ogg Vorbis and Opus are supported.")
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
                    Button("Format Tags", systemImage: "textformat") { controller.showQuickActionsSheet() }
                        .help("Format the selected files' tags: change case, replace text (⇧⌘K)")
                        .disabled(controller.selection.isEmpty || library.isSaving)
                    Button("Settings", systemImage: "gearshape") { openSettings() }
                        .help("Settings (⌘,)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                        .help("Show or hide the tag editor")
                }
            }
            .navigationSubtitle(subtitle)
            .background(DocumentEditedMarker(isEdited: library.hasUnsavedChanges))
            // Tags are names, titles and IDs: never "correct" them.
            .autocorrectionDisabled()
            .background(AutoFillWarmUp())
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
            .sheet(item: $controller.tagsFromNamesRequest) { request in
                TagsFromNamesSheet(ids: request.ids)
                    .environment(controller)
            }
            .sheet(item: $controller.quickActionsRequest) { request in
                QuickActionsSheet(ids: request.ids)
                    .environment(controller)
            }
            .sheet(item: $controller.trackNumbersRequest) { request in
                TrackNumbersSheet(ids: request.ids)
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

/// Shows the standard unsaved-changes dot in the window's close button (and
/// beside the window's name in the Window menu).
private struct DocumentEditedMarker: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ view: MarkerView, context: Context) {
        view.isEdited = isEdited
    }

    final class MarkerView: NSView {
        var isEdited = false {
            didSet { window?.isDocumentEdited = isEdited }
        }

        // The view joins the window after the first update.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isDocumentEdited = isEdited
        }
    }
}

/// Works around a macOS 26 quirk. The first time any text field in an app gets
/// keyboard focus, macOS sets up its AutoFill panel, which briefly takes key
/// status from the window: the field's focus ring disappears and animates in
/// again, and an empty panel can flash. Focusing an invisible field once, when
/// the window opens, gets that setup done before the user clicks anything.
private struct AutoFillWarmUp: NSViewRepresentable {
    func makeNSView(context: Context) -> WarmUpView {
        WarmUpView()
    }

    func updateNSView(_ view: WarmUpView, context: Context) {}

    final class WarmUpView: NSView {
        private var hasWarmedUp = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !hasWarmedUp, let window, let contentView = window.contentView else { return }
            hasWarmedUp = true

            // Transparent, and outside the window's visible area.
            let field = NSTextField(frame: NSRect(x: -10_000, y: -10_000, width: 20, height: 20))
            field.alphaValue = 0
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.setAccessibilityElement(false)
            contentView.addSubview(field)

            DispatchQueue.main.async {
                let previous = window.firstResponder
                window.makeFirstResponder(field)
                // macOS finishes its setup within about 0.3 s of the focus.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    // Hand focus back, unless the user has already moved it.
                    if (window.firstResponder as? NSTextView)?.delegate === field {
                        window.makeFirstResponder(previous)
                    }
                    field.removeFromSuperview()
                }
            }
        }
    }
}
