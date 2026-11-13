import SwiftUI

private enum BookDetailTab: String, CaseIterable, Identifiable {
    case metadata = "书目"
    case reader = "阅读"

    var id: String { rawValue }
}

struct BookDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let bookID: UUID?
    @State private var tab: BookDetailTab = .metadata
    /// The reader stays alive once opened, so flipping between 书目 and 阅读 does not reload the file.
    @State private var readerOpened = false

    var body: some View {
        if let bookID, let book = libraryStore.books.first(where: { $0.id == bookID }) {
            VStack(spacing: 0) {
                BookHeaderView(book: book, tab: $tab)
                Rectangle()
                    .fill(MuTianTheme.hairline)
                    .frame(height: 1)
                ZStack {
                    if readerOpened || tab == .reader {
                        ReaderView(book: book)
                            .id("\(book.id)|\(book.localPath)")
                            .opacity(tab == .reader ? 1 : 0)
                            .disabled(tab != .reader)
                            .accessibilityHidden(tab != .reader)
                    }
                    BookMetadataEditor(book: book)
                        .id(book.id)
                        .opacity(tab == .metadata ? 1 : 0)
                        .disabled(tab != .metadata)
                        .accessibilityHidden(tab != .metadata)
                }
            }
            .background(MuTianTheme.detailBackground)
            .onChange(of: bookID) { _, _ in
                tab = .metadata
                readerOpened = false
            }
            .onChange(of: tab) { _, newTab in
                if newTab == .reader { readerOpened = true }
            }
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
            Text(book.displayTitle)
                .font(.song(17, weight: .semibold))
                .foregroundStyle(MuTianTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(book.displayTitle)

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
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(MuTianTheme.detailBackground)
    }
}

struct BookMetadataEditor: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    @State private var recognition: ProposalReview?
    @State private var isLookingUp = false

    var body: some View {
        // A plain stack instead of a grouped Form: Form takes ~80 ms to build and tear down,
        // which made selecting books and switching pages stutter.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorSection(title: "基本书目") {
                    HStack(spacing: 12) {
                        Button("从文件名识别…") {
                            let proposals = libraryStore.recognitionProposals(for: [book])
                            recognition = ProposalReview(kind: .recognition, proposals: proposals)
                        }
                        .help("按“书名-作者-出版社”等命名习惯重新拆分文件名，确认后写入")
                        Button("联网查询…") { isLookingUp = true }
                            .help("在 \(OnlineBookLookup.serviceName) 书目库中按书名查找出版社、年份和丛书")
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                } content: {
                    textRow("书名", \.title)
                    textRow("卷册", \.volumeText, prompt: "如 第3册、卷一至卷七")
                    textRow("作者", \.author, prompt: "如 王引之撰；李花蕾校点")
                    textRow("朝代", \.dynasty)
                    textRow("出版社", \.publisherText, suggestions: libraryStore.publishers)
                    textRow("版本", \.edition, prompt: "如 1980、点校本、明刻本")
                    textRow("丛书", \.seriesText, prompt: "不属于丛书可留空", suggestions: libraryStore.seriesCounts.map(\.name), isLast: true)
                } footer: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("文件名")
                        Text(book.fileName)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                EditorSection(title: "分类整理") {
                    EditorRow("四库分类") {
                        Picker("四库分类", selection: classificationBinding) {
                            ForEach(libraryStore.classifications.sorted { $0.sortOrder < $1.sortOrder }) { node in
                                Text(libraryStore.classificationName(for: node.id)).tag(node.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    EditorRow("整理状态") {
                        Picker("整理状态", selection: statusBinding) {
                            ForEach(BookStatus.allCases) { status in
                                Text(status.rawValue).tag(status)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    EditorRow("标签", isLast: true) {
                        DraftTextField(title: "标签", value: tagsBinding.wrappedValue, prompt: "用空格分隔") { tagsBinding.wrappedValue = $0 }
                    }
                }

                EditorSection(title: "来源和备注") {
                    textRow("来源", \.sourceName)
                    textRow("来源链接", \.sourceURL)
                    EditorRow("备注", isLast: true) {
                        DraftTextField(title: "备注", value: book.notes, axis: .vertical) { commit(\.notes, $0) }
                    }
                }

                EditorSection(title: "文件") {
                    EditorRow("格式") { Text(book.fileType.rawValue).foregroundStyle(.secondary) }
                    if book.pageCount > 0 {
                        EditorRow("页数") { Text("\(book.pageCount) 页").foregroundStyle(.secondary) }
                    }
                    EditorRow("位置", isLast: true) {
                        Text(book.localPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .help(book.localPath)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(MuTianTheme.detailBackground)
        .sheet(item: $recognition) { review in
            ProposalReviewSheet(review: review)
        }
        .sheet(isPresented: $isLookingUp) {
            OnlineLookupSheet(bookID: book.id)
        }
    }

    private func textRow(
        _ title: String,
        _ keyPath: WritableKeyPath<Book, String>,
        prompt: String? = nil,
        suggestions: [String] = [],
        isLast: Bool = false
    ) -> some View {
        EditorRow(title, isLast: isLast) {
            DraftTextField(title: title, value: book[keyPath: keyPath], prompt: prompt, suggestions: suggestions) {
                commit(keyPath, $0)
            }
        }
    }

    private func commit(_ keyPath: WritableKeyPath<Book, String>, _ value: String) {
        guard var edited = libraryStore.books.first(where: { $0.id == book.id }),
              edited[keyPath: keyPath] != value else { return }
        edited[keyPath: keyPath] = value
        libraryStore.update(edited)
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

/// 书目页的一组：小标题、浅墨底的卡片、可选的脚注。
private struct EditorSection<Accessory: View, Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) { content }
                .background(MuTianTheme.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MuTianTheme.hairline))

            footer
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

private extension EditorSection where Accessory == EmptyView, Footer == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content, footer: { EmptyView() })
    }
}

private extension EditorSection where Footer == EmptyView {
    init(title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: accessory, content: content, footer: { EmptyView() })
    }
}

private struct EditorRow<Value: View>: View {
    let title: String
    var isLast = false
    @ViewBuilder var value: Value

    init(_ title: String, isLast: Bool = false, @ViewBuilder value: () -> Value) {
        self.title = title
        self.isLast = isLast
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(MuTianTheme.ink)
                .fixedSize()
            Spacer(minLength: 8)
            value
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(MuTianTheme.hairline).frame(height: 1).padding(.leading, 12)
            }
        }
    }
}

/// Edits a copy and writes it back after a short pause, on Return, or when focus leaves.
/// Writing on every keystroke re-rendered the whole library for each character typed.
struct DraftTextField: View {
    let title: String
    let value: String
    var prompt: String? = nil
    var axis: Axis = .horizontal
    var suggestions: [String] = []
    let commit: (String) -> Void

    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text(prompt ?? ""), axis: axis)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .focused($isFocused)
                .onSubmit(flush)
            if !matches.isEmpty {
                Menu {
                    ForEach(matches, id: \.self) { item in
                        Button(item) {
                            text = item
                            flush()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("从资料库已有的\(title)中选择")
            }
        }
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in
            if !isFocused && pending == nil { text = newValue }
        }
        .onChange(of: text) { _, newValue in
            guard newValue != value else { return }
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                flush()
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { flush() }
        }
        .onDisappear(perform: flush)
    }

    private func flush() {
        pending?.cancel()
        pending = nil
        if text != value { commit(text) }
    }

    private var matches: [String] {
        guard !suggestions.isEmpty else { return [] }
        let query = text.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty || suggestions.contains(query)
            ? suggestions
            : suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
        return Array(filtered.prefix(30))
    }
}
