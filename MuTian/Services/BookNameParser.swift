import Foundation

/// Bibliographic fields recognised from a file or folder name.
struct ParsedBookName: Equatable, Sendable {
    var title = ""
    var volume = ""
    var author = ""
    var dynasty = ""
    var publisher = ""
    var edition = ""
    var series = ""

    var hasBibliographicEvidence: Bool {
        !author.isEmpty || !publisher.isEmpty || !edition.isEmpty || !series.isEmpty || !volume.isEmpty
    }
}

/// Splits names such as `书名-作者-出版社2013`, `书名.清某某撰.中华书局.1980` or
/// `01001.点校本二十四史精装版.史记.一.卷一至卷七.纪[汉]司马迁撰.中华书局2013` into fields.
/// Everything here is heuristic: callers only fill blank fields or show a reviewable preview.
enum BookNameParser {
    // MARK: Public entry points

    /// Parses a book at `itemURL`, using containing folders (below `root`) for missing context:
    /// `全宋诗（72册）-北京大学古文献研究所编-北京大学出版社.1998/0022.pdf` becomes 全宋诗 · 第22册.
    static func parse(itemURL: URL, root: URL?) -> ParsedBookName {
        let isFile = FileTypeDetector.isSupportedBookFile(itemURL)
        let baseName = isFile ? itemURL.deletingPathExtension().lastPathComponent : itemURL.lastPathComponent
        var result = parse(name: baseName)
        let names = containingFolderNames(of: itemURL, root: root)
        let folders = names.enumerated().compactMap { index, name -> ParsedBookName? in
            guard !isClassificationFolder(name) else { return nil }
            let parsed = parse(name: name)
            // The library root (e.g. 木天测试、下载) is only context when its name looks like a book.
            if index == 0, root != nil, !parsed.hasBibliographicEvidence { return nil }
            return parsed.title.isEmpty ? nil : parsed
        }
        guard !folders.isEmpty else { return result }

        if result.title.isEmpty {
            let source = folders.last(where: \.hasBibliographicEvidence) ?? folders[folders.count - 1]
            result.title = source.title
        }

        for folder in folders.reversed() where sameWork(folder.title, result.title) {
            inheritMissing(into: &result, from: folder, includingAuthor: true)
        }

        if result.series.isEmpty,
           let collection = folders.first(where: { folder in
               !sameWork(folder.title, result.title)
                   && (folder.hasBibliographicEvidence || containsSeriesKeyword(folder.title))
           }) {
            result.series = collection.series.isEmpty ? collection.title : collection.series
            inheritMissing(into: &result, from: collection, includingAuthor: false)
        } else if !result.series.isEmpty,
                  let collection = folders.first(where: { sameWork($0.title, result.series) || sameWork($0.series, result.series) }) {
            inheritMissing(into: &result, from: collection, includingAuthor: false)
        }
        return result
    }

