import SwiftUI
import TaggartCore

/// Runs a list of steps (change case, replace text, set, split or remove
/// tags…) on the selected files' tags, and names if a step says so, with a
/// preview of every change. Lists of steps can be saved and loaded.
struct FormatTagsSheet: View {
    /// In list order.
    let ids: [AudioFileItem.ID]
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @ViewState private var steps = FormatStepStore.currentSteps
    @ViewState private var selectedStepID: FormatStep.ID?
    @ViewState private var savedLists = FormatStepStore.savedLists
    /// The saved list the steps were loaded from or saved as.
    @ViewState private var listName: String?
    @ViewState private var isNamingList = false
    @ViewState private var newListName = ""
    /// The selected files' tags that aren't the editor's fields, for the pickers.
    @ViewState private var otherTags: [FormatTarget] = []

    /// The preview lists at most this many changes, to stay responsive.
    private static let previewLimit = 1000

    var body: some View {
        let result = controller.library.planFormat(steps, in: ids)
        let plan = (try? result.get()) ?? FormatPlan()

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(ids.count == 1 ? "Format Tags for 1 File" : "Format Tags for \(ids.count) Files")
                    .font(.title3.bold())
                if let listName {
                    Text(listName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                savedListsMenu
            }

            HStack(alignment: .top, spacing: 16) {
                stepList
                    .frame(width: 260)
                ScrollView {
                    if let index = steps.firstIndex(where: { $0.id == selectedStepID }) {
                        StepEditor(step: $steps[index], number: index + 1, otherTags: otherTags)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(steps.isEmpty ? "Add a step with +." : "Select a step to edit it.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 290)

            if case let .failure(error) = result {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Table(Array(plan.changes.prefix(Self.previewLimit))) {
                TableColumn("File") { change in
                    Text(change.url.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(change.url.path)
                }
                .width(min: 100, ideal: 170)
                TableColumn("Tag") { change in
                    Text(change.label)
                }
                .width(min: 50, ideal: 90)
                TableColumn("Before") { change in
                    Text(change.before)
                        .foregroundStyle(.secondary)
                        .help(change.before)
                }
                TableColumn("After") { change in
                    AfterCell(change: change)
                }
            }
            .frame(minHeight: 180)

            Text(summary(plan))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text(plan.renames.contains { $0.status == .rename }
                    ? "⌘Z undoes it all. Tag changes are saved with ⌘S; files are renamed right away."
                    : "⌘Z undoes it; save with ⌘S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.fileCount == 1 ? "Apply to 1 File" : "Apply to \(plan.fileCount) Files") {
                    controller.applyFormat(plan)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.fileCount == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 860, idealWidth: 940, minHeight: 700, idealHeight: 760)
        .onAppear {
            selectedStepID = selectedStepID ?? steps.first?.id
            otherTags = FormatTarget.otherTags(among: controller.library.rawTags(for: Set(ids)).map(\.key))
        }
        .onChange(of: steps) {
            FormatStepStore.currentSteps = steps
        }
        .alert("Save Steps", isPresented: $isNamingList) {
            TextField("Name", text: $newListName)
            Button("Save") { save(as: newListName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved steps are listed in the Saved Steps menu, here and in the list's context menu. Steps saved with the same name are replaced.")
        }
    }

    // MARK: Steps

    private var stepList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedStepID) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(index + 1). \(step.kind.label)")
                        Text(step.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .tag(step.id)
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack(spacing: 2) {
                Menu {
                    ForEach(FormatStep.Kind.allCases) { kind in
                        Button(kind.label) { add(kind) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a step")
                Button("Remove Step", systemImage: "minus", action: removeSelected)
                    .disabled(selectedIndex == nil)
                    .help("Remove the selected step")
                Button("Move Up", systemImage: "chevron.up") { moveSelected(by: -1) }
                    .disabled((selectedIndex ?? 0) == 0)
                    .help("Run the selected step earlier")
                Button("Move Down", systemImage: "chevron.down") { moveSelected(by: 1) }
                    .disabled(selectedIndex.map { $0 == steps.count - 1 } ?? true)
                    .help("Run the selected step later")
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(6)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }

    private var selectedIndex: Int? {
        steps.firstIndex { $0.id == selectedStepID }
    }

    private func add(_ kind: FormatStep.Kind) {
        let step = FormatStep(kind)
        steps.insert(step, at: selectedIndex.map { $0 + 1 } ?? steps.count)
        selectedStepID = step.id
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        steps.remove(at: index)
        selectedStepID = steps.indices.contains(index) ? steps[index].id : steps.last?.id
    }

    private func moveSelected(by offset: Int) {
        guard let index = selectedIndex, steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
    }

    // MARK: Saved lists

    private var savedListsMenu: some View {
        Menu("Saved Steps") {
            if savedLists.isEmpty {
                Button("No Saved Steps") {}
                    .disabled(true)
            }
            ForEach(savedLists) { list in
                Button(list.name) { load(list) }
            }
            Divider()
            if let listName, savedLists.contains(where: { $0.name == listName }) {
                Button("Save Changes to “\(listName)”") { save(as: listName) }
            }
            Button("Save Steps As…") {
                newListName = listName ?? ""
                isNamingList = true
            }
            .disabled(steps.isEmpty)
            if !savedLists.isEmpty {
                Menu("Delete") {
                    ForEach(savedLists) { list in
                        Button(list.name) { delete(list) }
                    }
                }
            }
        }
        .fixedSize()
    }

    private func load(_ list: FormatStepList) {
        steps = list.steps
        listName = list.name
        selectedStepID = steps.first?.id
    }

    private func save(as name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        savedLists.removeAll { $0.name == name }
        savedLists.append(FormatStepList(name: name, steps: steps))
        savedLists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        FormatStepStore.savedLists = savedLists
        listName = name
    }

    private func delete(_ list: FormatStepList) {
        savedLists.removeAll { $0.name == list.name }
        FormatStepStore.savedLists = savedLists
        if listName == list.name {
            listName = nil
        }
    }

    private func summary(_ plan: FormatPlan) -> String {
        guard !plan.changes.isEmpty else { return steps.isEmpty ? "" : "Nothing to change." }
        let count = plan.changes.count
        var text = "\(count == 1 ? "1 change" : "\(count) changes") in \(plan.fileCount == 1 ? "1 file" : "\(plan.fileCount) files")."
        let renamed = plan.renames.filter { $0.status == .rename }.count
        if renamed > 0 {
            text += renamed == 1 ? " 1 file is renamed." : " \(renamed) files are renamed."
        }
        let skipped = plan.changes.filter { $0.problem != nil }.count
        if skipped > 0 {
            text += skipped == 1 ? " 1 file can't be renamed." : " \(skipped) files can't be renamed."
        }
        if count > Self.previewLimit {
            text += " The first \(Self.previewLimit) changes are shown."
        }
        return text
    }
}

private struct AfterCell: View {
    let change: FormatChange

    var body: some View {
        if let problem = change.problem {
            HStack(spacing: 4) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(change.after.isEmpty ? problem : change.after)
                    .strikethrough(!change.after.isEmpty)
            }
            .help("Not renamed: \(problem)")
        } else if change.after.isEmpty {
            Text("Removed")
                .italic()
                .foregroundStyle(.secondary)
        } else {
            Text(change.after)
                .help(change.after)
        }
    }
}

/// The settings of one step.
private struct StepEditor: View {
    @Binding var step: FormatStep
    let number: Int
    let otherTags: [FormatTarget]

    private static let textFields = FormatTarget.textFields.map(FormatTarget.field) + [.field(.date)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Step \(number):", selection: $step.kind) {
                ForEach(FormatStep.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .fixedSize()

            switch step.kind {
            case .changeCase:
                textTarget
                Picker("Case", selection: $step.caseStyle) {
                    ForEach(CaseStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if step.caseStyle.usesKeptWords {
                    HStack(spacing: 6) {
                        Text("Always write as:")
                        TextField("Always write as", text: $step.keptWords)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    }
                    caption("Words separated by commas, written exactly like this whatever their case. Title Case keeps small words (a, the, of, in…) lowercase, except first and last, and keeps capitals inside words (BBC, McCartney) unless the text is all in capitals.")
                }
            case .replace:
                textTarget
                replaceOptions
            case .cleanUpSpaces:
                textTarget
                caption("Removes spaces at the start and end, and turns repeated spaces into one.")
            case .setTag:
                TargetPicker(title: "Set:", target: $step.destination,
                             groups: [LogicalField.allCases.map(FormatTarget.field), otherTags, [.fileName]])
                PatternEditor(text: $step.pattern, tokens: PatternToken.tagValue, prompt: "%artist%")
                Toggle("Only where it's empty", isOn: $step.onlyIfEmpty)
                caption("Placeholders insert the file's tags, %filename% its name, and any tag's name its value (e.g. %MOOD%). Files where the pattern comes out empty are left alone.")
            case .splitTag:
                TargetPicker(title: "Split:", target: $step.source, groups: [Self.textFields, otherTags, [.fileName]])
                PatternEditor(text: $step.splitPattern, tokens: PatternToken.splitTag, prompt: "%artist% - %title%")
                caption("Reads tags from the text, like Tags from File Names: “Band - Song” with %artist% - %title% sets Artist and Title. %skip% skips text. Values that don't match are left alone.")
            case .removeTags:
                Picker("Remove", selection: $step.keepsListedTags) {
                    Text("Remove these tags").tag(false)
                    Text("Remove all tags except these").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                HStack(spacing: 6) {
                    TextField("Tag names", text: $step.tagNames, prompt: Text("Comment, ENCODER"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Menu("Add") {
                        ForEach(LogicalField.allCases) { field in
                            Button(field.label) { addName(field.label) }
                        }
                        if !otherTags.isEmpty {
                            Divider()
                            ForEach(otherTags, id: \.self) { tag in
                                Button(tag.label) { addName(tag.label) }
                            }
                        }
                    }
                    .fixedSize()
                }
                caption("Names separated by commas: fields such as Comment or Album Artist, or tags such as ENCODER (see All Tags). Covers stay; remove them in the tag editor.")
            }
        }
    }

    private var textTarget: some View {
        TargetPicker(title: "Apply to:", target: $step.target, groups: [[.textTags], Self.textFields, otherTags, [.fileName]])
    }

    private var replaceOptions: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Find:")
                    .gridColumnAlignment(.trailing)
                TextField("Find", text: $step.find)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            GridRow {
                Text("Replace with:")
                TextField("Replace with", text: $step.replacement, prompt: Text("Nothing (removes the text)"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                HStack(spacing: 16) {
                    Toggle("Match case", isOn: $step.matchCase)
                    Toggle("Regular expression", isOn: $step.regularExpression)
                        .help("Find is a regular expression; in Replace with, $1, $2… insert its groups.")
                }
            }
        }
    }

    private func addName(_ name: String) {
        let names = step.tagNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        step.tagNames = (names.filter { !$0.isEmpty } + [name]).joined(separator: ", ")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Chooses a step's target: the listed fields and tags (groups separated by
/// dividers), or any other tag by name.
private struct TargetPicker: View {
    let title: String
    @Binding var target: FormatTarget
    let groups: [[FormatTarget]]

    private enum Choice: Hashable {
        case target(FormatTarget)
        case otherTag
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker(title, selection: choice) {
                ForEach(Array(groups.enumerated().filter { !$0.element.isEmpty }), id: \.offset) { index, group in
                    if index > 0 {
                        Divider()
                    }
                    ForEach(group, id: \.self) { target in
                        Text(target.label).tag(Choice.target(target))
                    }
                }
                Divider()
                Text("Other Tag…").tag(Choice.otherTag)
            }
            .fixedSize()
            if isOtherTag {
                TextField("Tag name", text: tagName, prompt: Text("Tag name, e.g. MOOD"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 200)
            }
        }
    }

    private var isOtherTag: Bool {
        if case .tag = target {
            return !groups.joined().contains(target)
        }
        return false
    }

    private var choice: Binding<Choice> {
        Binding(
            get: { isOtherTag ? .otherTag : .target(target) },
            set: { choice in
                switch choice {
                case let .target(newTarget): target = newTarget
                case .otherTag: target = .tag("")
                }
            }
        )
    }

    private var tagName: Binding<String> {
        Binding(
            get: { if case let .tag(key) = target { key } else { "" } },
            set: { target = .tag($0.uppercased()) }
        )
    }
}

/// The steps last used, and the saved lists, kept in the user defaults.
enum FormatStepStore {
    private static let stepsKey = "formatSteps"
    private static let listsKey = "formatStepLists"

    static var currentSteps: [FormatStep] {
        get { decode([FormatStep].self, stepsKey) ?? [FormatStep(.changeCase)] }
        set { encode(newValue, stepsKey) }
    }

    static var savedLists: [FormatStepList] {
        get { decode([FormatStepList].self, listsKey) ?? [] }
        set { encode(newValue, listsKey) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func encode(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
