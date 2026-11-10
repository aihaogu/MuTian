import AppKit
import SwiftUI

struct BookCoverThumbnailView: View {
    let book: Book
    var cornerRadius: CGFloat = 3
    var showsShadow: Bool = true
    /// 悬停或选中时书略微抬起，投影加深。
    var isRaised: Bool = false

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
            .overlay(alignment: .leading) {
                // 书口一侧的微弱高光，让封面有纸张的厚度。
                LinearGradient(
                    colors: [.white.opacity(0.22), .white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 7)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(showsShadow ? 0.16 : 0), radius: 0.5, y: 0.5)
            .shadow(
                color: .black.opacity(showsShadow ? (isRaised ? 0.22 : 0.13) : 0),
                radius: showsShadow ? (isRaised ? 11 : 6) : 0,
                y: showsShadow ? (isRaised ? 7 : 4) : 0
            )
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

    /// 没有封面图时画一册线装书：布面书衣、右侧四眼装订、左上题签。
    private var fallbackCover: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let threadX = width * 0.885
            let slipWidth = max(width * 0.25, 20)
            let slipHeight = height * 0.62
            let fontSize = slipWidth * 0.54
            let lineHeight = fontSize * 1.14
            let capacity = max(Int((slipHeight - slipWidth * 0.5) / lineHeight), 1)
            let characters = Array(slipCharacters.prefix(capacity))

            ZStack(alignment: .topLeading) {
                MuTianTheme.clothColor(forClassificationID: book.classificationID)
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: threadX, y: 0))
                    path.addLine(to: CGPoint(x: threadX, y: height))
                    for fraction in [0.07, 0.355, 0.645, 0.93] {
                        path.move(to: CGPoint(x: threadX, y: height * fraction))
                        path.addLine(to: CGPoint(x: width, y: height * fraction))
                    }
                }
                .stroke(MuTianTheme.sealPaper.opacity(0.62), lineWidth: 0.8)

                VStack(spacing: lineHeight - fontSize) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(MuTianTheme.brush(fontSize))
                            .frame(height: fontSize)
                    }
                }
                .foregroundStyle(Color(hex: 0x2A2522))
                .padding(.top, slipWidth * 0.26)
                .frame(width: slipWidth, height: slipHeight, alignment: .top)
                .background(MuTianTheme.sealPaper)
                .overlay {
                    Rectangle()
                        .strokeBorder(Color(hex: 0x2A2522).opacity(0.42), lineWidth: 0.5)
                        .padding(2)
                }
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                .offset(x: width * 0.09, y: height * 0.065)
            }
        }
        .accessibilityHidden(true)
    }

    /// 题签只取书名里的文字，去掉括号、下划线等符号。
    private var slipCharacters: [Character] {
        let kept = book.title.filter { character in
            character.isLetter || character.isNumber
        }
        return kept.isEmpty ? Array("无题") : Array(kept)
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
}
