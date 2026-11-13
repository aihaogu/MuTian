import AppKit
import SwiftUI

private enum LibraryBrowseMode: String {
    case covers
    case list
}

private struct LibraryBookSection: Identifiable {
    /// 分类 ID
    let id: String
    let books: [Book]
}

struct BatchEditTarget: Identifiable {
    let id = UUID()
    let bookIDs: Set<UUID>
}

struct LibraryListView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("libraryBrowseMode") private var browseModeRaw = LibraryBrowseMode.covers.rawValue
    @State private var visibleBookLimit = 48
    @State private var review: ProposalReview?
    @State private var batchTarget: BatchEditTarget?

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
                GeometryReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 34) {
                            PageMasthead(
                                eyebrow: masthead.eyebrow,
                                title: masthead.title,
                                subtitle: mastheadSubtitle(count: books.count)
                            )

                            if !libraryStore.checkedBookIDs.isEmpty {
                                CheckedBooksBar(
                                    count: libraryStore.checkedBookIDs.count,
                                    edit: { batchTarget = BatchEditTarget(bookIDs: libraryStore.checkedBookIDs) },
                                    recognise: recognise,
                                    clear: { libraryStore.checkedBookIDs = [] }
                                )
                            }

                            ForEach(sections) { section in
                                bookSection(section, showsTitle: sections.count > 1)
                            }

                            if visibleBookLimit < books.count {
                                LoadMoreBooksView(shown: visibleBooks.count, total: books.count) {
                                    loadMore(total: books.count)
                                }
                            }
                        }
                        // 详情栏展开时书单变窄，页边距随之收紧。
                        .padding(.horizontal, proxy.size.width < 480 ? 20 : 32)
                        .padding(.top, 14)
                        .padding(.bottom, 36)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
        .navigationTitle(selectionTitle)
        .paperScrollEdge()
        .hidingToolbarTitle()
        .modifier(LibraryToolbar(browseModeRaw: $browseModeRaw, filterMenu: filterMenu, catalogueMenu: catalogueMenu))
        .sheet(item: $review) { review in
            ProposalReviewSheet(review: review)
        }
        .sheet(item: $batchTarget) { target in
            BatchEditSheet(bookIDs: target.bookIDs)
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

    /// 书目 menu: actions on the ⌘-clicked books, or on the whole current list.
    private var catalogueMenu: some View {
        let targets = libraryStore.batchTargetBooks
        let scope = libraryStore.checkedBookIDs.isEmpty ? "当前列表 \(targets.count) 部" : "已选 \(targets.count) 部"
        return Menu {
            Section(scope) {
                Button("从文件名识别…", action: recognise)
                Button("批量编辑…") { batchTarget = BatchEditTarget(bookIDs: Set(targets.map(\.id))) }
                Button("导出表格…") { libraryStore.exportCSV(targets) }
            }
            Divider()
            Button("导入表格…") {
                if let proposals = libraryStore.proposalsFromCSV() {
                    review = ProposalReview(kind: .spreadsheet, proposals: proposals)
                }
            }
            if !libraryStore.checkedBookIDs.isEmpty {
                Button("取消选择") { libraryStore.checkedBookIDs = [] }
            }
        } label: {
            Label("书目", systemImage: "text.book.closed")
                .labelStyle(.titleAndIcon)
        }
        .disabled(targets.isEmpty)
        .help("识别、批量编辑或导出书目；按住 ⌘ 点按书目可多选")
    }

    private func recognise() {
        review = ProposalReview(kind: .recognition, proposals: libraryStore.recognitionProposals(for: libraryStore.batchTargetBooks))
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
        case .series(let series): return series
        }
    }

    private var masthead: (eyebrow: String, title: String) {
        switch libraryStore.sidebarSelection {
        case .all, .downloads, .statistics:
            return ("资料库", "全部藏书")
        case .favorites:
            return ("资料库", "收藏")
        case .status(let status):
            return ("整理状态", status.rawValue)
        case .source(let source):
            return ("来源", source)
        case .series(let series):
            return ("丛书", series)
        case .classification(let id):
            guard let node = libraryStore.classifications.first(where: { $0.id == id }) else {
                return ("四库", "未分类")
            }
            let parent = node.parentID.flatMap { parentID in
                libraryStore.classifications.first { $0.id == parentID }
            }
            return (parent?.name ?? "四库", node.name)
        }
    }

    private func mastheadSubtitle(count: Int) -> String {
        let query = libraryStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let total = "\(count.formatted()) 部"
        return query.isEmpty ? total : "“\(query)” · \(total)"
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
        VStack(alignment: .leading, spacing: browseMode == .covers ? 18 : 8) {
            if showsTitle {
                sectionHeading(section)
            }

            switch browseMode {
            case .covers:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128, maximum: 172), spacing: 22, alignment: .top)],
                    alignment: .leading,
                    spacing: 26
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

    private func sectionHeading(_ section: LibraryBookSection) -> some View {
        let node = libraryStore.classifications.first { $0.id == section.id }
        let parent = node?.parentID.flatMap { parentID in
            libraryStore.classifications.first { $0.id == parentID }
        }
        let top = parent ?? node

        return SectionHeading(title: node?.name ?? "未分类", note: parent?.name ?? "") {
            SealMark(
                text: MuTianTheme.sectionGlyph(forClassificationID: top?.id ?? section.id, name: top?.name ?? ""),
                color: MuTianTheme.sealColor(forClassificationID: top?.id ?? section.id),
                size: 18
            )
        } trailing: {
            Text("\(section.books.count.formatted()) 部")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private func groupedBooks(_ books: [Book]) -> [LibraryBookSection] {
        var grouped: [String: [Book]] = [:]
        var order: [String] = []

        let knownIDs = Set(libraryStore.classifications.map(\.id))
        for book in books {
            let id = knownIDs.contains(book.classificationID)
                ? book.classificationID
                : Classification.defaultUnclassifiedID
            if grouped[id] == nil {
                grouped[id] = []
                order.append(id)
            }
            grouped[id]?.append(book)
        }

        return order.map { id in
            LibraryBookSection(id: id, books: grouped[id] ?? [])
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

private struct LibraryToolbar<FilterMenu: View, CatalogueMenu: View>: ViewModifier {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Binding var browseModeRaw: String
    let filterMenu: FilterMenu
    let catalogueMenu: CatalogueMenu

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItemGroup { viewControls }
                ToolbarSpacer(.fixed)
                ToolbarItem { catalogueMenu }
                ToolbarSpacer(.fixed)
                ToolbarItem { importButton }
                ToolbarSpacer(.fixed)
                ToolbarItem { rescanButton }
            }
        } else {
            compatibleToolbar(content)
        }
        #else
        compatibleToolbar(content)
        #endif
    }

    private func compatibleToolbar(_ content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup { viewControls }
            ToolbarItem { catalogueMenu }
            ToolbarItem { importButton }
            ToolbarItem { rescanButton }
        }
    }

    @ViewBuilder
    private var viewControls: some View {
        filterMenu
        Picker("显示方式", selection: $browseModeRaw) {
            Label("封面", systemImage: "square.grid.2x2").tag(LibraryBrowseMode.covers.rawValue)
            Label("列表", systemImage: "list.bullet").tag(LibraryBrowseMode.list.rawValue)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("切换封面或列表")
    }

    private var importButton: some View {
        Button {
            libraryStore.presentImportPanel()
        } label: {
            Label("导入", systemImage: "square.and.arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .help("选择本地古籍文件夹或 PDF 加入资料库")
    }

    private var rescanButton: some View {
        Button {
            Task { await libraryStore.rescanKnownRoots() }
        } label: {
            Label(libraryStore.isScanning ? "扫描中…" : "重新扫描", systemImage: "arrow.clockwise")
                .labelStyle(.titleAndIcon)
        }
        .help("重新扫描已导入的目录，更新新增、改动和失效的书目")
        .disabled(libraryStore.roots.isEmpty || libraryStore.isScanning)
    }
}

/// Plain click opens the book; ⌘-click adds or removes it from the batch selection.
@MainActor
private func selectOrToggle(_ book: Book, in store: LibraryStore) {
    if NSEvent.modifierFlags.contains(.command) {
        store.toggleChecked(book)
    } else {
        store.selectBook(book)
    }
}

private struct CheckedBooksBar: View {
    let count: Int
    let edit: () -> Void
    let recognise: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MuTianTheme.cinnabar)
            Text("已选 \(count) 部")
                .font(.song(13, weight: .medium))
                .foregroundStyle(MuTianTheme.ink)
            Text("按住 ⌘ 点按可增减")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("从文件名识别…", action: recognise)
            Button("批量编辑…", action: edit)
            Button("取消选择", action: clear)
        }
        .buttonStyle(.link)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(MuTianTheme.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(MuTianTheme.hairline))
    }
}

