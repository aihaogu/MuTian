import SwiftUI

/// A text field with a menu of values already used in the library (出版社、丛书).
struct SuggestingTextField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    var prompt: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: prompt.map { Text($0) })
            if !matches.isEmpty {
                Menu {
                    ForEach(matches, id: \.self) { value in
                        Button(value) { text = value }
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
    }

    private var matches: [String] {
        let query = text.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty || suggestions.contains(query)
            ? suggestions
            : suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
        return Array(filtered.prefix(30))
    }
}

// MARK: - Reviewing proposed changes

struct ProposalReview: Identifiable {
    enum Kind {
        case recognition
        case spreadsheet

        var title: String {
            switch self {
            case .recognition: return "从文件名识别书目"
            case .spreadsheet: return "导入书目表格"
            }
        }

        var backupName: String {
            switch self {
            case .recognition: return "recognition"
            case .spreadsheet: return "csv-import"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let proposals: [BookChangeProposal]
}

/// Lists every proposed field change with its own checkbox; nothing is written until “应用”.
struct ProposalReviewSheet: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let review: ProposalReview
    @State private var proposals: [BookChangeProposal] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(MuTianTheme.hairline).frame(height: 1)
            if proposals.isEmpty {
                DetailPlaceholder(
                    title: "没有需要修改的地方",
                    systemImage: "checkmark.circle",
                    message: review.kind == .recognition ? "文件名里识别出的内容与现有书目一致。" : "表格内容与现有书目一致。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach($proposals) { $proposal in
                            ProposalRow(proposal: $proposal, book: book(proposal.bookID))
                            Rectangle().fill(MuTianTheme.hairline).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            Rectangle().fill(MuTianTheme.hairline).frame(height: 1)
            footer
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 420, idealHeight: 620)
        .background(MuTianTheme.detailBackground)
        .tint(MuTianTheme.controlInk)
        .onAppear { proposals = review.proposals }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(review.kind.title)
                .font(.song(18, weight: .semibold))
                .foregroundStyle(MuTianTheme.ink)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var summary: String {
        let books = proposals.count
        let accepted = proposals.reduce(0) { $0 + $1.acceptedCount }
        let total = proposals.reduce(0) { $0 + $1.changes.count }
        guard books > 0 else { return "" }
        var text = "\(books) 部书目共 \(total) 处不同，已勾选 \(accepted) 处。"
        if review.kind == .recognition {
            text += "原值为空或取自文件名的默认勾选；你改过的内容默认不勾选。"
        }
        return text
    }

    private var footer: some View {
        HStack {
            Button("全部勾选") { setAll(true) }
                .disabled(proposals.isEmpty)
            Button("全部取消") { setAll(false) }
                .disabled(proposals.isEmpty)
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("应用") {
                libraryStore.apply(proposals, backupName: proposals.count > 1 ? review.kind.backupName : nil)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(proposals.allSatisfy { $0.acceptedCount == 0 })
        }
        .padding(16)
    }

    private func setAll(_ value: Bool) {
        for index in proposals.indices {
            for change in proposals[index].changes.indices {
                proposals[index].changes[change].isAccepted = value
            }
        }
    }

    private func book(_ id: UUID) -> Book? {
        libraryStore.books.first { $0.id == id }
    }
}

private struct ProposalRow: View {
    @Binding var proposal: BookChangeProposal
    let book: Book?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposal.fileName)
                .font(.song(13, weight: .medium))
                .foregroundStyle(MuTianTheme.ink)
                .lineLimit(2)
                .textSelection(.enabled)
            ForEach($proposal.changes) { $change in
                Toggle(isOn: $change.isAccepted) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(change.field.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(change.oldValue.isEmpty ? "（空）" : change.oldValue)
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .strikethrough(change.isAccepted && !change.oldValue.isEmpty)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 240, alignment: .leading)
                            .help(change.oldValue)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(change.newValue.isEmpty ? "（清空）" : change.newValue)
                            .font(.system(size: 12))
                            .foregroundStyle(change.isAccepted ? MuTianTheme.ink : .secondary)
                            .lineLimit(2)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Batch editing

struct BatchEditSheet: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookIDs: Set<UUID>
    @State private var values: [BookField: String] = [:]
    @State private var enabled: Set<BookField> = []

    private let fields: [BookField] = [.series, .publisher, .edition, .author, .dynasty]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("批量编辑 \(bookIDs.count) 部书目")
                    .font(.song(18, weight: .semibold))
                    .foregroundStyle(MuTianTheme.ink)
                Text("勾选要统一修改的项；留空并勾选表示清空。修改前会备份资料库。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(fields) { field in
                    GridRow {
                        Toggle(field.rawValue, isOn: enabledBinding(field))
                            .toggleStyle(.checkbox)
                            .frame(width: 80, alignment: .leading)
                        SuggestingTextField(
                            title: field.rawValue,
                            text: valueBinding(field),
                            suggestions: suggestions(for: field),
                            prompt: placeholder(for: field)
                        )
                        .opacity(enabled.contains(field) ? 1 : 0.6)
                    }
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("应用到 \(bookIDs.count) 部") {
                    let changes = values.filter { enabled.contains($0.key) }
                        .merging(enabled.filter { values[$0] == nil }.map { ($0, "") }) { current, _ in current }
                    libraryStore.batchUpdate(bookIDs, values: changes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enabled.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520, height: 360)
        .background(MuTianTheme.detailBackground)
        .tint(MuTianTheme.controlInk)
        .onAppear(perform: prefill)
    }

    /// Shows the shared value when every selected book already agrees.
    private func prefill() {
        let selected = libraryStore.books.filter { bookIDs.contains($0.id) }
        for field in fields {
            let distinct = Set(selected.map { $0[keyPath: field.keyPath] })
            if distinct.count == 1, let value = distinct.first { values[field] = value }
        }
    }

    private func suggestions(for field: BookField) -> [String] {
        switch field {
        case .series: return libraryStore.seriesCounts.map(\.name)
        case .publisher: return libraryStore.publishers
        default: return []
        }
    }

    private func placeholder(for field: BookField) -> String? {
        let selected = libraryStore.books.filter { bookIDs.contains($0.id) }
        let distinct = Set(selected.map { $0[keyPath: field.keyPath] })
        return distinct.count > 1 ? "多个不同的值" : nil
    }

    private func enabledBinding(_ field: BookField) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(field) },
            set: { if $0 { enabled.insert(field) } else { enabled.remove(field) } }
        )
    }

    private func valueBinding(_ field: BookField) -> Binding<String> {
        Binding(
            get: { values[field] ?? "" },
            set: { values[field] = $0; enabled.insert(field) }
        )
    }
}

// MARK: - Online lookup

struct OnlineLookupSheet: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID

    @State private var titleQuery = ""
    @State private var authorQuery = ""
    @State private var records: [OnlineBookRecord] = []
    @State private var selectedRecordID: OnlineBookRecord.ID?
    @State private var proposal: BookChangeProposal?
    @State private var isSearching = false
    @State private var message = ""
    @State private var hasSearched = false

    private let lookupFields: [BookField] = [.title, .author, .dynasty, .publisher, .edition, .series]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("联网查询书目")
                    .font(.song(18, weight: .semibold))
                    .foregroundStyle(MuTianTheme.ink)
                Text("在 \(OnlineBookLookup.serviceName)（日本国立情报学研究所联合目录）中查找；只发送下面的书名和作者，结果转为简体，选中一条后逐项确认写入。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("书名", text: $titleQuery)
                        .onSubmit(search)
                    TextField("作者（可留空）", text: $authorQuery)
                        .frame(width: 160)
                        .onSubmit(search)
                    Button(isSearching ? "查询中…" : "查询", action: search)
                        .disabled(isSearching || titleQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)

            Rectangle().fill(MuTianTheme.hairline).frame(height: 1)

            HSplitView {
                resultsList
                    .frame(minWidth: 300, idealWidth: 340)
                comparison
                    .frame(minWidth: 300)
            }

            Rectangle().fill(MuTianTheme.hairline).frame(height: 1)
            HStack {
                if let url = selectedRecord.flatMap({ URL(string: $0.url) }) {
                    Link("在网页中查看这条记录", destination: url)
                        .font(.callout)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("写入勾选的项") {
                    if let proposal { libraryStore.apply([proposal], backupName: nil) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSearching || (proposal?.acceptedCount ?? 0) == 0)
            }
            .padding(16)
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 560)
        .background(MuTianTheme.detailBackground)
        .tint(MuTianTheme.controlInk)
        .onAppear {
            guard let book else { return }
            titleQuery = book.title
            authorQuery = OnlineBookLookup.searchableAuthor(book.author)
            search()
        }
        .onChange(of: selectedRecordID) { _, _ in rebuildProposal() }
    }

    private var book: Book? {
        libraryStore.books.first { $0.id == bookID }
    }

    private var selectedRecord: OnlineBookRecord? {
        records.first { $0.id == selectedRecordID }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty {
            DetailPlaceholder(
                title: hasSearched ? "没有找到" : "尚未查询",
                systemImage: "magnifyingglass",
                message: message.isEmpty ? "试着缩短书名，或去掉作者再查。" : message
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(records, selection: $selectedRecordID) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.song(13, weight: .medium))
                        .lineLimit(2)
                    Text([record.author, record.publisher, record.year].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !record.series.isEmpty {
                        Text("丛书：\(record.series)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 3)
                .tag(record.id)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var comparison: some View {
        if let binding = Binding($proposal) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("勾选要写入的项")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(binding.changes) { $change in
                        Toggle(isOn: $change.isAccepted) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.field.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                Text("现在：\(change.oldValue.isEmpty ? "（空）" : change.oldValue)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Text("查到：\(change.newValue)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MuTianTheme.ink)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            DetailPlaceholder(
                title: selectedRecord == nil ? "选择一条记录" : "与现有书目一致",
                systemImage: "list.bullet.rectangle",
                message: selectedRecord == nil ? "在左侧选中查到的书目，对照后再写入。" : "这条记录没有可补充的内容。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func search() {
        let title = titleQuery, author = authorQuery
        guard !isSearching, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        selectedRecordID = nil
        records = []
        proposal = nil
        message = ""
        Task {
            do {
                var found = try await OnlineBookLookup.search(title: title, author: author)
                if let book { found = OnlineBookLookup.ranked(found, for: book) }
                records = found
                selectedRecordID = found.first?.id
                message = ""
            } catch {
                records = []
                selectedRecordID = nil
                message = (error as? LocalizedError)?.errorDescription ?? "网络不可用：\(error.localizedDescription)"
            }
            hasSearched = true
            isSearching = false
            rebuildProposal()
        }
    }

    /// Title changes are offered but not pre-ticked: catalogue titles are often in a different form.
    private func rebuildProposal() {
        guard let book, let record = selectedRecord else { proposal = nil; return }
        let changes = lookupFields.compactMap { field -> FieldChange? in
            let newValue = record.value(for: field)
            let oldValue = book[keyPath: field.keyPath]
            guard !newValue.isEmpty, newValue != oldValue else { return nil }
            return FieldChange(field: field, oldValue: oldValue, newValue: newValue, isAccepted: field != .title && oldValue.isEmpty)
        }
        proposal = changes.isEmpty ? nil : BookChangeProposal(bookID: book.id, fileName: book.fileName, changes: changes)
    }
}
