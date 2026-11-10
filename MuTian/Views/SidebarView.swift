import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @State private var expandedClassificationIDs: Set<String> = []

    var body: some View {
        let counts = ClassificationCounts(books: libraryStore.books, store: libraryStore)

        List {
            Section {
                SidebarNavRow(title: "浏览", systemImage: "books.vertical", count: libraryStore.books.count)
                    .sidebarDestination(.all, in: libraryStore)
                SidebarNavRow(
                    title: "收藏",
                    systemImage: "star",
                    count: libraryStore.books.filter(\.isFavorite).count
                )
                .sidebarDestination(.favorites, in: libraryStore)
                SidebarNavRow(title: "下载", systemImage: "arrow.down.circle") {
                    if downloadStore.hasRunningTasks {
                        ProgressView()
                            .controlSize(.mini)
                            .help("有下载任务正在运行")
                    }
                }
                .sidebarDestination(.downloads, in: libraryStore)
                SidebarNavRow(title: "统计", systemImage: "chart.bar")
                    .sidebarDestination(.statistics, in: libraryStore)
            }

            Section {
                ForEach(libraryStore.children(of: nil)) { node in
                    ClassificationSidebarRow(
                        node: node,
                        counts: counts,
                        expandedClassificationIDs: $expandedClassificationIDs
                    )
                }
            } header: {
                Text("四库")
                    .font(.song(11, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MuTianTheme.sidebarBackground)
        .navigationTitle("木天")
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                SidebarBrandHeader()
                SidebarStatusStrip()
            }
            .background(MuTianTheme.sidebarBackground)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFoldersFooter()
        }
        .onAppear(perform: expandSelectedSection)
        .onChange(of: libraryStore.sidebarSelection) { _, _ in
            expandSelectedSection()
        }
    }

    private func expandSelectedSection() {
        guard case .classification(let id) = libraryStore.sidebarSelection,
              let top = topAncestorID(of: id) else { return }
        expandedClassificationIDs = [top]
    }

    private func topAncestorID(of id: String) -> String? {
        var current = libraryStore.classifications.first { $0.id == id }
        while let parentID = current?.parentID {
            current = libraryStore.classifications.first { $0.id == parentID }
        }
        return current?.id
    }
}

/// 侧栏顶部的名号：一方“木天”小印与馆名。
private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            SealMark(text: "木天", size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("木天")
                    .font(.song(18, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(MuTianTheme.ink)
                Text("古籍资料库")
                    .font(.system(size: 10))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("木天 古籍资料库")
    }
}

private struct SidebarCount: View {
    let value: Int

    var body: some View {
        if value > 0 {
            Text(value.formatted())
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SidebarNavRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    var count: Int = 0
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(MuTianTheme.ink.opacity(0.62))
                .frame(width: 20)
            Text(title)
                .font(.song(14, weight: .medium))
                .foregroundStyle(MuTianTheme.ink)
            Spacer(minLength: 4)
            accessory
            SidebarCount(value: count)
        }
        .padding(.vertical, 2)
    }
}

extension SidebarNavRow where Accessory == EmptyView {
    init(title: String, systemImage: String, count: Int = 0) {
        self.init(title: title, systemImage: systemImage, count: count) { EmptyView() }
    }
}

/// 选中行：淡墨底，左侧一道朱砂。
private struct SidebarRowHighlight: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? MuTianTheme.ink.opacity(0.075) : .clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(MuTianTheme.cinnabar)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                        .padding(.leading, 1)
                }
            }
            .padding(.horizontal, 8)
    }
}

private extension View {
    /// 侧栏的一行：整行可点，选中态自绘，不使用系统的强调色高亮。
    @MainActor
    func sidebarDestination(_ destination: SidebarSelection, in store: LibraryStore) -> some View {
        let isSelected = store.sidebarSelection == destination
        return Button {
            store.sidebarSelection = destination
        } label: {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowBackground(SidebarRowHighlight(isSelected: isSelected))
    }
}

private struct SidebarStatusStrip: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        let hasContent = libraryStore.isScanning
            || libraryStore.loadError != nil
            || libraryStore.saveError != nil
            || !libraryStore.lastImportMessage.isEmpty

