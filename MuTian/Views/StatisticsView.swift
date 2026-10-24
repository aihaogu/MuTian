import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        let books = libraryStore.books
        let sections = libraryStore.countsByTopClassification()
        let maxSection = max(sections.map(\.1).max() ?? 0, 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    MetricTile(title: "全部古籍", value: books.count, color: .primary)
                    MetricTile(title: "收藏", value: books.filter(\.isFavorite).count, color: MuTianTheme.cinnabar)
                    MetricTile(title: "待整理", value: books.filter { $0.status == .pending }.count, color: .secondary)
                    MetricTile(title: "需校对", value: books.filter { $0.status == .needsProofreading }.count, color: MuTianTheme.accent)
                }

                StatSection(title: "四部") {
                    ForEach(sections, id: \.0) { name, count in
                        ProportionRow(title: name, value: count, fraction: Double(count) / Double(maxSection))
                    }
                }

                HStack(alignment: .top, spacing: 32) {
                    StatSection(title: "文件类型") {
                        let rows = BookFileType.allCases
                            .map { type in (type.rawValue, books.filter { $0.fileType == type }.count) }
                            .filter { $0.1 > 0 }
                        countRows(rows)
                    }
                    StatSection(title: "来源") {
                        let rows = libraryStore.sources
                            .map { source in (source, books.filter { $0.sourceName == source }.count) }
                            .sorted { $0.1 > $1.1 }
                        countRows(rows)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(MuTianTheme.detailBackground)
        .navigationTitle("统计")
        .navigationSubtitle("\(books.count) 部")
    }

    @ViewBuilder
    private func countRows(_ rows: [(String, Int)]) -> some View {
        if rows.isEmpty {
            Text("暂无数据")
                .foregroundStyle(.tertiary)
        } else {
            ForEach(rows, id: \.0) { title, count in
                HStack {
                    Text(title)
                        .lineLimit(1)
                    Spacer()
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .muTianPanel()
    }
}

private struct StatSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .serif))
            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProportionRow: View {
    let title: String
    let value: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 56, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MuTianTheme.hairline)
                    Capsule()
                        .fill(MuTianTheme.accent.opacity(0.75))
                        .frame(width: value > 0 ? max(proxy.size.width * fraction, 6) : 0)
                }
            }
            .frame(height: 8)
            Text("\(value)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}
