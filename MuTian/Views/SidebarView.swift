import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var expandedClassificationIDs: Set<String> = Set(["jing", "shi", "zi", "ji", "other"])

    var body: some View {
        List(selection: $libraryStore.sidebarSelection) {
            Section {
                Label("浏览", systemImage: "books.vertical")
                    .tag(SidebarSelection.all)
                Label("收藏", systemImage: "star")
                    .tag(SidebarSelection.favorites)
                Label("下载", systemImage: "arrow.down.circle")
                    .tag(SidebarSelection.downloads)
                Label("统计", systemImage: "chart.bar")
                    .tag(SidebarSelection.statistics)
            }

            Section("四库分类") {
                ForEach(libraryStore.children(of: nil)) { node in
                    ClassificationSidebarRow(
                        node: node,
                        level: 0,
                        expandedClassificationIDs: $expandedClassificationIDs
                    )
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
        .navigationTitle("木天")
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

private struct ClassificationSidebarRow: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let node: Classification
    let level: Int
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
                        level: level + 1,
                        expandedClassificationIDs: $expandedClassificationIDs
                    )
                }
            } label: {
                rowLabel
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? MuTianTheme.accent : .secondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(level * 12))
        .foregroundStyle(isSelected ? MuTianTheme.accent : .primary)
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

    private var isSelected: Bool {
        libraryStore.sidebarSelection == .classification(node.id)
    }

    private var iconName: String {
        node.id == Classification.defaultUnclassifiedID ? "tray" : "folder"
    }
}
