import AppKit
import SwiftUI

// MARK: - 色与字

/// 木天的设计语言：宣纸为底，墨色为字，朱砂只用于点睛；
/// 四部沿用《四库全书》书衣配色（经绿、史红、子蓝、集灰）。
enum MuTianTheme {
    /// 朱砂：全局唯一的强调色，与应用图标一致。
    static let cinnabar = Color.dynamic(light: 0xB3312A, dark: 0xDC6152)
    static let accent = cinnabar
    /// 淡墨：按钮、分段控件等普通控件的着色，把朱砂留给印记和选中态。
    static let controlInk = Color.dynamic(light: 0x554E47, dark: 0x8F8578)

    static let jade = Color.dynamic(light: 0x4D7A5B, dark: 0x78A888)
    static let vermilion = Color.dynamic(light: 0xA8412F, dark: 0xD07560)
    static let indigo = Color.dynamic(light: 0x34598A, dark: 0x7399CC)
    static let ash = Color.dynamic(light: 0x7A756C, dark: 0xA39D92)
    static let ochre = Color.dynamic(light: 0x96693A, dark: 0xC49A68)

    /// 墨：标题与正文。
    static let ink = Color.dynamic(light: 0x2A2522, dark: 0xECE5D8)
    /// 笺：卡片、输入框和阅读区的纸面。
    static let paper = Color.dynamic(light: 0xFCFAF4, dark: 0x262320)
    /// 宣纸：窗口底色。
    static let detailBackground = Color.dynamic(light: 0xF5F1E7, dark: 0x1B1917)
    /// 侧栏：比宣纸略深一层。
    static let sidebarBackground = Color.dynamic(light: 0xECE6D9, dark: 0x151412)
    static let hairline = Color.dynamic(light: 0x2A2522, dark: 0xECE5D8).opacity(0.11)
    static let rule = Color.dynamic(light: 0x2A2522, dark: 0xECE5D8).opacity(0.26)

    /// 印文与题签的纸白，深浅模式下都不变。
    static let sealPaper = Color(hex: 0xFBF5E8)
    /// 印泥：印章用固定的朱砂色，不随深浅模式变化。
    static let sealRed = Color(hex: 0xB3312A)

    static func statusColor(_ status: BookStatus) -> Color {
        switch status {
        case .pending: return ash
        case .organized: return jade
        case .needsProofreading: return cinnabar
        case .proofreading: return indigo
        case .proofread: return ochre
        }
    }

    static func downloadColor(_ status: DownloadStatus) -> Color {
        switch status {
        case .waiting: return ash
        case .running: return indigo
        case .completed, .imported: return jade
        case .failed, .cancelled, .interrupted: return cinnabar
        }
    }

    static func fileTypeIcon(_ type: BookFileType) -> String {
        switch type {
        case .pdf: "doc.richtext"
        case .imageSequence: "photo.on.rectangle"
        case .text: "text.page"
        case .ebook: "book"
        case .document: "doc"
        case .archive: "archivebox"
        case .mixedFolder: "folder"
        }
    }

    // MARK: 四部

    /// 分类 ID 形如 `shi.10`，点号之前即所属的部。
    static func topClassificationID(of classificationID: String) -> String {
        classificationID.split(separator: ".").first.map(String.init) ?? classificationID
    }

    static func sectionColor(forClassificationID id: String) -> Color {
        switch topClassificationID(of: id) {
        case "jing": return jade
        case "shi": return vermilion
        case "zi": return indigo
        case "ji": return ash
        case "other": return ochre
        default: return ash.opacity(0.75)
        }
    }

    /// 四部小印的底色，深浅模式下保持一致。
    static func sealColor(forClassificationID id: String) -> Color {
        switch topClassificationID(of: id) {
        case "jing": return Color(hex: 0x4D7A5B)
        case "shi": return Color(hex: 0xA8412F)
        case "zi": return Color(hex: 0x34598A)
        case "ji": return Color(hex: 0x7A756C)
        case "other": return Color(hex: 0x96693A)
        default: return Color(hex: 0x948E84)
        }
    }

    /// 部首字：经、史、子、集；四部之外用“外”，未分类用“未”。
    static func sectionGlyph(forClassificationID id: String, name: String = "") -> String {
        switch topClassificationID(of: id) {
        case "jing": return "经"
        case "shi": return "史"
        case "zi": return "子"
        case "ji": return "集"
        case "other": return "外"
        case Classification.defaultUnclassifiedID: return "未"
        default: return name.first.map(String.init) ?? "类"
        }
    }

