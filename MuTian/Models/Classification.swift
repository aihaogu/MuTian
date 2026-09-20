import Foundation

struct Classification: Identifiable, Codable, Hashable {
    static let defaultUnclassifiedID = "uncategorized"

    var id: String
    var parentID: String?
    var name: String
    var sortOrder: Int
    var isSystem: Bool

    var displayPath: String {
        name
    }
}

enum ClassificationSeed {
    static let all: [Classification] = {
        var rows: [Classification] = []
        func add(_ id: String, _ parent: String?, _ name: String, _ sort: Int) {
            rows.append(Classification(id: id, parentID: parent, name: name, sortOrder: sort, isSystem: true))
        }

        add("jing", nil, "经部", 0)
        ["易", "书", "诗", "礼", "春秋", "孝经", "五经总义", "四书", "乐", "小学"].enumerated().forEach {
            add("jing.\($0.offset)", "jing", $0.element, $0.offset)
        }

        add("shi", nil, "史部", 1)
        ["正史", "编年", "纪事本末", "别史", "杂史", "诏令奏议", "传记", "史钞", "载记", "时令", "地理", "职官", "政书", "目录", "史评"].enumerated().forEach {
            add("shi.\($0.offset)", "shi", $0.element, $0.offset)
        }

        add("zi", nil, "子部", 2)
        ["儒家", "兵家", "法家", "农家", "医家", "天文算法", "术数", "艺术", "谱录", "杂家", "类书", "小说家", "释家", "道家"].enumerated().forEach {
            add("zi.\($0.offset)", "zi", $0.element, $0.offset)
        }

        add("ji", nil, "集部", 3)
        ["楚辞", "别集", "总集", "诗文评", "词曲"].enumerated().forEach {
            add("ji.\($0.offset)", "ji", $0.element, $0.offset)
        }

        add("other", nil, "其他", 4)
        ["丛书", "方志", "谱牒", "敦煌吐鲁番文献"].enumerated().forEach {
            add("other.\($0.offset)", "other", $0.element, $0.offset)
        }

        add(Classification.defaultUnclassifiedID, nil, "未分类", 99)
        return rows
    }()
}
