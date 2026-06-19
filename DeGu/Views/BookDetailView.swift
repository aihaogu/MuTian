import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let bookID: UUID?

    var body: some View {
        if let bookID, let book = libraryStore.books.first(where: { $0.id == bookID }) {
            VStack(spacing: 0) {
                BookHeaderView(book: book)
                Divider()
                TabView {
                    ReaderView(book: book)
                        .tabItem { Label("阅读", systemImage: "book") }
                    BookMetadataEditor(book: book)
                        .tabItem { Label("书目", systemImage: "info.circle") }
                    PageNotesPlaceholder(book: book)
                        .tabItem { Label("校书", systemImage: "pencil.and.scribble") }
                }
            }
            .background(DeGuTheme.detailBackground)
        } else {
            DetailPlaceholder(
                title: "未选择古籍",
                systemImage: "books.vertical",
                message: "导入文件夹后，在中间浏览页选择一部古籍。"
            )
        }
    }
}

struct BookHeaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            BookCoverThumbnailView(book: book, cornerRadius: 6, showsShadow: false)
                .frame(width: 44, height: 58)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(book.title)
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    StatusBadge(text: book.status.rawValue, color: DeGuTheme.statusColor(book.status))
                }

                HStack(spacing: 6) {
                    MetaPill(text: libraryStore.classificationName(for: book.classificationID), systemImage: "square.grid.2x2", color: DeGuTheme.accent)
                    MetaPill(text: book.fileType.rawValue, systemImage: "doc.richtext", color: DeGuTheme.indigo)
                    MetaPill(text: "\(book.pageCount) 页", systemImage: "number", color: .secondary)
                    if !book.sourceName.isEmpty {
                        MetaPill(text: book.sourceName, systemImage: "building.columns", color: DeGuTheme.jade)
                    }
                }
            }
            Spacer()
            Button {
                libraryStore.toggleFavorite(book)
            } label: {
                Label(book.isFavorite ? "已收藏" : "收藏", systemImage: book.isFavorite ? "star.fill" : "star")
            }
            Button {
                libraryStore.revealInFinder(book)
            } label: {
                Label("Finder", systemImage: "folder")
            }
            Button {
                libraryStore.setBookDetailVisible(false)
            } label: {
                Label("收起详情", systemImage: "sidebar.right")
            }
            .labelStyle(.iconOnly)
            .help("收起书籍详情")
        }
        .padding(18)
        .background(.bar)
    }
}

struct BookMetadataEditor: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Form {
                    Section("基本书目") {
                        TextField("书名", text: binding(\.title))
                        TextField("作者", text: binding(\.author))
                        TextField("朝代", text: binding(\.dynasty))
                        TextField("版本", text: binding(\.edition))
                    }

                    Section("分类整理") {
                        Picker("四库分类", selection: classificationBinding) {
                            ForEach(libraryStore.classifications.sorted { $0.sortOrder < $1.sortOrder }) { node in
                                Text(libraryStore.classificationName(for: node.id)).tag(node.id)
                            }
                        }

                        Picker("整理状态", selection: statusBinding) {
                            ForEach(BookStatus.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }

                        TextField("标签（用空格分隔）", text: tagsBinding)
                    }

                    Section("来源和备注") {
                        TextField("来源", text: binding(\.sourceName))
                        TextField("来源 URL", text: binding(\.sourceURL))
                        TextField("备注", text: binding(\.notes), axis: .vertical)
                            .lineLimit(4...8)
                    }
                }
                .formStyle(.grouped)
                .deGuPanel()

                VStack(alignment: .leading, spacing: 8) {
                    Text("文件位置")
                        .font(.headline)
                    Text(book.localPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .deGuPanel()
            }
            .padding(18)
        }
        .background(DeGuTheme.detailBackground)
    }

    private func binding(_ keyPath: WritableKeyPath<Book, String>) -> Binding<String> {
        Binding(
            get: {
                libraryStore.books.first(where: { $0.id == book.id })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                guard var edited = libraryStore.books.first(where: { $0.id == book.id }) else { return }
                edited[keyPath: keyPath] = value
                libraryStore.update(edited)
            }
        )
    }

    private var classificationBinding: Binding<String> {
        Binding(
            get: { libraryStore.books.first(where: { $0.id == book.id })?.classificationID ?? Classification.defaultUnclassifiedID },
            set: { value in
                guard var edited = libraryStore.books.first(where: { $0.id == book.id }) else { return }
                edited.classificationID = value
                libraryStore.update(edited)
            }
        )
    }

    private var statusBinding: Binding<BookStatus> {
        Binding(
            get: { libraryStore.books.first(where: { $0.id == book.id })?.status ?? .pending },
            set: { value in
                guard var edited = libraryStore.books.first(where: { $0.id == book.id }) else { return }
                edited.status = value
                libraryStore.update(edited)
            }
        )
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { libraryStore.books.first(where: { $0.id == book.id })?.tags.joined(separator: " ") ?? "" },
            set: { value in
                guard var edited = libraryStore.books.first(where: { $0.id == book.id }) else { return }
                edited.tags = value.split(separator: " ").map(String.init)
                libraryStore.update(edited)
            }
        )
    }
}

struct PageNotesPlaceholder: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("校书工作台")
                .font(.title3)
                .fontWeight(.semibold)
            Text("当前已为页级 OCR、人工校对文本和页备注预留数据结构。后续可在这里做影像/文本对照、逐页校改、校记和版本对读。")
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 8) {
                StatusBadge(text: book.status.rawValue, color: DeGuTheme.statusColor(book.status))
                MetaPill(text: "\(book.pageCount) 页", systemImage: "doc", color: .secondary)
            }
        }
        .deGuPanel()
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeGuTheme.detailBackground)
    }
}