    /// 线装书衣的布色，深浅模式下保持一致，像一本真实的书。
    static func clothColor(forClassificationID id: String) -> Color {
        switch topClassificationID(of: id) {
        case "jing": return Color(hex: 0x4D7A5B)
        case "shi": return Color(hex: 0x9C3F30)
        case "zi": return Color(hex: 0x34598A)
        case "ji": return Color(hex: 0x756F66)
        case "other": return Color(hex: 0x8A6238)
        default: return Color(hex: 0x33475B) // 瓷青
        }
    }

    // MARK: 字体

    private static let hasKaiti = NSFont(name: "STKaitiSC-Regular", size: 12) != nil

    /// 楷体用于题签；系统未安装时退回宋体。
    static func brush(_ size: CGFloat) -> Font {
        hasKaiti ? .custom("STKaitiSC-Regular", fixedSize: size) : .song(size, weight: .medium)
    }
}

extension Font {
    /// 宋体（中文落在 Songti SC，西文与数字落在 New York）。
    static func song(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - 印

/// 一方小印：朱底白文。单字用于四部标记，双字竖排用于“木天”。
struct SealMark: View {
    let text: String
    var color: Color = MuTianTheme.sealRed
    var size: CGFloat = 18

    var body: some View {
        let characters = Array(text.prefix(2))
        let fontSize = characters.count == 1 ? size * 0.60 : size * 0.37

        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(color)
            .overlay {
                if size >= 26 {
                    RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                        .strokeBorder(MuTianTheme.sealPaper.opacity(0.6), lineWidth: max(size * 0.03, 0.75))
                        .padding(size * 0.085)
                }
            }
            .overlay {
                VStack(spacing: -size * 0.05) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.song(fontSize, weight: .bold))
                    }
                }
                .foregroundStyle(MuTianTheme.sealPaper)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - 栏线

/// 文武线：一粗一细，取自古籍版框。
struct WenWuRule: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(MuTianTheme.ink.opacity(0.78))
                .frame(height: 1.5)
            Rectangle()
                .fill(MuTianTheme.rule)
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// 页首：小字眉题、宋体大标题、文武线。
struct PageMasthead<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(3)
                        .foregroundStyle(MuTianTheme.cinnabar)
                    Text(title)
                        .font(.song(30, weight: .bold))
                        .foregroundStyle(MuTianTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 12)
                accessory
            }
            WenWuRule()
        }
    }
}

extension PageMasthead where Accessory == EmptyView {
    init(eyebrow: String, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 节标题：宋体标题，细线延伸到右侧。
struct SectionHeading<Leading: View, Trailing: View>: View {
    let title: String
    var note: String = ""
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            leading
            Text(title)
                .font(.song(16, weight: .semibold))
                .foregroundStyle(MuTianTheme.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Rectangle()
                .fill(MuTianTheme.hairline)
                .frame(height: 1)
            trailing
        }
    }
}

extension SectionHeading where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, note: String = "") {
        self.init(title: title, note: note) { EmptyView() } trailing: { EmptyView() }
    }
}

extension SectionHeading where Leading == EmptyView {
    init(title: String, note: String = "", @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, note: note, leading: { EmptyView() }, trailing: trailing)
    }
}

// MARK: - 面板与标记

struct MuTianPanelModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MuTianTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MuTianTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

extension View {
    func muTianPanel(padding: CGFloat = 18) -> some View {
        modifier(MuTianPanelModifier(padding: padding))
    }

    /// 内容滚到工具栏下方时渐隐到纸色，不与工具栏按钮叠在一起。
    func paperScrollEdge() -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                LinearGradient(
                    stops: [
                        .init(color: MuTianTheme.detailBackground, location: 0),
                        .init(color: MuTianTheme.detailBackground.opacity(0.94), location: 0.7),
                        .init(color: MuTianTheme.detailBackground.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.safeAreaInsets.top + 12)
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 页面已有大标题时，隐藏工具栏里重复的窗口标题（macOS 15 起可用）。
    @ViewBuilder
    func hidingToolbarTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

/// 让窗口本身也是宣纸色：内容滚到工具栏下方时，标题栏不会露出系统的白底。
struct PaperWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            view?.window?.backgroundColor = NSColor(MuTianTheme.detailBackground)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.backgroundColor = NSColor(MuTianTheme.detailBackground)
    }
}

/// 签条式状态标记。
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(color.opacity(0.32), lineWidth: 0.75)
            }
    }
}

struct DetailPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(MuTianTheme.ink.opacity(0.38))
                .padding(.bottom, 18)
            Text(title)
                .font(.song(18, weight: .semibold))
                .foregroundStyle(MuTianTheme.ink)
            Rectangle()
                .fill(MuTianTheme.cinnabar)
                .frame(width: 22, height: 1.5)
                .padding(.vertical, 12)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 340)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
    }
}
