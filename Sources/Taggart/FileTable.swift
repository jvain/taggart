import SwiftUI
import TaggartCore

struct FileTable: View {
    let items: [AudioFileItem]
    @Binding var selection: Set<AudioFileItem.ID>
    @Environment(AppController.self) private var controller
    @ViewState private var sortOrder: [KeyPathComparator<AudioFileItem>] = []
    @SceneStorage("FileTableColumns") private var columns = TableColumnCustomization<AudioFileItem>()

    var body: some View {
        Table(sortedItems, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
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

            TableColumn("Title", value: \AudioFileItem.title)
                .width(min: 80, ideal: 140)
                .customizationID("title")
            TableColumn("Artist", value: \AudioFileItem.artist)
                .width(min: 60, ideal: 110)
                .customizationID("artist")
            TableColumn("Album", value: \AudioFileItem.album)
                .width(min: 60, ideal: 110)
                .customizationID("album")

            Group {
                TableColumn("Album Artist", value: \AudioFileItem.albumArtist) { Text($0.albumArtist) }
                    .width(min: 80, ideal: 130)
                    .customizationID("albumArtist")
                    .defaultVisibility(.hidden)
                TableColumn("#", value: \AudioFileItem.trackSortKey) { item in
                    Text(item.value(.trackNumber)).monospacedDigit()
                }
                .width(min: 28, ideal: 34)
                .customizationID("track")
                TableColumn("Disc", value: \AudioFileItem.discSortKey) { item in
                    Text(item.value(.discNumber)).monospacedDigit()
                }
                .width(min: 28, ideal: 34)
                .customizationID("disc")
                .defaultVisibility(.hidden)
                TableColumn("Year", value: \AudioFileItem.year) { Text($0.year) }
                    .width(min: 36, ideal: 44)
                    .customizationID("year")
                TableColumn("Genre", value: \AudioFileItem.genre) { Text($0.genre) }
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
                Button("Revert") {
                    controller.selection = ids
                    controller.revertSelected()
                }
                Divider()
                Button("Remove from List") {
                    controller.selection = ids
                    controller.removeSelected()
                }
            }
        }
        .onDeleteCommand { controller.removeSelected() }
    }

    private var sortedItems: [AudioFileItem] {
        sortOrder.isEmpty ? items : items.sorted(using: sortOrder)
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
