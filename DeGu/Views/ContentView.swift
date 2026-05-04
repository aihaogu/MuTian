import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadStore: DownloadTaskStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .searchable(text: $libraryStore.searchText, placement: .toolbar, prompt: "搜索书名、作者、来源、标签")
        .tint(DeGuTheme.accent)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    libraryStore.presentImportPanel()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入条目并建立索引，不复制原文件")

                Button {
                    downloadStore.addDraft(defaultDirectory: AppPaths.defaultManagedDownloadsDirectory.path)
                    libraryStore.sidebarSelection = .downloads
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .help("创建 bookget 下载任务")

                Button {
                    Task { await libraryStore.rescanKnownRoots() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(libraryStore.roots.isEmpty || libraryStore.isScanning)
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch libraryStore.sidebarSelection {
        case .downloads:
            DownloadTaskListView()
        case .statistics:
            StatisticsView()
        default:
            LibraryListView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch libraryStore.sidebarSelection {
        case .downloads:
            DownloadDetailView()
        case .statistics:
            StatisticsDetailView()
        default:
            BookDetailView(bookID: libraryStore.selectedBookID)
        }
    }
}