    /// Parses a single name component without folder context.
    static func parse(name rawName: String) -> ParsedBookName {
        var result = ParsedBookName()
        var text = cleanNoise(rawName)
        guard !text.isEmpty else { return result }

        if let number = match(text, #"^[\s\[\][0-9]]+$"#) {
            let digits = number.filter(\.isNumber)
            if let value = Int(String(digits.prefix(4))), !digits.isEmpty {
                result.volume = "第\(value)册"
            }
            return result
        }

        // 卷030.阮元瑜集 阮瑀 — a leading juan number is the position inside a larger collection.
        let juanPattern = #"^[卷巻]([0-9一二三四五六七八九十〇零百]+(?:-[0-9]+)?)[\.\s、_]+"#
        if let range = text.range(of: juanPattern, options: .regularExpression),
           let number = captures(text, juanPattern)?.first {
            result.volume = "卷" + number.split(separator: "-").map { part in
                chineseNumber(String(part)).map(String.init) ?? String(part)
            }.joined(separator: "-")
            text = String(text[range.upperBound...])
        }
        text = stripLeadingIndex(text)

        // 佛教十三经01：金刚经·心经 — series, position, then the work itself.
        if let groups = captures(text, #"^([^\s：:\-_·.]{2,12}?)\s*[0-9]{1,3}\s*[：:]\s*(.+)$"#), groups.count == 2,
           containsSeriesKeyword(groups[0]) {
            result.series = groups[0]
            text = groups[1]
        }

        var segments = tokenize(text)
        classify(&segments)
        assemble(segments, into: &result)
        finish(&result)
        return result
    }

    // MARK: Tokenizing

    private enum Kind: Equatable {
        case unknown, title, volume, author, dynasty, publisher, edition, series, drop
    }

    private struct Segment {
        var text: String
        var separator: String
        var isParenthetical = false
        var dynasty = ""
        var kind: Kind = .unknown
        var extra = ""      // edition text found after a publisher (中华书局2013 → 2013)
        var preset = false
    }

    private static let dynastyMarker: Character = "\u{1E}"

    private static func tokenize(_ input: String) -> [Segment] {
        var text = input
        // 〈李白全集〉 is a title mark too; keep everything inside 《》 together.
        text = text.replacingOccurrences(of: "〈", with: "《").replacingOccurrences(of: "〉", with: "》")
        text = protectTitleMarks(text)
        // Protect decimal points such as 2014.01 and full-stop separators inside numbers.
        text = text.replacingOccurrences(of: #"([0-9])\.([0-9])"#, with: "$1\u{1F}$2", options: .regularExpression)
        // [唐]、［宋］、（清）、(明) before a name become a dynasty prefix on the following segment.
        text = text.replacingOccurrences(
            of: #"[\[［〔【（(]\s*("# + dynastyPattern + #")\s*[\]］〕】）)]\s*[_\s]*"#,
            with: "|\(dynastyMarker)$1\(dynastyMarker)",
            options: .regularExpression
        )

        var segments: [Segment] = []
        var current = ""
        var separator = ""
        var depth = 0
        var bracketText = ""
        var bracketOpen: Character = "("

        // `separator` is the separator that preceded the segment being collected.
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            current = ""
            guard !trimmed.isEmpty else { return }
            segments.append(Segment(text: trimmed, separator: separator))
            separator = ""
        }

        let opens: [Character: Character] = ["(": ")", "（": "）", "[": "]", "［": "］", "【": "】", "〔": "〕"]
        let closes = Set(opens.values)
        for char in text {
            if depth > 0 {
                if opens[char] != nil { depth += 1 }
                if closes.contains(char) { depth -= 1 }
                guard depth == 0 else { bracketText.append(char); continue }
                let inner = bracketText.trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty {
                    var segment = Segment(text: inner, separator: separator, isParenthetical: true)
                    segment.extra = String(bracketOpen)
                    segments.append(segment)
                    separator = ""
                }
                bracketText = ""
                continue
            }
            if opens[char] != nil {
                flush()
                depth = 1
                bracketOpen = char
                continue
            }
            if char == "|" {
                flush()
                continue
            }
            if "-_·.，,+;；—–".contains(char) || char.isWhitespace {
                flush()
                if separator.isEmpty || separator == " " { separator = String(char) }
                continue
            }
            current.append(char)
        }
        if depth > 0 { current += String(bracketOpen) + bracketText }
        flush()

        return segments.map { segment in
            var segment = segment
            segment.text = restoreTitleMarks(segment.text.replacingOccurrences(of: "\u{1F}", with: "."))
            if segment.text.first == dynastyMarker,
               let end = segment.text.dropFirst().firstIndex(of: dynastyMarker) {
                segment.dynasty = String(segment.text[segment.text.index(after: segment.text.startIndex)..<end])
                segment.text = String(segment.text[segment.text.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            }
            return segment
        }
    }

    private static let protectedCharacters: [(Character, Character)] = [
        ("+", "\u{E001}"), ("-", "\u{E002}"), ("_", "\u{E003}"), ("·", "\u{E004}"), (".", "\u{E005}"),
        (" ", "\u{E006}"), ("（", "\u{E007}"), ("）", "\u{E008}"), ("(", "\u{E009}"), (")", "\u{E00A}"),
        ("，", "\u{E00B}"), (",", "\u{E00C}"), ("[", "\u{E00D}"), ("]", "\u{E00E}"), ("【", "\u{E00F}"), ("】", "\u{E010}")
    ]

    private static func protectTitleMarks(_ text: String) -> String {
        var output = ""
        var depth = 0
        for char in text {
            if char == "《" { depth += 1 }
            if char == "》" { depth = max(0, depth - 1) }
            if depth > 0, let replacement = protectedCharacters.first(where: { $0.0 == char })?.1 {
                output.append(replacement)
            } else {
                output.append(char)
            }
        }
        return output
    }

    private static func restoreTitleMarks(_ text: String) -> String {
        var output = text
        for (original, replacement) in protectedCharacters {
            output = output.replacingOccurrences(of: String(replacement), with: String(original))
        }
        return output
    }

    // MARK: Classification

    private static func classify(_ segments: inout [Segment]) {
        // 点校本《清史稿》、《全唐诗》十三 — an explicitly marked title, maybe followed by a volume.
        segments = segments.flatMap { segment -> [Segment] in
            guard !segment.isParenthetical,
                  let groups = captures(segment.text, #"^(\p{Han}{0,4}本)?《([^》]+)》(.*)$"#), groups.count == 3,
                  groups[2].isEmpty || isVolume(groups[2]) else { return [segment] }
            var title = segment
            title.text = groups[1]
            title.extra = groups[0]
            title.kind = .title
            title.preset = true
            guard !groups[2].isEmpty else { return [title] }
            var volume = Segment(text: groups[2], separator: " ")
            volume.kind = .volume
            volume.preset = true
            return [title, volume]
        }
        var pendingTitles: [(Int, Segment)] = []
        defer {
            for (index, title) in pendingTitles.reversed() { segments.insert(title, at: index + 1) }
        }
        // [中国寺庙宝典 01华北东北卷].张羽新主编 — a bracketed leading name is the title.
        if let first = segments.first, first.isParenthetical, ["[", "［"].contains(first.extra),
           !first.text.contains(dynastyMarker), classifyPlain(first.text, isFirst: true) == .unknown {
            segments[0].kind = .title
            segments[0].preset = true
            segments[0].extra = ""
        }
        let firstPlain = segments.first?.preset == true && segments.first?.kind == .title
            ? nil
            : segments.firstIndex { !$0.isParenthetical && $0.dynasty.isEmpty && !$0.text.isEmpty }
        for index in segments.indices {
            var segment = segments[index]
            defer { segments[index] = segment }
            if segment.preset { continue }
            let text = segment.text

            if text.isEmpty {
                segment.kind = segment.dynasty.isEmpty ? .drop : .dynasty
                if !segment.dynasty.isEmpty { segment.text = segment.dynasty }
                continue
            }
            if segment.isParenthetical {
                classifyParenthetical(&segment)
                continue
            }
            if !segment.dynasty.isEmpty {
                segment.kind = .author
                // [明]_谈迁：国榷 — author, then the title.
                if let groups = captures(text, #"^(\p{Han}{2,4})[：:](.+)$"#), groups.count == 2 {
                    segment.text = groups[0]
                    var title = Segment(text: groups[1], separator: "")
                    title.kind = .title
                    title.preset = true
                    pendingTitles.append((index, title))
                }
                continue
            }
            segment.kind = classifyPlain(text, isFirst: index == firstPlain)
            if segment.kind == .publisher { splitPublisher(&segment) }
            if segment.kind == .author, let glued = gluedDynastyName(text) {
                segment.dynasty = glued.dynasty
                segment.text = glued.name
            }
        }

        // A bare dynasty word belongs to the next name: 续资治通鉴-宋·李焘, 汉 司马迁.
        for index in segments.indices where segments[index].kind == .dynasty {
            let next = index + 1
            if next < segments.count, segments[next].kind == .author || isLikelyPersonName(segments[next].text) || roleSplit(segments[next].text) != nil {
                if segments[next].dynasty.isEmpty { segments[next].dynasty = segments[index].text }
                segments[next].kind = .author
                segments[index].kind = .drop
            }
        }
    }

    private static func classifyPlain(_ text: String, isFirst: Bool) -> Kind {
        if isJunk(text) { return .drop }
        if isFirst {
            // The leading piece is the title unless it is clearly something else.
            if isVolume(text), text.range(of: #"^(?:[0-9]{1,3}|[一二三四五六七八九十〇零百]+(?:之[一二三四五六七八九十〇零百]+)?)$"#, options: .regularExpression) != nil {
                return .volume
            }
            if containsSeriesKeyword(text), !isPublisher(text) { return .series }
            return .unknown
        }
        if isPublisher(text) { return .publisher }
        if isVolume(text) { return .volume }
        if containsSeriesKeyword(text), !text.hasSuffix("本"), !text.hasSuffix("藏") || text.contains("二十四史") { return .series }
        if isEdition(text) { return .edition }
        if !isFirst {
            if isDynastyWord(text) { return .dynasty }
            if roleSplit(text) != nil || isLikelyPersonName(text) || gluedDynastyName(text) != nil { return .author }
        }
        if containsSeriesKeyword(text) { return .series }
        if isFirst && isDynastyWord(text) { return .dynasty }
        return .unknown
    }

    private static func classifyParenthetical(_ segment: inout Segment) {
        // (（宋）范仲淹撰) — the inner dynasty bracket was already turned into a marker.
        if segment.text.contains(dynastyMarker) {
            let pieces = segment.text.replacingOccurrences(of: "|", with: "").split(separator: dynastyMarker, omittingEmptySubsequences: true).map(String.init)
            if pieces.count == 2, isDynastyWord(pieces[0]) {
                segment.dynasty = pieces[0]
                segment.text = pieces[1].trimmingCharacters(in: .whitespaces)
            } else {
                segment.text = pieces.joined()
            }
        }
        let text = segment.text
        let opener = segment.extra
        segment.extra = ""
        if isJunk(text) { segment.kind = .drop; return }
        if text.hasPrefix("《") || text.hasPrefix("缺") || text.hasPrefix("附") || text.contains("推荐") {
            segment.kind = opener == "【" && text.count > 12 ? .drop : .unknown
            if segment.kind == .unknown { segment.text = wrap(text, opener) }
            return
        }
        if isVolume(text) || match(text, #"^[上中下][、,，]?[上中下]?[册冊编卷]?$"#) != nil
            || match(text.replacingOccurrences(of: " ", with: ""), "^(?:套装|全套)?共?\(numeral)[册冊卷]$") != nil {
            segment.kind = .volume; return
        }
        if containsSeriesKeyword(text) && !isPublisher(text) { segment.kind = .series; return }
        if isPublisher(text) { segment.kind = .publisher; splitPublisher(&segment); return }
        if isEdition(text) { segment.kind = .edition; return }
        if opener == "【" && text.count > 12 { segment.kind = .drop; return }

        // (北宋.张君房辑)、(赖永海 主编, 陈林 译注)、(王建伟, 金晖, …)
        let parts = text.split(whereSeparator: { "，,;；/／".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var authors: [String] = []
        var dynasty = ""
        var recognised = 0
        for part in parts {
            var name = part
            if let groups = captures(name, "^(" + dynastyPattern + #")\s*[\.·\s]\s*(.+)$"#), groups.count == 2 {
                if dynasty.isEmpty { dynasty = groups[0] }
                name = groups[1]
            } else if let glued = gluedDynastyName(name) {
                if dynasty.isEmpty { dynasty = glued.dynasty }
                name = glued.name
            }
            name = name.replacingOccurrences(of: #"\s+(?=\p{Han})"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ".", with: "")
            if roleSplit(name) != nil || isLikelyPersonName(name) || name.hasSuffix("法师") || name.hasSuffix("上人") {
                recognised += 1
            }
            authors.append(name)
        }
        if recognised > 0 {
            segment.kind = .author
            segment.text = authors.joined(separator: "、")
            if segment.dynasty.isEmpty { segment.dynasty = dynasty }
            return
        }
        if opener == "【" {
            segment.kind = .series
            return
        }
        segment.kind = .unknown
        segment.text = wrap(text, opener)
    }

    private static func wrap(_ text: String, _ opener: String) -> String {
        switch opener {
        case "【": return "【\(text)】"
        case "[", "［": return "[\(text)]"
        case "(": return "(\(text))"
        default: return "（\(text)）"
        }
    }

    private static func splitPublisher(_ segment: inout Segment) {
        let text = segment.text
        let pattern = "^(.*?(?:" + publisherSuffixPattern + "))(.*)$"
        if let groups = captures(text, pattern), groups.count == 2 {
            segment.text = groups[0].trimmingCharacters(in: .whitespaces)
            segment.extra = groups[1].trimmingCharacters(in: CharacterSet(charactersIn: " ,，.（）()"))
        }
        // 安徽教育2002、上海古籍2006 — abbreviated publisher followed by a year.
        if let groups = captures(segment.text, #"^(\p{Han}{2,10}?)((?:18|19|20)[0-9]{2}.*)$"#), groups.count == 2 {
            segment.text = groups[0]
            segment.extra = (groups[1] + " " + segment.extra).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: Assembly

    private static func assemble(_ segments: [Segment], into result: inout ParsedBookName) {
        var segments = segments
        // The first unknown piece is the title; a leading series keyword only wins when a title follows.
        if segments.contains(where: { $0.kind == .title }) {
            // 《》 already marked it.
        } else if let titleIndex = segments.firstIndex(where: { $0.kind == .unknown }) {
            segments[titleIndex].kind = .title
        } else if let seriesIndex = segments.firstIndex(where: { $0.kind == .series }),
                  !segments.contains(where: { $0.kind == .title }) {
            let laterSeries = segments.indices.contains { $0 > seriesIndex && segments[$0].kind == .series }
            if !laterSeries && result.series.isEmpty && seriesIndex == 0 && segments.count == 1 {
                segments[seriesIndex].kind = .title
            } else if !laterSeries && seriesIndex == segments.count - 1 && segments.count == 1 {
                segments[seriesIndex].kind = .title
            }
        }
        if !segments.contains(where: { $0.kind == .title }),
           let first = segments.firstIndex(where: { $0.kind == .author && $0.dynasty.isEmpty && roleSplit($0.text) == nil }),
           first == 0 {
            segments[first].kind = .title
        }

        var titleParts: [String] = []
        var volumeParts: [String] = []
        var authors: [(text: String, dynasty: String)] = []
        var publishers: [String] = []
        var editions: [String] = []
        var seriesParts: [String] = []
        var lastTextual: Kind = .title
        var titleClosed = false

        for segment in segments {
            switch segment.kind {
            case .drop, .dynasty:
                continue
            case .title:
                if !titleParts.isEmpty && titleClosed {
                    // A second marked title: keep the first, file the rest with the volume.
                    volumeParts.append(segment.text)
                } else {
                    titleParts.append(titleParts.isEmpty ? segment.text : segment.separator + segment.text)
                }
                if !segment.extra.isEmpty { editions.append(segment.extra) }
                lastTextual = .title
            case .unknown:
                if lastTextual == .volume, !volumeParts.isEmpty {
                    volumeParts.append(segment.text)
                } else if !titleClosed {
                    let glue = segment.separator.trimmingCharacters(in: .whitespaces).isEmpty
                        ? (segment.isParenthetical || segment.text.hasPrefix("（") || segment.text.hasPrefix("(") ? "" : " ")
                        : segment.separator
                    if titleParts.isEmpty { titleParts.append(segment.text) }
                    else { titleParts.append(glue + segment.text) }
                    lastTextual = .title
                    continue
                } else if lastTextual == .edition || !editions.isEmpty {
                    editions.append(segment.text)
                } else {
                    editions.append(segment.text)
                }
            case .volume:
                volumeParts.append(normalizeVolume(segment.text))
                lastTextual = .volume
                titleClosed = true
            case .author:
                authors.append((normalizeAuthor(segment.text), segment.dynasty))
                lastTextual = .author
                titleClosed = true
            case .publisher:
                publishers.append(segment.text)
                if !segment.extra.isEmpty { editions.append(segment.extra) }
                lastTextual = .edition
                titleClosed = true
            case .edition:
                if lastTextual == .edition, let last = editions.last,
                   last.range(of: #"[0-9]$"#, options: .regularExpression) != nil,
                   segment.text.range(of: #"^[0-9]{1,2}$"#, options: .regularExpression) != nil {
                    editions[editions.count - 1] = last + "." + segment.text
                } else {
                    editions.append(segment.text)
                }
                lastTextual = .edition
                titleClosed = true
            case .series:
                seriesParts.append(segment.text)
                titleClosed = !titleParts.isEmpty
            }
            if segment.kind != .unknown && segment.kind != .title && !titleParts.isEmpty { titleClosed = true }
        }

        result.title = titleParts.joined()
        if result.series.isEmpty { result.series = seriesParts.first ?? "" }
        if !volumeParts.isEmpty {
            var unique: [String] = []
            for part in [result.volume].filter({ !$0.isEmpty }) + volumeParts where !unique.contains(part) { unique.append(part) }
            result.volume = unique.joined(separator: " ")
        }
        result.publisher = publishers.first ?? ""
        result.edition = editions.joined(separator: " ")

        if let first = authors.first(where: { !$0.dynasty.isEmpty }) { result.dynasty = first.dynasty }
        var authorText = ""
        for (index, author) in authors.enumerated() {
            var name = author.text
            if index > 0, !author.dynasty.isEmpty, author.dynasty != result.dynasty {
                name = "（\(author.dynasty)）" + name
            }
            if authorText.isEmpty {
                authorText = name
            } else {
                let previous = authors[index - 1].text
                authorText += roleSplit(previous) == nil ? "、" + name : "；" + name
            }
        }
        result.author = authorText
    }

    private static func finish(_ result: inout ParsedBookName) {
        var title = result.title.trimmingCharacters(in: CharacterSet(charactersIn: " .·-_，,+"))
        // 点校本《清史稿》 → title 清史稿, edition 点校本.
        if let groups = captures(title, #"^(点校本|标点本|整理本|校注本|影印本)?《([^》]+)》$"#), groups.count == 2 {
            if !groups[0].isEmpty { result.edition = joinNonEmpty(groups[0], result.edition) }
            title = groups[1]
        } else if let groups = captures(title, #"^《([^》]+)》\s*(.*)$"#), groups.count == 2,
                  !groups[1].isEmpty, isVolume(groups[1]) || isVolumeTail(groups[1]) {
            title = groups[0]
            result.volume = joinNonEmpty(normalizeVolume(groups[1]), result.volume)
        }
        // 清史编年+第七卷（嘉庆朝）、清人文集地理类汇编6、群书治要集解 第七册
        if let groups = captures(title, #"^(.*?\p{Han})\s*[+＋]?\s*(第[0-9一二三四五六七八九十〇零百两]+[册冊卷辑集编部分].*)$"#), groups.count == 2 {
            title = groups[0]
            result.volume = joinNonEmpty(normalizeVolume(groups[1]), result.volume)
        } else if let groups = captures(title, #"^(.*\p{Han}{2})\s*[+＋\-]?\s*([0-9]{1,3})$"#), groups.count == 2,
                  !title.hasPrefix("《") {
            title = groups[0]
            result.volume = joinNonEmpty("第\(Int(groups[1]) ?? 0)册", result.volume)
        } else if let groups = captures(title, #"^(.*\p{Han}{2})\s*([ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫ])$"#), groups.count == 2 {
            let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ"]
            title = groups[0]
            result.volume = joinNonEmpty("第\((roman.firstIndex(of: groups[1]) ?? 0) + 1)册", result.volume)
        } else if let groups = captures(title, #"^(.*\p{Han}{2})((?:[0-9]{1,3}|[一二三四五六七八九十百两]+)[卷册冊])$"#), groups.count == 2,
                  result.volume.isEmpty {
            title = groups[0]
            result.volume = groups[1].replacingOccurrences(of: "冊", with: "册")
        }
        result.volume = result.volume.replacingOccurrences(of: "+", with: "")
        title = title.replacingOccurrences(of: #"^《([^》]+)》$"#, with: "$1", options: .regularExpression)
        result.title = title.trimmingCharacters(in: CharacterSet(charactersIn: " .·-_，,+"))
        if isDynastyWord(result.title) { result.title = "" }
        // 二十五史（全集） — a name that is only a series word is the title itself.
        if result.title.isEmpty, !result.series.isEmpty, result.volume.isEmpty || result.author.isEmpty {
            result.title = result.series
            result.series = ""
        }
        result.edition = result.edition.trimmingCharacters(in: CharacterSet(charactersIn: " .·-_，,"))
        result.publisher = result.publisher.trimmingCharacters(in: CharacterSet(charactersIn: " .·-_，,"))
        if result.series == result.title { result.series = "" }
    }

    // MARK: Folder context

    private static func containingFolderNames(of itemURL: URL, root: URL?) -> [String] {
        let parent = itemURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard let root else { return Array(parent.suffix(1)) }
        let rootDirectory = FileTypeDetector.isSupportedBookFile(root) ? root.deletingLastPathComponent() : root
        let rootComponents = rootDirectory.standardizedFileURL.pathComponents
        guard parent.count >= rootComponents.count, Array(parent.prefix(rootComponents.count)) == rootComponents else {
            return Array(parent.suffix(1))
        }
        // Include the root folder itself: importing `全元文（60册）-凤凰出版社` directly still gives context.
        return Array(parent.dropFirst(max(0, rootComponents.count - 1)))
    }

    /// Topic folders (四部类目、诸子学派) carry no bibliographic information of their own.
    static func isClassificationFolder(_ name: String) -> Bool {
        if MetadataParser.classificationID(forFolderName: name) != nil { return true }
        let bare = name.replacingOccurrences(of: #"^[0-9]+\s*[\.\-、_]?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[（(][^）)]*[）)]$"#, with: "", options: .regularExpression)
        return ["墨家", "名家", "纵横家", "阴阳家", "下载", "另一版", "其他", "未分类"].contains(bare)
    }

    private static func sameWork(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizedTitle(lhs), b = normalizedTitle(rhs)
        guard a.count >= 2, b.count >= 2 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"^(点校本|标点本|整理本)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[《》\s·\.\-_（）\(\)]"#, with: "", options: .regularExpression)
    }

    private static func inheritMissing(into result: inout ParsedBookName, from folder: ParsedBookName, includingAuthor: Bool) {
        if includingAuthor && result.author.isEmpty {
            result.author = folder.author
            if result.dynasty.isEmpty { result.dynasty = folder.dynasty }
        }
        if result.publisher.isEmpty { result.publisher = folder.publisher }
        if result.edition.isEmpty { result.edition = folder.edition }
        if includingAuthor && result.series.isEmpty { result.series = folder.series }
    }

    // MARK: Vocabulary

    static let dynastyNames = [
        "先秦", "春秋", "战国", "秦", "西汉", "东汉", "汉", "三国魏", "三国蜀", "三国吴", "三国", "曹魏", "蜀汉",
        "西晋", "东晋", "晋", "南朝宋", "南朝齐", "南朝梁", "南朝陈", "刘宋", "南齐", "萧梁", "南北朝", "北魏",
        "东魏", "西魏", "北齐", "北周", "隋", "唐", "五代", "后梁", "后唐", "后晋", "后汉", "后周", "南唐", "前蜀",
        "后蜀", "吴越", "北宋", "南宋", "宋", "辽", "西夏", "金", "元", "明", "南明", "清", "民国",
        "梁", "陈", "齐", "魏", "周", "吴", "蜀"
    ]
    static let dynastyPattern = dynastyNames.joined(separator: "|")

    /// Single-character dynasties that are also common surnames need a longer name after them.
    private static let surnameDynasties: Set<String> = ["陈", "金", "梁", "魏", "周", "齐", "吴", "蜀", "秦", "宋"]

    private static func isDynastyWord(_ text: String) -> Bool {
        dynastyNames.contains(text.trimmingCharacters(in: .whitespaces))
    }

    /// 清王先谦、唐李延寿、南朝宋范晔、宋·李焘 → (dynasty, name).
    private static func gluedDynastyName(_ text: String) -> (dynasty: String, name: String)? {
        for dynasty in dynastyNames.sorted(by: { $0.count > $1.count }) where text.hasPrefix(dynasty) {
            var name = String(text.dropFirst(dynasty.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ·.．"))
            let bareName = (roleSplit(name)?.name ?? name).replacingOccurrences(of: "等", with: "")
            let minimum = surnameDynasties.contains(dynasty) ? 3 : 2
            guard bareName.count >= minimum, bareName.count <= 5,
                  bareName.range(of: #"^\p{Han}+$"#, options: .regularExpression) != nil,
                  !endsWithTitleWord(bareName) else { continue }
            name = name.trimmingCharacters(in: .whitespaces)
            return (dynasty, name)
        }
        return nil
    }

    private static let roles = [
        "编著", "编纂", "编撰", "撰绘", "主编", "整理", "校理", "校释", "校注", "校点", "点校", "标点", "校勘", "校补", "校正",
        "副主编", "疏注", "校笺", "笺注", "笺校", "疏证", "通释", "译注", "今注", "集解", "集释", "集注", "义疏", "辑释", "辑校", "注释",
        "注译", "讲述", "开示", "编译", "选编", "选注", "评注", "撰", "著", "着", "辑", "编", "注", "译", "校", "笺",
        "疏", "传", "补", "述", "讲", "绘", "评", "选"
    ]

    /// 王引之撰 → ("王引之", "撰").
    private static func roleSplit(_ text: String) -> (name: String, role: String)? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        for role in roles where compact.hasSuffix(role) {
            var name = String(compact.dropLast(role.count))
            if name.hasSuffix("等") { name.removeLast() }
            guard (1...16).contains(name.count),
                  name.range(of: #"^[\p{Han}、，,&＆·]+$"#, options: .regularExpression) != nil else { continue }
            let firstName = name.split(whereSeparator: { "、，,&＆".contains($0) }).first.map(String.init) ?? name
            guard firstName.count >= 2 || name.count >= 2 else { continue }
            guard !endsWithTitleWord(firstName) || firstName.hasSuffix("所") || firstName.hasSuffix("会") || firstName.hasSuffix("馆") else { continue }
            if role.count == 1, firstName.count > 5, !firstName.contains("所"), !firstName.contains("会") { continue }
            return (name, role)
        }
        return nil
    }

    private static let titleEndings: Set<Character> = [
        "志", "史", "书", "經", "经", "集", "录", "记", "论", "考", "疏", "典", "图", "表", "要", "鉴", "略", "稿",
        "篇", "卷", "册", "诗", "词", "赋", "韵", "义", "解", "释", "说", "案", "本", "版", "序", "目", "颂", "讲",
        "钞", "编", "注", "纂", "谱", "言", "语", "策", "训", "辞", "话", "评", "选", "抄", "汇", "刊", "律", "令",
        "法", "方", "学", "子", "藏", "全", "库", "苑", "简", "笺", "证", "读", "例", "辨", "补", "议", "录",
        "宝", "经", "曲", "府", "县", "州", "国", "史", "鉴", "目", "义", "疏", "源", "流", "门", "品", "偈", "咒", "家", "纪", "例", "汇", "编", "朝", "集"
    ]

    private static func endsWithTitleWord(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return titleEndings.contains(last)
    }

    private static func isLikelyPersonName(_ raw: String) -> Bool {
        var text = raw.replacingOccurrences(of: " ", with: "")
        if text.hasSuffix("等") { text.removeLast() }
        if text.hasSuffix("法师") || text.hasSuffix("上人") || text.hasSuffix("大师") || text.hasSuffix("居士") {
            return (3...8).contains(text.count)
        }
        let names = text.split(whereSeparator: { "、&＆".contains($0) }).map(String.init)
        guard !names.isEmpty else { return false }
        return names.allSatisfy { name in
            (2...4).contains(name.count)
                && name.range(of: #"^[\p{Han}]+$"#, options: .regularExpression) != nil
                && !endsWithTitleWord(name)
                && !isPublisher(name)
                && !containsSeriesKeyword(name)
                && !name.contains("本")
                && !isDynastyWord(name)
                && match(name, #"^[一二三四五六七八九十〇零百上中下之]+$"#) == nil
                && match(name, #"[一二三四五六七八九十〇上中下0-9]$"#) == nil
                && match(name, #"^[纪传志表书考世家载记序跋]+$"#) == nil
        }
    }

    private static let publisherSuffixPattern =
        "出版社|出版集团|出版公司|書局|书局|書店|书店|書社|书社|印书馆|印書館|出品|出版|图书馆|圖書館|文物社"
    private static let publisherAbbreviations = [
        "上海古籍", "安徽教育", "四川大学", "中华书局", "商务印书馆", "人民文学", "凤凰", "岳麓", "巴蜀", "齐鲁", "广陵", "中西书局"
    ]

    private static func isPublisher(_ text: String) -> Bool {
        if text.range(of: publisherSuffixPattern, options: .regularExpression) != nil {
            return !text.hasPrefix("《") && text.count <= 30
        }
        return publisherAbbreviations.contains { abbreviation in
            text.hasPrefix(abbreviation)
                && text.dropFirst(abbreviation.count).range(of: #"^(?:出版|[0-9]{4}.*)?$"#, options: .regularExpression) != nil
        }
    }

    private static let seriesKeywords = [
        "丛书", "叢書", "丛刊", "叢刊", "丛编", "集成", "文库", "藏书", "选刊", "二十四史", "二十五史",
        "十三经", "名著", "大系", "备要", "汇刊"
    ]

    static func containsSeriesKeyword(_ text: String) -> Bool {
        seriesKeywords.contains { text.contains($0) }
    }

    private static let numeral = "(?:[0-9]{1,3}|[一二三四五六七八九十〇零百千两]+)"

    private static func isVolume(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        let patterns = [
            "^第?\(numeral)[册冊卷辑集编部分本]?[上中下]?$",
            "^[卷巻]第?\(numeral)[上中下]?(?:[至\\-~～]卷?\(numeral)[上中下]?)?$",
            "^\(numeral)[卷巻](?:[至\\-~～]\(numeral)[卷巻]?)?$",
            "^\(numeral)[\\-~～至]\(numeral)[卷巻册冊]$",
            "^[上中下][册冊编卷]?$",
            "^[上中下][、,，][上中下][册冊]?$",
            "^全\(numeral)[册冊卷]$",
            "^\(numeral)[册冊]$",
            "^总\(numeral)卷$",
            "^\(numeral)之\(numeral)$",
            "^[一二三四五六七八九十〇零百]+$",
            "^[0-9]{1,3}$"
        ]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    private static func isVolumeTail(_ text: String) -> Bool {
        text.range(of: "^\(numeral)$", options: .regularExpression) != nil
    }

    private static let editionWords = [
        "刻本", "刊本", "重刊", "覆刊", "翻刻", "影刻", "影印", "抄本", "钞本", "写本", "藏本", "点校本", "标点本",
        "整理本", "简体字本", "繁体", "精装", "平装", "修订本", "增订本", "增补本", "三全本", "单疏本", "初版", "再版",
        "影宋", "刊", "刻", "版", "印本", "扫描", "排印", "铅印", "石印", "稿本", "善本", "注疏本", "白文本", "全本", "选本"
    ]

    private static func isEdition(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        if t.range(of: #"^(?:18|19|20)[0-9]{2}(?:年.*|\D.*)?$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^[0-9]{1,4}年"#, options: .regularExpression) != nil { return true }
        if t.hasSuffix("藏") || t.hasSuffix("藏本") || t.hasSuffix("本") && !t.hasSuffix("本末") && t.count <= 30 && t.count >= 2 {
            return true
        }
        return editionWords.contains { t.contains($0) } && t.count <= 30
    }

    private static func isJunk(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        let junk = ["Z-Library", "z-library", "扫描版", "图像PDG", "PDG", "高清", "PDF", "pdf", "全集", "合集", "完整版", "电子版"]
        if junk.contains(t) { return true }
        if t.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, t.count >= 5 { return true }
        if t.range(of: #"^[A-Za-z]$"#, options: .regularExpression) != nil { return true }
        return false
    }

    // MARK: Cleaning

    private static func cleanNoise(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let removals = [
            #"\s*[\(（]\s*Z-Library\s*[\)）]"#,
            #"\s*[\(（][0-9]{1,2}[\)）]\s*$"#,
            #"_?\s*图像PDG"#,
            #"_页面_[0-9]+_图像_[0-9]+$"#,
            #"\[[0-9]{3,}\]"#,
            #"_[0-9]{6,}$"#,
            #"【[^】]{13,}】?"#,
            #"\s*扫描版"#
        ]
        for pattern in removals {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // 《清史编年+第七卷（嘉庆朝）》 (《清史编年+第七卷（嘉庆朝）》) — a repeated title in brackets.
        if let groups = captures(text, #"^(.*?)\s*[\(（](《[^》]+》)[\)）]\s*$"#), groups.count == 2, groups[0].contains(groups[1]) {
            text = groups[0]
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes sort prefixes such as `01`, `16106.`, `0301【…】` but keeps years like `1925中华民国地图集`.
    private static func stripLeadingIndex(_ text: String) -> String {
        guard let prefix = match(text, #"^[0-9]{1,5}"#) else { return text }
        let rest = text.dropFirst(prefix.count)
        if prefix.count == 4, prefix.hasPrefix("1") || prefix.hasPrefix("20"), rest.first.map({ !"《【.、_-— ".contains($0) }) ?? false {
            return text
        }
        let trimmed = rest.drop { ".、_-— ．".contains($0) }
        return trimmed.isEmpty ? text : String(trimmed)
    }

    private static func normalizeVolume(_ text: String) -> String {
        var t = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "冊", with: "册")
            .replacingOccurrences(of: "巻", with: "卷")
        if let groups = captures(t, #"^第([0-9一二三四五六七八九十〇零百两]+)([册卷辑集编部分])$"#), groups.count == 2,
           let value = chineseNumber(groups[0]) {
            t = "第\(value)\(groups[1])"
        } else if let digits = match(t, #"^0*[0-9]{1,3}$"#), let value = Int(digits) {
            t = "第\(value)册"
        } else if let value = chineseNumber(t) {
            t = "第\(value)册"
        }
        return t
    }

    /// 0022 → 22, 一〇 → 10, 二十一 → 21, 两 → 2.
    static func chineseNumber(_ text: String) -> Int? {
        if text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil { return Int(text) }
        let digits: [Character: Int] = ["〇": 0, "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        guard !text.isEmpty, text.allSatisfy({ digits[$0] != nil || $0 == "十" || $0 == "百" }) else { return nil }
        if !text.contains("十") && !text.contains("百") {
            return text.reduce(0) { $0 * 10 + digits[$1]! }
        }
        var total = 0, current = 0
        for char in text {
            if let digit = digits[char] { current = digit }
            else if char == "十" { total += (current == 0 ? 1 : current) * 10; current = 0 }
            else if char == "百" { total += (current == 0 ? 1 : current) * 100; current = 0 }
        }
        return total + current
    }

    private static func normalizeAuthor(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " .·_-，,"))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\p{Han}) (?=(?:主编|译注|撰|著|编|注|校点|点校))"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "着", with: "著")
    }

    private static func joinNonEmpty(_ lhs: String, _ rhs: String) -> String {
        [lhs, rhs].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Regex helpers

    private static func match(_ text: String, _ pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<result.numberOfRanges).map { index in
            Range(result.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
