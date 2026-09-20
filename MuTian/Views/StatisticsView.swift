import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        List {
            Section("总览") {
                StatRow(title: "全部古籍", value: libraryStore.books.count, systemImage: "books.vertical")
                StatRow(title: "收藏", value: libraryStore.books.filter(\.isFavorite).count, systemImage: "star")
                StatRow(title: "未分类", value: libraryStore.books.filter { $0.classificationID == Classification.defaultUnclassifiedID }.count, systemImage: "tray")
            }

            Section("四部") {
                ForEach(libraryStore.countsByTopClassification(), id: \.0) { name, count in
                    StatRow(title: name, value: count, systemImage: "folder")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MuTianTheme.detailBackground)
        .navigationTitle("统计")
    }
}

struct StatisticsDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("资料库统计")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("按收藏、四库分类、文件形态和来源汇总。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(MuTianTheme.accent)
                }
                .muTianPanel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    MetricCard(title: "全部古籍", value: "\(libraryStore.books.count)", icon: "books.vertical")
                    MetricCard(title: "收藏", value: "\(libraryStore.books.filter(\.isFavorite).count)", icon: "star")
                    MetricCard(title: "PDF", value: "\(libraryStore.books.filter { $0.fileType == .pdf }.count)", icon: "doc.richtext")
                    MetricCard(title: "图片序列", value: "\(libraryStore.books.filter { $0.fileType == .imageSequence }.count)", icon: "photo.on.rectangle")
                    MetricCard(title: "电子书", value: "\(libraryStore.books.filter { $0.fileType == .ebook }.count)", icon: "book")
                    MetricCard(title: "文档", value: "\(libraryStore.books.filter { $0.fileType == .document }.count)", icon: "doc")
                    MetricCard(title: "文本", value: "\(libraryStore.books.filter { $0.fileType == .text }.count)", icon: "text.page")
                    MetricCard(title: "待整理", value: "\(libraryStore.books.filter { $0.status == .pending }.count)", icon: "tray")
                    MetricCard(title: "需校对", value: "\(libraryStore.books.filter { $0.status == .needsProofreading }.count)", icon: "pencil.and.outline")
                }

                Divider()

                Text("来源统计")
                    .font(.headline)
                ForEach(libraryStore.sources, id: \.self) { source in
                    HStack {
                        Text(source)
                        Spacer()
                        Text("\(libraryStore.books.filter { $0.sourceName == source }.count)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(18)
        }
        .background(MuTianTheme.detailBackground)
    }
}

struct StatRow: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(MuTianTheme.accent)
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .muTianPanel()
    }
}
