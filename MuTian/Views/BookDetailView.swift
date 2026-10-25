import SwiftUI

private enum BookDetailTab: String, CaseIterable, Identifiable {
    case reader = "阅读"
    case metadata = "书目"

    var id: String { rawValue }
}

struct BookDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let bookID: UUID?
    @State private var tab: BookDetailTab = .reader

    var body: some View {
        if let bookID, let book = libraryStore.books.first(where: { $0.id == bookID }) {
            VStack(spacing: 0) {
                BookHeaderView(book: book, tab: $tab)
                Divider()
                switch tab {
                case .reader:
                    ReaderView(book: book)
                        .id("\(book.id)|\(book.localPath)")
                case .metadata:
                    BookMetadataEditor(book: book)
                }
            }
            .background(MuTianTheme.detailBackground)
            .onChange(of: bookID) { _, _ in tab = .reader }
        } else {
            DetailPlaceholder(
                title: "未选择古籍",
                systemImage: "books.vertical",
                message: "在左侧书单中选择一部古籍。"
            )
        }
    }
}

private struct BookHeaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    @Binding var tab: BookDetailTab

    var body: some View {
        HStack(spacing: 10) {
            Text(book.title)
                .font(.system(.title3, design: .serif))
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(book.title)

            if !book.author.isEmpty {
                Text(book.author)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Picker("视图", selection: $tab) {
                ForEach(BookDetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            OpenReaderWindowButton(book: book)
                .labelStyle(.titleAndIcon)
                .controlSize(.regular)
                .disabled(!FileManager.default.fileExists(atPath: book.localPath))

            HStack(spacing: 2) {
                Button {
                    libraryStore.toggleFavorite(book)
                } label: {
                    Image(systemName: book.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(book.isFavorite ? MuTianTheme.cinnabar : .secondary)
                }
                .help(book.isFavorite ? "取消收藏" : "收藏")

                Button {
                    libraryStore.revealInFinder(book)
                } label: {
                    Image(systemName: "folder")
                }
                .help("在 Finder 中显示")

                Button {
                    libraryStore.setBookDetailVisible(false)
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("收起详情")
            }
            .buttonStyle(.borderless)
            .imageScale(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct BookMetadataEditor: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book

    var body: some View {
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

                TextField("标签", text: tagsBinding, prompt: Text("用空格分隔"))
            }

            Section("来源和备注") {
                TextField("来源", text: binding(\.sourceName))
                TextField("来源链接", text: binding(\.sourceURL))
                TextField("备注", text: binding(\.notes), axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("文件") {
                LabeledContent("格式", value: book.fileType.rawValue)
                if book.pageCount > 0 {
                    LabeledContent("页数", value: "\(book.pageCount) 页")
                }
                LabeledContent("位置") {
                    Text(book.localPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(book.localPath)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(MuTianTheme.detailBackground)
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
