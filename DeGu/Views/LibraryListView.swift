import AppKit
import SwiftUI

private enum LibraryBrowseMode: String {
    case covers
    case list
}

private struct LibraryBookSection: Identifiable {
    let id: String
    let title: String
    let books: [Book]
}

struct LibraryListView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("libraryBrowseMode") private var browseModeRaw = LibraryBrowseMode.covers.rawValue
    @State private var visibleBookLimit = 48

    private var pageSize: Int {
        browseMode == .covers ? 48 : 120
    }

    var body: some View {
        let books = libraryStore.filteredBooks
        let visibleBooks = Array(books.prefix(visibleBookLimit))

        VStack(spacing: 0) {
            header(total: books.count)

            if books.isEmpty {
                DetailPlaceholder(
                    title: "没有可浏览的古籍",
                    systemImage: "books.vertical",
                    message: "导入文件夹后，可以在这里按分类浏览封面或列表。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(groupedBooks(visibleBooks)) { section in
                            bookSection(section)
                        }

                        if visibleBookLimit < books.count {
                            LoadMoreBooksView(shown: visibleBooks.count, total: books.count) {
                                loadMore(total: books.count)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(DeGuTheme.detailBackground)
        .navigationTitle("浏览")
        .onChange(of: libraryStore.searchText) { _, _ in
            resetPagination()
        }
        .onChange(of: libraryStore.sidebarSelection) { _, _ in
            resetPagination()
        }
        .onChange(of: browseModeRaw) { _, _ in
            resetPagination()
        }
        .onChange(of: books.count) { _, _ in
            if visibleBookLimit > books.count {
                visibleBookLimit = max(pageSize, books.count)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var browseMode: LibraryBrowseMode {
        LibraryBrowseMode(rawValue: browseModeRaw) ?? .covers
    }

    private func header(total: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("浏览")
                    .font(.headline)
                Text("\(total) 部古籍")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !libraryStore.searchText.isEmpty {
                MetaPill(text: "搜索中", systemImage: "magnifyingglass", color: DeGuTheme.indigo)
            }
            Picker("显示方式", selection: $browseModeRaw) {
                Label("封面", systemImage: "square.grid.2x2").tag(LibraryBrowseMode.covers.rawValue)
                Label("列表", systemImage: "list.bullet").tag(LibraryBrowseMode.list.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 168)
            if libraryStore.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func bookSection(_ section: LibraryBookSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.headline)
                Text("\(section.books.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            switch browseMode {
            case .covers:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132, maximum: 176), spacing: 18)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(section.books) { book in
                        BookCoverButton(book: book)
                    }
                }
            case .list:
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(section.books) { book in
                        BookListButton(book: book)
                    }
                }
            }
        }
    }

    private func groupedBooks(_ books: [Book]) -> [LibraryBookSection] {
        var grouped: [String: [Book]] = [:]
        var order: [String] = []

        for book in books {
            let title = libraryStore.classificationName(for: book.classificationID)
            if grouped[title] == nil {
                grouped[title] = []
                order.append(title)
            }
            grouped[title]?.append(book)
        }

        return order.map { title in
            LibraryBookSection(id: title, title: title, books: grouped[title] ?? [])
        }
    }

    private func resetPagination() {
        visibleBookLimit = pageSize
    }

    private func loadMore(total: Int) {
        guard visibleBookLimit < total else { return }
        visibleBookLimit = min(visibleBookLimit + pageSize, total)
    }
}

private struct BookCoverButton: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        Button {
            libraryStore.selectBook(book)
        } label: {
            BookCoverView(book: book, isSelected: libraryStore.selectedBookID == book.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            bookActions
        }
    }

    @ViewBuilder
    private var bookActions: some View {
        Button(book.isFavorite ? "取消收藏" : "收藏") {
            libraryStore.toggleFavorite(book)
        }
        Button("在 Finder 中显示") {
            libraryStore.revealInFinder(book)
        }
    }
}

private struct BookListButton: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        Button {
            libraryStore.selectBook(book)
        } label: {
            BookRowView(book: book)
                .padding(.horizontal, 10)
                .background(isSelected ? DeGuTheme.accent.opacity(0.10) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            bookActions
        }
    }

    private var isSelected: Bool {
        libraryStore.selectedBookID == book.id
    }

    @ViewBuilder
    private var bookActions: some View {
        Button(book.isFavorite ? "取消收藏" : "收藏") {
            libraryStore.toggleFavorite(book)
        }
        Button("在 Finder 中显示") {
            libraryStore.revealInFinder(book)
        }
    }
}

private struct BookCoverView: View {
    let book: Book
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                BookCoverThumbnailView(book: book)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isSelected ? DeGuTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    }

                if book.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(7)
                }
            }

            Text(book.title)
                .font(.system(.callout, design: .serif))
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Image(systemName: fileTypeIcon)
                    .font(.caption2)
                Text(subtitle)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(isSelected ? DeGuTheme.accent.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        if !book.author.isEmpty {
            return book.author
        }
        if book.pageCount > 0 {
            return "\(book.pageCount) 页"
        }
        return book.fileType.rawValue
    }

    private var fileTypeIcon: String {
        switch book.fileType {
        case .pdf: "doc.richtext"
        case .imageSequence: "photo.on.rectangle"
        case .text: "text.page"
        case .ebook: "book"
        case .document: "doc"
        case .archive: "archivebox"
        case .mixedFolder: "folder"
        }
    }
}

private struct LoadMoreBooksView: View {
    let shown: Int
    let total: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("已显示 \(shown) / \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear(perform: action)
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
        case .ebook: "book"
        case .document: "doc"
        case .archive: "archivebox"
        case .mixedFolder: "folder"
        }
    }

    private var iconColor: Color {
        switch book.fileType {
        case .pdf: return DeGuTheme.cinnabar
        case .imageSequence: return DeGuTheme.jade
        case .text: return DeGuTheme.indigo
        case .ebook: return DeGuTheme.accent
        case .document: return .secondary
        case .archive: return DeGuTheme.cinnabar
        case .mixedFolder: return DeGuTheme.accent
        }
    }

    private var authorText: String {
        book.author.isEmpty ? "作者未录" : book.author
    }
}
