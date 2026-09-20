import AppKit
import SwiftUI

struct FullScreenReaderWindow: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let bookID: UUID?

    var body: some View {
        Group {
            if let bookID, let book = libraryStore.books.first(where: { $0.id == bookID }) {
                ReaderView(book: book, presentation: .fullScreenWindow)
                    .id("\(book.id)|\(book.localPath)")
                    .background {
                        FullScreenWindowConfigurator(title: "阅读 - \(book.title)")
                    }
            } else {
                DetailPlaceholder(
                    title: "无法打开全屏阅读",
                    systemImage: "book.closed",
                    message: "这部古籍可能已从资料库移除。"
                )
            }
        }
        .frame(minWidth: 900, minHeight: 680)
        .background(MuTianTheme.paper)
    }
}

private struct FullScreenWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view, context: context)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view, context: context)
        }
    }

    private func configure(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        window.title = title
        window.minSize = NSSize(width: 900, height: 680)

        guard !context.coordinator.didRequestFullScreen else { return }
        context.coordinator.didRequestFullScreen = true
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    final class Coordinator {
        var didRequestFullScreen = false
    }
}
