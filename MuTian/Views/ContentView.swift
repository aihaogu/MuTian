import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage("bookDetailWidth") private var bookDetailWidth = 560.0

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
    }

    @ViewBuilder
    private var workspace: some View {
        switch libraryStore.sidebarSelection {
        case .downloads:
            DownloadsView()
        case .statistics:
            StatisticsView()
        default:
            ResizableSplitView(
                resizableSide: .trailing,
                paneWidth: $bookDetailWidth,
                minPaneWidth: 380,
                maxPaneWidth: 1400,
                minOtherWidth: 260,
                showsTrailing: libraryStore.isBookDetailVisible && libraryStore.selectedBookID != nil
            ) {
                LibraryListView()
            } trailing: {
                BookDetailView(bookID: libraryStore.selectedBookID)
            }
        }
    }
}
