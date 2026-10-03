import CryptoKit
import SwiftUI
import TaggartCore
import UniformTypeIdentifiers

/// Shows the selection's cover and lets the user replace, remove or export it.
/// Accepts dropped image files or image data, and ⌘V.
struct ArtworkWell: View {
    let ids: Set<URL>
    @Environment(AppController.self) private var controller
    @ViewState private var isTargeted = false
    /// A sharper image than the cached thumbnail, loaded on demand.
    @ViewState private var preview: (digest: SHA256.Digest, image: CGImage)?

    var body: some View {
        let state = controller.library.artworkState(for: ids)
        let source = controller.library.primaryArtwork(in: ids)
        let shownDigest: SHA256.Digest? = if case let .uniform(artwork) = state { artwork.digest } else { nil }
        VStack(spacing: 10) {
            preview(state)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted, perform: drop)
                .focusable()
                .focusEffectDisabled()
                .onPasteCommand(of: [.fileURL, .image]) { _ in controller.pasteArtwork(for: ids) }
                .contextMenu { menuItems(state) }

            Text(caption(state))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Choose…") { controller.chooseArtwork(for: ids) }
                Button("Paste") { controller.pasteArtwork(for: ids) }
                Button("Remove") { controller.apply(.removeArtwork, to: ids) }
                    .disabled(state == .none)
                if shownDigest != nil, let source {
                    Button("Export…") { controller.exportArtwork(source.artwork, from: source.url) }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .task(id: shownDigest) {
            guard let shownDigest, let source, preview?.digest != shownDigest else { return }
            if let image = await Self.makePreview(of: source.artwork, in: source.url) {
                preview = (shownDigest, image)
            }
        }
    }

    @concurrent
    private nonisolated static func makePreview(of artwork: Artwork, in url: URL) async -> CGImage? {
        guard let data = try? TagIO.data(of: artwork, in: url) else { return nil }
        return ArtworkImage.thumbnail(of: data, maxPixelSize: 640)
    }

    @ViewBuilder
    private func preview(_ state: ArtworkState) -> some View {
        switch state {
        case let .uniform(artwork):
            let sharp = preview?.digest == artwork.digest ? preview?.image : nil
            if let image = sharp ?? controller.library.thumbnails[artwork.digest] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            } else {
                placeholder("Artwork", systemImage: "photo")
            }
        case .mixed:
            placeholder("Different Artwork", systemImage: "square.stack")
        case .none:
            placeholder("No Artwork", systemImage: "photo.badge.plus")
        }
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 32))
            Text(title)
            Text("Drop an image here").font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func menuItems(_ state: ArtworkState) -> some View {
        Button("Choose Image…") { controller.chooseArtwork(for: ids) }
        Button("Paste Image") { controller.pasteArtwork(for: ids) }
        Button("Remove Artwork") { controller.apply(.removeArtwork, to: ids) }
            .disabled(state == .none)
    }

    private func caption(_ state: ArtworkState) -> String {
        switch state {
        case let .uniform(artwork):
            let type = UTType(mimeType: artwork.mimeType)?.preferredFilenameExtension?.uppercased() ?? artwork.mimeType
            let size = ByteCountFormatStyle(style: .file).format(Int64(artwork.byteCount))
            let dimensions = artwork.width > 0 ? "\(artwork.width) × \(artwork.height) · " : ""
            return "\(dimensions)\(type) · \(size)"
        case .mixed:
            return "The selected files have different artwork."
        case .none:
            return ids.count > 1 ? "None of the selected files have artwork." : "This file has no artwork."
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let targets = ids
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    controller.setArtwork(for: targets) { try ArtworkImage.artwork(contentsOf: url) }
                }
            }
            return true
        }
        guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }) else { return false }
        _ = provider.loadDataRepresentation(for: type) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                controller.setArtwork(for: targets) { try ArtworkImage.artwork(from: data) }
            }
        }
        return true
    }
}
