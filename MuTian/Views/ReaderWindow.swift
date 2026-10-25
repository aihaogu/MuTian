import AppKit
import SwiftUI

struct ReaderWindow: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let bookID: UUID?

    var body: some View {
        Group {
            if let bookID, let book = libraryStore.books.first(where: { $0.id == bookID }) {
                ReaderView(book: book, presentation: .window)
                    .id("\(book.id)|\(book.localPath)")
                    .navigationTitle(book.title)
            } else {
                DetailPlaceholder(
                    title: "无法打开阅读窗口",
                    systemImage: "book.closed",
                    message: "这部古籍可能已从资料库移除。"
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(MuTianTheme.paper)
    }
}

struct OpenReaderWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let book: Book
    var title = "阅读"

    var body: some View {
        Button {
            openWindow(value: book.id)
        } label: {
            Label(title, systemImage: "book")
        }
        .help("在新窗口中阅读")
    }
}
