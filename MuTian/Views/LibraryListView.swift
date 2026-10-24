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
        let sections = groupedBooks(visibleBooks)

        Group {
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(sections) { section in
                            bookSection(section, showsTitle: sections.count > 1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
        .navigationTitle(selectionTitle)
        .navigationSubtitle("\(books.count) 部")
        .toolbar {
            ToolbarItemGroup {
                filterMenu
                Picker("显示方式", selection: $browseModeRaw) {
                    Label("封面", systemImage: "square.grid.2x2").tag(LibraryBrowseMode.covers.rawValue)
                    Label("列表", systemImage: "list.bullet").tag(LibraryBrowseMode.list.rawValue)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("切换封面或列表")
            }
        }
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

    @ViewBuilder
    private var emptyState: some View {
        if !libraryStore.searchText.isEmpty {
            DetailPlaceholder(title: "没有匹配的古籍", systemImage: "magnifyingglass", message: "换个关键词，或清除搜索后再看。")
        } else if libraryStore.books.isEmpty {
            DetailPlaceholder(title: "资料库还是空的", systemImage: "books.vertical", message: "点击工具栏的“导入”，选择本地古籍文件夹或 PDF。")
        } else {
            DetailPlaceholder(title: "这里暂无古籍", systemImage: "tray", message: "当前分类或筛选下没有书目。")
        }
    }

    private var selectionTitle: String {
        switch libraryStore.sidebarSelection {
        case .all, .downloads, .statistics: return "浏览"
        case .favorites: return "收藏"
        case .status(let status): return status.rawValue
        case .classification(let id): return libraryStore.classificationName(for: id)
        case .source(let source): return source
        }
    }

    private var filterMenu: some View {
        Menu {
            Button("全部古籍") { libraryStore.sidebarSelection = .all }
            Section("整理状态") {
                ForEach(BookStatus.allCases) { status in
                    filterButton(status.rawValue, selection: .status(status))
                }
            }
            if !libraryStore.sources.isEmpty {
                Section("来源") {
                    ForEach(libraryStore.sources, id: \.self) { source in
                        filterButton(source, selection: .source(source))
                    }
                }
            }
        } label: {
            Label(activeFilterName ?? "筛选", systemImage: activeFilterName == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .help("按整理状态或来源筛选")
    }

    private func filterButton(_ title: String, selection: SidebarSelection) -> some View {
        Button {
            libraryStore.sidebarSelection = selection
        } label: {
            if libraryStore.sidebarSelection == selection {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var activeFilterName: String? {
        switch libraryStore.sidebarSelection {
        case .status(let status): return status.rawValue
        case .source(let source): return source
        default: return nil
        }
    }

    @ViewBuilder
    private func bookSection(_ section: LibraryBookSection, showsTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(section.title)
                        .font(.system(.headline, design: .serif))
                    Text("\(section.books.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            switch browseMode {
            case .covers:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 124, maximum: 168), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(section.books) { book in
                        BookCoverButton(book: book)
                    }
                }
            case .list:
                LazyVStack(alignment: .leading, spacing: 0) {
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

private struct BookActions: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        Button(book.isFavorite ? "取消收藏" : "收藏") {
            libraryStore.toggleFavorite(book)
        }
        Button("在 Finder 中显示") {
            libraryStore.revealInFinder(book)
        }
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
        .contextMenu { BookActions(book: book) }
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
                .background(isSelected ? MuTianTheme.accent.opacity(0.10) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu { BookActions(book: book) }
    }

    private var isSelected: Bool {
        libraryStore.selectedBookID == book.id
    }
}

private struct BookCoverView: View {
    let book: Book
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverThumbnailView(book: book)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? MuTianTheme.accent : MuTianTheme.hairline, lineWidth: isSelected ? 2 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if book.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(MuTianTheme.cinnabar, in: Circle())
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(.callout, design: .serif))
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? MuTianTheme.accent : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(4)
        .contentShape(Rectangle())
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
    let book: Book

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: MuTianTheme.fileTypeIcon(book.fileType))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(book.title)
                .font(.system(.body, design: .serif))
                .lineLimit(1)

            if book.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(MuTianTheme.cinnabar)
            }

            Spacer(minLength: 12)

            if book.status != .pending {
                StatusBadge(text: book.status.rawValue, color: MuTianTheme.statusColor(book.status))
            }

            Text(book.author.isEmpty ? "—" : book.author)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            Text(book.pageCount > 0 ? "\(book.pageCount) 页" : "")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
