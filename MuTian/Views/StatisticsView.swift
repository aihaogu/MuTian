import SwiftUI

private struct SectionCount: Identifiable {
    let id: String
    let name: String
    let count: Int
}

struct StatisticsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        let books = libraryStore.books
        let total = books.count
        let sections = sectionCounts()
        let maxSection = max(sections.map(\.count).max() ?? 0, 1)

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageMasthead(eyebrow: "资料库", title: "藏书统计", subtitle: "共 \(total.formatted()) 部")

                HStack(spacing: 0) {
                    MetricCell(title: "藏书", value: total)
                    metricDivider
                    MetricCell(title: "收藏", value: books.filter(\.isFavorite).count)
                    metricDivider
                    MetricCell(title: "已整理", value: books.filter { $0.status != .pending }.count)
                    metricDivider
                    MetricCell(title: "待整理", value: books.filter { $0.status == .pending }.count)
                    metricDivider
                    MetricCell(
                        title: "需校对",
                        value: books.filter { $0.status == .needsProofreading }.count,
                        highlightsNonZero: true
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "四部", note: "经史子集")
                    ProportionStrip(sections: sections, total: total)
                        .padding(.bottom, 2)
                    VStack(spacing: 0) {
                        ForEach(sections) { section in
                            SectionRow(
                                section: section,
                                fraction: Double(section.count) / Double(maxSection),
                                share: total > 0 ? Double(section.count) / Double(total) : 0
                            ) {
                                libraryStore.sidebarSelection = .classification(section.id)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 44) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "文件类型")
                        let rows = BookFileType.allCases
                            .map { type in (type, books.filter { $0.fileType == type }.count) }
                            .filter { $0.1 > 0 }
                        if rows.isEmpty {
                            emptyNote
                        } else {
                            VStack(spacing: 0) {
                                ForEach(rows, id: \.0) { type, count in
                                    CountRow(title: type.rawValue, count: count) {
                                        Image(systemName: MuTianTheme.fileTypeIcon(type))
                                            .font(.system(size: 12, weight: .light))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 18)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "整理状态")
                        VStack(spacing: 0) {
                            ForEach(BookStatus.allCases) { status in
                                CountRow(
                                    title: status.rawValue,
                                    count: books.filter { $0.status == status }.count,
                                    action: { libraryStore.sidebarSelection = .status(status) }
                                ) {
                                    Circle()
                                        .fill(MuTianTheme.statusColor(status))
                                        .frame(width: 7, height: 7)
                                        .frame(width: 18)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                let sources = libraryStore.sources
                    .map { source in (source, books.filter { $0.sourceName == source }.count) }
                    .sorted { $0.1 > $1.1 }
                if !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "来源")
                        VStack(spacing: 0) {
                            ForEach(sources, id: \.0) { source, count in
                                CountRow(
                                    title: source,
                                    count: count,
                                    action: { libraryStore.sidebarSelection = .source(source) }
                                ) { EmptyView() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 44)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(MuTianTheme.detailBackground)
        .navigationTitle("统计")
        .paperScrollEdge()
        .hidingToolbarTitle()
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(MuTianTheme.hairline)
            .frame(width: 1, height: 46)
            .padding(.trailing, 22)
    }

    private var emptyNote: some View {
        Text("暂无数据")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 6)
    }

    private func sectionCounts() -> [SectionCount] {
        let ids = libraryStore.children(of: nil)
            .map(\.id)
            .filter { $0 != Classification.defaultUnclassifiedID } + [Classification.defaultUnclassifiedID]
        let counts = libraryStore.countsByTopClassification()
        return zip(ids, counts).map { id, row in
            SectionCount(id: id, name: row.0, count: row.1)
        }
    }
}

private struct MetricCell: View {
    let title: String
    let value: Int
    var highlightsNonZero = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .tracking(2)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value.formatted())
                    .font(.song(32, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(highlightsNonZero && value > 0 ? MuTianTheme.cinnabar : MuTianTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("部")
                    .font(.song(12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 一条色带，按四部书衣颜色显示各部占比。
private struct ProportionStrip: View {
    let sections: [SectionCount]
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let visible = sections.filter { $0.count > 0 }
            let spacing: CGFloat = 2
            let available = max(proxy.size.width - spacing * CGFloat(max(visible.count - 1, 0)), 0)

            HStack(spacing: spacing) {
                ForEach(visible) { section in
                    Rectangle()
                        .fill(MuTianTheme.sectionColor(forClassificationID: section.id))
                        .frame(width: max(available * CGFloat(section.count) / CGFloat(max(total, 1)), 2))
                        .help("\(section.name) \(section.count.formatted()) 部")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

private struct SectionRow: View {
    let section: SectionCount
    let fraction: Double
    let share: Double
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let color = MuTianTheme.sectionColor(forClassificationID: section.id)

        Button(action: action) {
            HStack(spacing: 12) {
                SealMark(
                    text: MuTianTheme.sectionGlyph(forClassificationID: section.id, name: section.name),
                    color: MuTianTheme.sealColor(forClassificationID: section.id),
                    size: 20
                )
                Text(section.name)
                    .font(.song(14, weight: .medium))
                    .foregroundStyle(MuTianTheme.ink)
                    .frame(width: 58, alignment: .leading)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(MuTianTheme.hairline)
                            .frame(height: 1)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(color)
                            .frame(width: section.count > 0 ? max(proxy.size.width * fraction, 3) : 0, height: 6)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 6)

                Text(section.count.formatted())
                    .font(.song(15))
                    .monospacedDigit()
                    .foregroundStyle(MuTianTheme.ink)
                    .frame(width: 58, alignment: .trailing)
                Text(share.formatted(.percent.precision(.fractionLength(1))))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(
                isHovering ? MuTianTheme.ink.opacity(0.04) : .clear,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -8)
        .onHover { isHovering = $0 }
        .help("查看\(section.name)的书目")
    }
}

private struct CountRow<Leading: View>: View {
    let title: String
    let count: Int
    var action: (() -> Void)?
    @ViewBuilder var leading: Leading
    @State private var isHovering = false

    var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help("查看“\(title)”的书目")
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            leading
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(MuTianTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(count.formatted())
                .font(.song(14))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? AnyShapeStyle(MuTianTheme.ink) : AnyShapeStyle(.tertiary))
        }
        .padding(.vertical, 8)
        .background(isHovering ? MuTianTheme.ink.opacity(0.04) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MuTianTheme.hairline)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}
