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
        .shadow(color: .black.opacity(showsShadow ? 0.12 : 0), radius: showsShadow ? 8 : 0, y: showsShadow ? 3 : 0)
        .task(id: thumbnailRequest.key) {
            await loadCover(for: thumbnailRequest)
        }
    }

    private var thumbnailRequest: BookCoverThumbnailRequest {
        BookCoverThumbnailRequest(book: book)
    }

    private var fallbackCover: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [coverTint.opacity(0.92), coverTint.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(titleInitial)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                Spacer()
                Text(book.fileType.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(12)
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

    private var coverTint: Color {
        switch book.fileType {
        case .pdf: return MuTianTheme.cinnabar
        case .imageSequence: return MuTianTheme.jade
        case .text: return MuTianTheme.indigo
        case .ebook: return MuTianTheme.accent
        case .document: return .secondary
        case .archive: return MuTianTheme.cinnabar
        case .mixedFolder: return MuTianTheme.accent
        }
    }
}
