import SwiftUI

struct LibraryListView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("书目")
                        .font(.headline)
                    Text("\(libraryStore.filteredBooks.count) 部古籍")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !libraryStore.searchText.isEmpty {
                    MetaPill(text: "搜索中", systemImage: "magnifyingglass", color: DeGuTheme.indigo)
                }
                Text("索引导入，不复制原文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if libraryStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List(selection: $libraryStore.selectedBookID) {
                ForEach(libraryStore.filteredBooks) { book in
                    BookRowView(book: book)
                        .tag(book.id)
                        .contextMenu {
                            Button(book.isFavorite ? "取消收藏" : "收藏") {
                                libraryStore.toggleFavorite(book)
                            }
                            Button("在 Finder 中显示") {
                                libraryStore.revealInFinder(book)
                            }
                        }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(DeGuTheme.detailBackground)
        .navigationTitle("书目")
    }
}

struct BookRowView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(book.title)
                        .font(.system(.headline, design: .serif))
                        .lineLimit(1)
                    if book.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                    Spacer()
                    StatusBadge(text: book.status.rawValue, color: DeGuTheme.statusColor(book.status))
                }
                HStack(spacing: 6) {
                    MetaPill(text: authorText, systemImage: "person", color: .secondary)
                    MetaPill(text: libraryStore.classificationName(for: book.classificationID), systemImage: "square.grid.2x2", color: DeGuTheme.accent)
                    MetaPill(text: "\(book.pageCount) 页", systemImage: "doc", color: .secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        switch book.fileType {
        case .pdf: "doc.richtext"
        case .imageSequence: "photo.on.rectangle"
        case .text: "text.page"
        case .mixedFolder: "folder"
        }
    }

    private var iconColor: Color {
        switch book.fileType {
        case .pdf: return DeGuTheme.cinnabar
        case .imageSequence: return DeGuTheme.jade
        case .text: return DeGuTheme.indigo
        case .mixedFolder: return DeGuTheme.accent
        }
    }

    private var authorText: String {
        book.author.isEmpty ? "作者未录" : book.author
    }
}