        VStack(spacing: 0) {
            if hasContent {
                strip
            }
        }
        .task(id: dismissKey) { await autoDismiss() }
    }

    private var strip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = libraryStore.saveError {
                Text(error)
                    .foregroundStyle(MuTianTheme.cinnabar)
                    .lineLimit(3)
                Button("重试保存") { libraryStore.flush() }
                    .controlSize(.small)
            }
            if libraryStore.loadError != nil {
                Button("从备份恢复资料库…") { libraryStore.presentRecoveryPanel() }
                    .controlSize(.small)
            }
            if libraryStore.isScanning || !libraryStore.lastImportMessage.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if libraryStore.isScanning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(libraryStore.lastImportMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(libraryStore.lastImportMessage)
                    Spacer(minLength: 0)
                    if !libraryStore.isScanning {
                        Button {
                            libraryStore.lastImportMessage = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                        .help("关闭提示")
                    }
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.opacity)
    }

    private var dismissKey: String {
        "\(libraryStore.isScanning)|\(libraryStore.lastImportMessage)"
    }

    private func autoDismiss() async {
        let message = libraryStore.lastImportMessage
        guard !libraryStore.isScanning, !message.isEmpty else { return }
        let isWarning = ["失败", "无法", "不可用"].contains { message.contains($0) }
        try? await Task.sleep(for: .seconds(isWarning ? 12 : 5))
        guard !Task.isCancelled, !libraryStore.isScanning, libraryStore.lastImportMessage == message else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            libraryStore.lastImportMessage = ""
        }
    }
}

private struct SidebarFoldersFooter: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: LibraryFoldersWindow.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(MuTianTheme.ink.opacity(0.62))
                    .frame(width: 20)
                Text("资料库文件夹")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(libraryStore.roots.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看资料库来自哪些文件夹，添加或移除位置（⇧⌘L）")
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(MuTianTheme.sidebarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MuTianTheme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 12)
        }
    }
}

private struct ClassificationCounts {
    private var direct: [String: Int] = [:]
    private let store: LibraryStore

    @MainActor
    init(books: [Book], store: LibraryStore) {
        self.store = store
        for book in books {
            direct[book.classificationID, default: 0] += 1
        }
    }

    @MainActor
    func total(for id: String) -> Int {
        store.children(of: id).reduce(direct[id] ?? 0) { $0 + total(for: $1.id) }
    }
}

private struct ClassificationSidebarRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let node: Classification
    let counts: ClassificationCounts
    @Binding var expandedClassificationIDs: Set<String>

    var body: some View {
        let children = libraryStore.children(of: node.id)
        if children.isEmpty {
            rowLabel
        } else {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(children) { child in
                    ClassificationSidebarRow(
                        node: child,
                        counts: counts,
                        expandedClassificationIDs: $expandedClassificationIDs
                    )
                }
            } label: {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 9) {
            if node.parentID == nil {
                SealMark(
                    text: MuTianTheme.sectionGlyph(forClassificationID: node.id, name: node.name),
                    color: MuTianTheme.sealColor(forClassificationID: node.id),
                    size: 18
                )
                .frame(width: 20)
                Text(node.name)
                    .font(.song(14, weight: .medium))
                    .foregroundStyle(MuTianTheme.ink)
            } else {
                Text(node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(MuTianTheme.ink.opacity(0.86))
            }
            Spacer(minLength: 4)
            SidebarCount(value: counts.total(for: node.id))
        }
        .lineLimit(1)
        .padding(.vertical, node.parentID == nil ? 2 : 0)
        .sidebarDestination(.classification(node.id), in: libraryStore)
    }

    private var expandedBinding: Binding<Bool> {
        Binding {
            expandedClassificationIDs.contains(node.id)
        } set: { isExpanded in
            if isExpanded {
                expandedClassificationIDs.insert(node.id)
            } else {
                expandedClassificationIDs.remove(node.id)
            }
        }
    }
}
