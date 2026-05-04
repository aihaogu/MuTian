import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        List(selection: $libraryStore.sidebarSelection) {
            Section {
                Label("全部古籍", systemImage: "books.vertical")
                    .tag(SidebarSelection.all)
                Label("收藏", systemImage: "star")
                    .tag(SidebarSelection.favorites)
                Label("下载任务", systemImage: "arrow.down.circle")
                    .tag(SidebarSelection.downloads)
                Label("统计", systemImage: "chart.bar")
                    .tag(SidebarSelection.statistics)
            }

            Section("四库分类") {
                ForEach(flatClassifications, id: \.node.id) { row in
                    Label(row.node.name, systemImage: row.node.id == Classification.defaultUnclassifiedID ? "tray" : "folder")
                        .padding(.leading, CGFloat(row.level * 12))
                        .tag(SidebarSelection.classification(row.node.id))
                }
            }

            Section("整理状态") {
                ForEach(BookStatus.allCases) { status in
                    Label(status.rawValue, systemImage: statusIcon(status))
                        .tag(SidebarSelection.status(status))
                }
            }

            if !libraryStore.sources.isEmpty {
                Section("来源") {
                    ForEach(libraryStore.sources, id: \.self) { source in
                        Label(source, systemImage: "building.columns")
                            .tag(SidebarSelection.source(source))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("得古")
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if libraryStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                if !libraryStore.lastImportMessage.isEmpty {
                    Text(libraryStore.lastImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(8)
        }
    }

    private var flatClassifications: [(node: Classification, level: Int)] {
        func rows(parentID: String?, level: Int) -> [(Classification, Int)] {
            libraryStore.children(of: parentID).flatMap { node in
                [(node, level)] + rows(parentID: node.id, level: level + 1)
            }
        }
        return rows(parentID: nil, level: 0)
    }

    private func statusIcon(_ status: BookStatus) -> String {
        switch status {
        case .pending: return "tray"
        case .organized: return "checkmark.circle"
        case .needsProofreading: return "exclamationmark.bubble"
        case .proofreading: return "pencil.and.outline"
        case .proofread: return "checkmark.seal"
        }
    }
}
