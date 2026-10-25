import AppKit
import SwiftUI

enum LibraryFoldersWindow {
    static let id = "library-folders"
}

struct OpenLibraryFoldersButton: View {
    @Environment(\.openWindow) private var openWindow
    var title = "管理资料库文件夹…"

    var body: some View {
        Button(title) { openWindow(id: LibraryFoldersWindow.id) }
    }
}

struct LibraryFoldersView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var selection: Set<UUID> = []
    @State private var pendingRemoval: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            Text("资料库会扫描下列文件夹和文件。移除只会把对应书目移出资料库，不会删除磁盘上的文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if libraryStore.roots.isEmpty {
                DetailPlaceholder(title: "还没有资料库文件夹", systemImage: "folder.badge.plus", message: "点击下方“添加”，选择存放古籍的文件夹或 PDF。")
            } else {
                List(selection: $selection) {
                    ForEach(sortedRoots) { root in
                        LibraryFolderRow(root: root)
                            .tag(root.id)
                            .contextMenu { rowMenu(for: root) }
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }

            Divider()
            bottomBar
        }
        .frame(minWidth: 560, minHeight: 360)
        .tint(MuTianTheme.accent)
        .confirmationDialog(removalTitle, isPresented: removalBinding) {
            Button("移除", role: .destructive) {
                if libraryStore.removeRoots(pendingRemoval) {
                    selection.subtract(pendingRemoval)
                }
                pendingRemoval = []
            }
            Button("取消", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text(removalMessage)
        }
    }

    private var sortedRoots: [LibraryRoot] {
        libraryStore.roots.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                libraryStore.presentImportPanel()
            } label: {
                Label("添加…", systemImage: "plus")
            }
            .help("添加文件夹或 PDF 并立即扫描")

            Button {
                pendingRemoval = selection
            } label: {
                Label("移除", systemImage: "minus")
            }
            .disabled(selection.isEmpty || libraryStore.isScanning)
            .help("把选中的文件夹移出资料库")

            Spacer()

            if libraryStore.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text("正在扫描…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(libraryStore.roots.count) 个位置 · \(libraryStore.books.count) 部")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await libraryStore.rescanKnownRoots() }
            } label: {
                Label("全部重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(libraryStore.roots.isEmpty || libraryStore.isScanning)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func rowMenu(for root: LibraryRoot) -> some View {
        Button("在 Finder 中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: root.path)])
        }
        .disabled(!FileManager.default.fileExists(atPath: root.path))
        Button("重新扫描") {
            Task { await libraryStore.rescan(root) }
        }
        .disabled(libraryStore.isScanning)
        Divider()
        Button("移除…", role: .destructive) {
            pendingRemoval = selection.contains(root.id) ? selection : [root.id]
        }
        .disabled(libraryStore.isScanning)
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { !pendingRemoval.isEmpty }, set: { if !$0 { pendingRemoval = [] } })
    }

    private var removalTitle: String {
        pendingRemoval.count == 1 ? "移除这个文件夹？" : "移除 \(pendingRemoval.count) 个文件夹？"
    }

    private var removalMessage: String {
        let count = libraryStore.booksRemoved(withRoots: pendingRemoval).count
        let books = count == 0 ? "资料库中的书目不会减少。" : "\(count) 部书目会移出资料库，它们的收藏、备注和阅读进度一并清除。"
        return "\(books)磁盘上的文件不会删除；移除前会自动备份资料库索引，之后可以重新添加。"
    }
}

private struct LibraryFolderRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let root: LibraryRoot

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: nil)

        HStack(spacing: 10) {
            Image(systemName: exists ? iconName : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(exists ? MuTianTheme.accent : MuTianTheme.cinnabar)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: root.path).lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(root.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(root.path)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(libraryStore.bookCount(in: root)) 部")
                    .monospacedDigit()
                Text(exists ? scannedText : "找不到此位置")
                    .font(.caption)
                    .foregroundStyle(exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(MuTianTheme.cinnabar))
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
        return isDirectory.boolValue ? "folder.fill" : "doc.fill"
    }

    private var scannedText: String {
        guard let date = root.lastScannedAt else { return "尚未扫描" }
        return "扫描于 " + date.formatted(.relative(presentation: .named))
    }
}
