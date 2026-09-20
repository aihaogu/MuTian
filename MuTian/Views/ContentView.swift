import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var downloadStore: DownloadTaskStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
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
                Button {
                    libraryStore.presentImportPanel()
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("导入本地古籍条目")

                Button {
                    libraryStore.sidebarSelection = .downloads
                } label: {
                    if downloadStore.hasRunningTasks {
                        Label {
                            Text("下载")
                        } icon: {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Label("下载", systemImage: "arrow.down.circle")
                    }
                }
                .help("打开下载")

                if libraryStore.sidebarSelection.usesBookDetail {
                    Button {
                        libraryStore.setBookDetailVisible(!libraryStore.isBookDetailVisible)
                    } label: {
                        Label(libraryStore.isBookDetailVisible ? "收起详情" : "展开详情", systemImage: "sidebar.right")
                    }
                    .disabled(libraryStore.selectedBookID == nil)
                    .help(libraryStore.isBookDetailVisible ? "收起书籍详情" : "展开书籍详情")
                }

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
    private var workspace: some View {
        switch libraryStore.sidebarSelection {
        case .downloads:
            HSplitView {
                DownloadTaskListView()
                    .frame(minWidth: 280, idealWidth: 360)
                DownloadDetailView()
                    .frame(minWidth: 360)
            }
        case .statistics:
            HSplitView {
                StatisticsView()
                    .frame(minWidth: 280, idealWidth: 360)
                StatisticsDetailView()
                    .frame(minWidth: 360)
            }
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