private struct BookActions: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        OpenReaderWindowButton(book: book, title: "在新窗口中阅读")
        Divider()
        Button(book.isFavorite ? "取消收藏" : "收藏") {
            libraryStore.toggleFavorite(book)
        }
        Button("在 Finder 中显示") {
            libraryStore.revealInFinder(book)
        }
        Divider()
        Button(libraryStore.checkedBookIDs.contains(book.id) ? "取消选择" : "加入批量选择") {
            libraryStore.toggleChecked(book)
        }
        if let series = book.seriesName {
            Button("查看丛书“\(series)”") {
                libraryStore.sidebarSelection = .series(series)
            }
        }
    }
}

private struct BookCoverButton: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        Button {
            selectOrToggle(book, in: libraryStore)
        } label: {
            BookCoverView(
                book: book,
                isSelected: libraryStore.selectedBookID == book.id,
                isChecked: libraryStore.checkedBookIDs.contains(book.id)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { BookActions(book: book) }
    }
}

private struct BookListButton: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    @State private var isHovering = false

    var body: some View {
        Button {
            selectOrToggle(book, in: libraryStore)
        } label: {
            BookRowView(book: book, isChecked: libraryStore.checkedBookIDs.contains(book.id))
                .padding(.horizontal, 10)
                .background(rowFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .leading) {
                    if isSelected {
                        Rectangle()
                            .fill(MuTianTheme.cinnabar)
                            .frame(width: 2)
                            .padding(.vertical, 7)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(MuTianTheme.hairline)
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu { BookActions(book: book) }
    }

    private var rowFill: Color {
        if isSelected { return MuTianTheme.cinnabar.opacity(0.08) }
        return isHovering ? MuTianTheme.ink.opacity(0.04) : .clear
    }

    private var isSelected: Bool {
        libraryStore.selectedBookID == book.id
    }
}

private struct BookCoverView: View {
    let book: Book
    let isSelected: Bool
    var isChecked = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverThumbnailView(book: book, isRaised: isHovering || isSelected)
                .overlay(alignment: .topTrailing) {
                    if book.isFavorite {
                        SealMark(text: "藏", size: 20)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .padding(7)
                            .accessibilityLabel("已收藏")
                    }
                }
                .padding(5)
                .overlay {
                    if isSelected || isChecked {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(MuTianTheme.cinnabar, lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isChecked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(MuTianTheme.sealPaper, MuTianTheme.cinnabar)
                            .padding(9)
                            .accessibilityLabel("已选")
                    }
                }
                .offset(y: isHovering ? -2 : 0)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.displayTitle)
                    .font(.song(13, weight: .medium))
                    .foregroundStyle(isSelected ? MuTianTheme.cinnabar : MuTianTheme.ink)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    private var subtitle: String {
        if !book.author.isEmpty {
            return book.author
        }
        if book.pageCount > 0 {
            return "\(book.pageCount.formatted()) 页"
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
    var isChecked = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : MuTianTheme.fileTypeIcon(book.fileType))
                .font(.system(size: 12, weight: isChecked ? .regular : .light))
                .foregroundStyle(isChecked ? AnyShapeStyle(MuTianTheme.cinnabar) : AnyShapeStyle(.tertiary))
                .frame(width: 18)

            Text(book.title)
                .font(.song(14))
                .foregroundStyle(MuTianTheme.ink)
                .lineLimit(1)

            if let volume = book.volume {
                Text(volume)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if book.isFavorite {
                SealMark(text: "藏", size: 14)
                    .accessibilityLabel("已收藏")
            }

            Spacer(minLength: 12)

            if book.status != .pending {
                StatusBadge(text: book.status.rawValue, color: MuTianTheme.statusColor(book.status))
            }

            Text(book.author.isEmpty ? "—" : book.author)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
                .help(book.author)

            Text(book.publisherText.isEmpty ? "—" : book.publisherText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .help(book.publisherText)

            Text(book.pageCount > 0 ? "\(book.pageCount.formatted()) 页" : "")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
