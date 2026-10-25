import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @State private var expandedClassificationIDs: Set<String> = []

    var body: some View {
        let counts = ClassificationCounts(books: libraryStore.books, store: libraryStore)

        List(selection: $libraryStore.sidebarSelection) {
            Section {
                Label("浏览", systemImage: "books.vertical")
                    .badge(libraryStore.books.count)
                    .tag(SidebarSelection.all)
                Label("收藏", systemImage: "star")
                    .badge(libraryStore.books.filter(\.isFavorite).count)
                    .tag(SidebarSelection.favorites)
                HStack {
                    Label("下载", systemImage: "arrow.down.circle")
                    Spacer(minLength: 4)
                    if downloadStore.hasRunningTasks {
                        ProgressView()
                            .controlSize(.mini)
                            .help("有下载任务正在运行")
                    }
                }
                .tag(SidebarSelection.downloads)
                Label("统计", systemImage: "chart.bar")
                    .tag(SidebarSelection.statistics)
            }

            Section("四库分类") {
                ForEach(libraryStore.children(of: nil)) { node in
                    ClassificationSidebarRow(
                        node: node,
                        counts: counts,
                        expandedClassificationIDs: $expandedClassificationIDs
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("木天")
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarStatusStrip()
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
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.secondary)
                Text("资料库文件夹")
                Spacer(minLength: 4)
                Text("\(libraryStore.roots.count)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看资料库来自哪些文件夹，添加或移除位置（⇧⌘L）")
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
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
        Label(node.name, systemImage: iconName)
            .lineLimit(1)
            .badge(counts.total(for: node.id))
            .tag(SidebarSelection.classification(node.id))
            .contentShape(Rectangle())
            .onTapGesture {
                libraryStore.sidebarSelection = .classification(node.id)
            }
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

    private var iconName: String {
        if node.id == Classification.defaultUnclassifiedID { return "tray" }
        return node.parentID == nil ? "books.vertical" : "folder"
    }
}
