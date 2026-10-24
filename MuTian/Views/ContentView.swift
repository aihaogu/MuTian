import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            workspace
        }
        .searchable(text: $libraryStore.searchText, placement: .toolbar, prompt: "搜索书名、作者、来源、标签")
        .onChange(of: libraryStore.searchText) { _, _ in
            libraryStore.syncSelectionWithFilter()
        }
        .onChange(of: libraryStore.sidebarSelection) { _, _ in
            libraryStore.syncSelectionWithFilter()
        }
        .tint(MuTianTheme.accent)
        .toolbar {
            ToolbarItemGroup {
                switch libraryStore.sidebarSelection {
                case .downloads:
                    Button {
                        downloadStore.addDraft(settings: settingsStore.settings)
                    } label: {
                        Label("新建任务", systemImage: "plus")
                    }
                    .help("新建下载任务")
                case .statistics:
                    EmptyView()
                default:
                    Button {
                        libraryStore.presentImportPanel()
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .help("导入本地古籍条目")

                    Button {
                        Task { await libraryStore.rescanKnownRoots() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .help("重新扫描已导入的目录")
                    .disabled(libraryStore.roots.isEmpty || libraryStore.isScanning)
                }
            }
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch libraryStore.sidebarSelection {
        case .downloads:
            HSplitView {
                DownloadTaskListView()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
                DownloadDetailView()
                    .frame(minWidth: 420)
            }
        case .statistics:
            StatisticsView()
        default:
            HSplitView {
                LibraryListView()
                    .frame(minWidth: 320, idealWidth: 500)
                if libraryStore.isBookDetailVisible, libraryStore.selectedBookID != nil {
                    BookDetailView(bookID: libraryStore.selectedBookID)
                        .frame(minWidth: 420, idealWidth: 620)
                }
            }
        }
    }
}
