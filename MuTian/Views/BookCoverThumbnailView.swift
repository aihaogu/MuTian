import AppKit
import SwiftUI

struct BookCoverThumbnailView: View {
    let book: Book
    var cornerRadius: CGFloat = 7
    var showsShadow: Bool = true

    @State private var coverImage: NSImage?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = max(width / 0.68, 1)

            ZStack {
                if let coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    fallbackCover
                        .frame(width: width, height: height)
                        .clipped()
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .aspectRatio(0.68, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .shadow(color: .black.opacity(showsShadow ? 0.10 : 0), radius: showsShadow ? 4 : 0, y: showsShadow ? 2 : 0)
        .task(id: thumbnailRequest.key) {
            await loadCover(for: thumbnailRequest)
        }
    }

    private var thumbnailRequest: BookCoverThumbnailRequest {
        BookCoverThumbnailRequest(book: book)
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
    private func loadCover(for request: BookCoverThumbnailRequest) async {
        coverImage = nil
        guard let data = await BookCoverThumbnailCache.shared.thumbnailData(for: request),
              !Task.isCancelled else {
            return
        }
        coverImage = NSImage(data: data)
    }

    private var titleInitial: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "书" : String(trimmed.prefix(1))
    }
}
