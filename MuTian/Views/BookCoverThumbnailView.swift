import AppKit
import SwiftUI

struct BookCoverThumbnailView: View {
    let book: Book
    var cornerRadius: CGFloat = 7
    var showsShadow: Bool = true

    @State private var loaded: BookCoverImageStore.Entry?
    @State private var loadedKey: String?
    @State private var hasNoCover = false

    var body: some View {
        let key = BookCoverThumbnailRequest.displayKey(for: book)

        Color.clear
            .aspectRatio(0.68, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image = coverImage(for: key) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    fallbackCover
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(showsShadow ? 0.10 : 0), radius: showsShadow ? 4 : 0, y: showsShadow ? 2 : 0)
            .task(id: key) {
                await loadCover(displayKey: key)
            }
    }

    private func coverImage(for key: String) -> NSImage? {
        if loadedKey == key {
            return hasNoCover ? nil : loaded?.image
        }
        return BookCoverImageStore.entry(for: key)?.image
    }

    private var fallbackCover: some View {
        ZStack(alignment: .trailing) {
            MuTianTheme.paper
            MuTianTheme.accent.opacity(0.10)

            Rectangle()
                .fill(MuTianTheme.accent.opacity(0.45))
                .frame(width: 3)

            VStack(spacing: 8) {
                Text(titleInitial)
                    .font(.system(size: 30, weight: .medium, design: .serif))
                    .foregroundStyle(MuTianTheme.accent)
                Spacer()
                Text(book.fileType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
        }
    }

    @MainActor
    private func loadCover(displayKey: String) async {
        let book = self.book
        let request = await Task.detached(priority: .utility) {
            BookCoverThumbnailRequest(book: book)
        }.value
        guard !Task.isCancelled else { return }

        if let cached = BookCoverImageStore.entry(for: displayKey), cached.sourceKey == request.key {
            show(cached, key: displayKey)
            return
        }

        guard let data = await BookCoverThumbnailCache.shared.thumbnailData(for: request),
              !Task.isCancelled,
              let image = NSImage(data: data) else {
            guard !Task.isCancelled else { return }
            BookCoverImageStore.remove(displayKey)
            loaded = nil
            loadedKey = displayKey
            hasNoCover = true
            return
        }

        let entry = BookCoverImageStore.Entry(image: image, sourceKey: request.key)
        BookCoverImageStore.store(entry, for: displayKey)
        show(entry, key: displayKey)
    }

    private func show(_ entry: BookCoverImageStore.Entry, key: String) {
        loaded = entry
        loadedKey = key
        hasNoCover = false
    }

    private var titleInitial: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "书" : String(trimmed.prefix(1))
    }
}
