import Foundation

struct MetadataCandidate {
    var title: String?
    var author: String?
    var dynasty: String?
    var edition: String?
    var classificationID: String?
    var sourceName: String?
    var sourceURL: String?
}

enum MetadataParser {
    static func parseMetadata(for itemURL: URL, root: URL) -> MetadataCandidate {
        let metadataDirectory = FileTypeDetector.isSupportedBookFile(itemURL)
            ? itemURL.deletingLastPathComponent()
            : itemURL
        var metadata = parseMetadata(in: metadataDirectory)
        let inferred = inferMetadata(for: itemURL, root: root)
        fillMissing(&metadata, with: inferred)
        return metadata
    }

    static func parseMetadata(in directory: URL) -> MetadataCandidate {
        let candidates = ["metadata.json", "manifest.json", "info.json"]
        for fileName in candidates {
            let url = directory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let title = firstString(object, keys: ["title", "label", "name", "dc:title"])
            let author = firstString(object, keys: ["author", "creator", "dc:creator"])
            let source = firstString(object, keys: ["attribution", "provider", "source", "repository"])
            let sourceURL = firstString(object, keys: ["@id", "id", "url", "homepage"])
            return MetadataCandidate(title: title, author: author, dynasty: nil, edition: nil, classificationID: nil, sourceName: source, sourceURL: sourceURL)
        }
        return MetadataCandidate(title: nil, author: nil, dynasty: nil, edition: nil, classificationID: nil, sourceName: nil, sourceURL: nil)
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let value = object[key] as? [String: Any] {
                if let nested = value["@value"] as? String {
                    return nested
                }
                if let nested = value["value"] as? String {
                    return nested
                }
            }
            if let value = object[key] as? [[String: Any]],
               let first = value.first {
                if let nested = first["@value"] as? String {
                    return nested
                }
                if let nested = first["value"] as? String {
                    return nested
                }
                if let nested = first["label"] as? String {
                    return nested
                }
            }
        }
        return nil
    }

    private static func inferMetadata(for itemURL: URL, root: URL) -> MetadataCandidate {
        let baseName = itemURL.deletingPathExtension().lastPathComponent
        return MetadataCandidate(
            title: nil,
            author: inferAuthor(from: baseName),
            dynasty: inferDynasty(from: baseName),
            edition: inferEdition(from: baseName),
            classificationID: inferClassificationID(for: itemURL, root: root),
            sourceName: nil,
            sourceURL: nil
        )
    }

    private static func fillMissing(_ metadata: inout MetadataCandidate, with fallback: MetadataCandidate) {
        if isBlank(metadata.author) { metadata.author = fallback.author }
        if isBlank(metadata.dynasty) { metadata.dynasty = fallback.dynasty }
        if isBlank(metadata.edition) { metadata.edition = fallback.edition }
        if isBlank(metadata.classificationID) { metadata.classificationID = fallback.classificationID }
        if isBlank(metadata.sourceName) { metadata.sourceName = fallback.sourceName }
        if isBlank(metadata.sourceURL) { metadata.sourceURL = fallback.sourceURL }
    }

    private static func inferClassificationID(for itemURL: URL, root: URL) -> String? {
        let rootDirectory = FileTypeDetector.isSupportedBookFile(root)
            ? root.deletingLastPathComponent()
            : root
        let targetDirectory = FileTypeDetector.isSupportedBookFile(itemURL)
            ? itemURL.deletingLastPathComponent()
            : itemURL
        let rootComponents = rootDirectory.standardizedFileURL.pathComponents
        let targetComponents = targetDirectory.standardizedFileURL.pathComponents
        let relativeComponents = targetComponents.dropFirst(min(rootComponents.count, targetComponents.count))

        var match: String?
        for component in relativeComponents {
            let normalized = normalizeClassificationComponent(component)
            if let id = classificationIDByName[normalized] {
                match = id
            }
        }
        return match
    }

    private static func normalizeClassificationComponent(_ component: String) -> String {
        var value = component.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"^\d+\s*[\.\-、_]?\s*"#,
            with: "",
            options: .regularExpression
        )
        if value.hasSuffix("类") {
            value.removeLast()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let classificationIDByName: [String: String] = [
        "经": "jing", "经部": "jing",
        "易": "jing.0", "周易": "jing.0",
        "书": "jing.1", "尚书": "jing.1",
        "诗": "jing.2", "诗经": "jing.2",
        "礼": "jing.3", "春秋": "jing.4", "孝经": "jing.5",
        "五经总义": "jing.6",
        "四书": "jing.7", "论语": "jing.7", "孟子": "jing.7", "大学": "jing.7", "中庸": "jing.7",
        "乐": "jing.8",
        "小学": "jing.9", "音韵": "jing.9",
        "史": "shi", "史部": "shi",
        "正史": "shi.0", "编年": "shi.1", "纪事本末": "shi.2", "别史": "shi.3", "杂史": "shi.4",
        "诏令奏议": "shi.5", "传记": "shi.6", "史钞": "shi.7", "载记": "shi.8", "时令": "shi.9",
        "地理": "shi.10", "职官": "shi.11", "政书": "shi.12", "目录": "shi.13", "史评": "shi.14",
        "子": "zi", "子部": "zi",
        "儒家": "zi.0", "兵家": "zi.1", "法家": "zi.2", "农家": "zi.3", "医家": "zi.4",
        "天文算法": "zi.5", "术数": "zi.6", "艺术": "zi.7", "谱录": "zi.8", "杂家": "zi.9",
        "类书": "zi.10", "小说家": "zi.11", "释家": "zi.12", "佛家": "zi.12", "道家": "zi.13",
        "集": "ji", "集部": "ji",
        "楚辞": "ji.0", "别集": "ji.1", "总集": "ji.2", "诗文评": "ji.3", "词曲": "ji.4",
        "其他": "other", "丛书": "other.0", "方志": "other.1", "谱牒": "other.2", "敦煌吐鲁番文献": "other.3"
    ]

    private static func inferDynasty(from name: String) -> String? {
        firstRegexMatch(in: name, pattern: #"[［\[\(（](先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)[］\]\)）]"#)
            ?? firstRegexMatch(in: name, pattern: #"(^|[\-·_\s])(先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)(?=[^代]|$)"#, captureIndex: 2)
    }

    private static func inferAuthor(from name: String) -> String? {
        if let author = firstRegexMatch(
            in: name,
            pattern: #"[［\[\(（](?:先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)[］\]\)）]\s*[_\-·\s]*([^：:·_\-\s，,（）\(\)]+)"#
        ) {
            return cleanAuthor(author)
        }

        if let author = firstRegexMatch(
            in: name,
            pattern: #"[\-·_\s](?:先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)[·\s]*([^：:·_\-\s，,（）\(\)]+?)(?:撰|著|辑|编|校|注|译)"#
        ) {
            return cleanAuthor(author)
        }

        if let author = firstRegexMatch(
            in: name,
            pattern: #"[\-·_]\s*(?:先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)[·\s]+([^：:·_\-\s，,（）\(\)]+)"#
        ) {
            return cleanAuthor(author)
        }

        if let author = firstRegexMatch(
            in: name,
            pattern: #"[\-·_]\s*([^：:·_\-\s，,（）\(\)]+?)(?:撰|著|辑|编|校|注|译)"#
        ) {
            return cleanAuthor(author)
        }

        let parts = name.split(whereSeparator: { "-_·".contains($0) }).map { String($0) }
        if parts.count >= 2 {
            let candidate = cleanAuthor(parts[1])
            if isLikelyPersonName(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func inferEdition(from name: String) -> String? {
        let parts = name.split(whereSeparator: { "-_·".contains($0) }).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts.first { part in
            part.contains("出版社")
                || part.contains("书局")
                || part.contains("古籍")
                || part.range(of: #"(18|19|20)\d{2}"#, options: .regularExpression) != nil
        }
    }

    private static func cleanAuthor(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(
            of: #"^(先秦|秦|汉|魏|晋|南北朝|隋|唐|五代|宋|辽|金|元|明|清|民国)[·\s]*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(撰|著|辑|编|校|注|译|点校|校注|主编)$"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyPersonName(_ value: String) -> Bool {
        guard (2...6).contains(value.count) else { return false }
        let blocked = ["中华书局", "上海古籍", "出版社", "书店", "三全本", "标点本", "扫描版", "Z-Library"]
        guard !blocked.contains(where: { value.contains($0) }) else { return false }
        return value.range(of: #"^[\p{Han}、]+$"#, options: .regularExpression) != nil
    }

    private static func firstRegexMatch(in text: String, pattern: String, captureIndex: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > captureIndex,
              let capture = Range(match.range(at: captureIndex), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
