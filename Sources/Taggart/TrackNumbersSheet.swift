import SwiftUI
import TaggartCore

/// Numbers the selected files' tracks 1, 2, 3… in list order, with a
/// before/after preview.
struct TrackNumbersSheet: View {
    /// In list order.
    let ids: [AudioFileItem.ID]
    @Environment(AppController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    // Remembered between uses.
    @AppStorage("trackNumberingStart") private var start = 1
    @AppStorage("trackNumberingRestartsInEachFolder") private var restartsInEachFolder = true
    @AppStorage("trackNumberingSetsTotal") private var setsTotal = false
    @AppStorage("trackNumberingPadsWithZeros") private var padsWithZeros = false

    private static let startRange = 0...9999
    /// The preview lists at most this many files, to stay responsive.
    private static let previewLimit = 1000

    private var numbering: TrackNumbering {
        TrackNumbering(start: start.clamped(to: Self.startRange), restartsInEachFolder: restartsInEachFolder,
                       setsTotal: setsTotal, padsWithZeros: padsWithZeros)
    }

    var body: some View {
        let plan = controller.library.planTrackNumbers(ids, numbering: numbering)
        let changes = plan.filter(\.isChange).count

        VStack(alignment: .leading, spacing: 14) {
            Text(ids.count == 1 ? "Number 1 Track" : "Number \(ids.count) Tracks")
                .font(.title3.bold())
            Text("Files are numbered in the order of the list. To number them by file name, sort the list by File first.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Start at:")
                    TextField("Start at", value: $start, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("Start at", value: $start, in: Self.startRange)
                        .labelsHidden()
                }
                .onChange(of: start) {
                    start = start.clamped(to: Self.startRange)
                }
                Toggle("Start over in each folder", isOn: $restartsInEachFolder)
                    .help("Number each folder's files on their own, as separate albums.")
                Toggle("Set Track Total to the last number", isOn: $setsTotal)
                    .help("Without this, the files' track totals stay as they are.")
                Toggle("Leading zeros (01, 02, …)", isOn: $padsWithZeros)
            }

            Table(Array(plan.prefix(Self.previewLimit))) {
                TableColumn("File") { change in
                    Text(change.url.lastPathComponent)
                        .help(change.url.path)
                }
                .width(min: 120, ideal: 220)
                TableColumn("Folder") { change in
                    Text(change.url.deletingLastPathComponent().lastPathComponent)
                        .foregroundStyle(.secondary)
                        .help(change.url.deletingLastPathComponent().path)
                }
                .width(min: 80, ideal: 140)
                TableColumn("Before") { change in
                    Text(change.before)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 80)
                TableColumn("After") { change in
                    Text(change.after)
                        .foregroundStyle(change.isChange ? .primary : .secondary)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 80)
            }
            .frame(minHeight: 220)

            Text(summary(changes: changes))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Text("⌘Z undoes it; save with ⌘S.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(changes == 1 ? "Number 1 File" : "Number \(changes) Files") {
                    controller.applyTrackNumbers(ids, numbering: numbering)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(changes == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 600, idealWidth: 640, minHeight: 500, idealHeight: 560)
    }

    private func summary(changes: Int) -> String {
        guard changes > 0 else { return "Nothing to change: the files already have these numbers." }
        var text = changes == 1 ? "1 file will change." : "\(changes) files will change."
        if ids.count > Self.previewLimit {
            text += " The first \(Self.previewLimit) files are shown."
        }
        return text
    }
}
