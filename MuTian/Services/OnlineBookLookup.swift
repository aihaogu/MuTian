import Foundation

/// A catalogue record found online. Values are converted to simplified characters.
struct OnlineBookRecord: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var author: String
    var dynasty: String = ""
    var publisher: String
    var year: String
    var series: String
    var url: String

    func value(for field: BookField) -> String {
        switch field {
        case .title: return title
        case .author: return author
        case .publisher: return publisher
        case .edition: return year
        case .series: return series
        case .dynasty: return dynasty
        case .volume: return ""
        }
    }
}

enum OnlineBookLookupError: LocalizedError {
    case emptyQuery
    case badResponse(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .emptyQuery: return "书名为空，无法查询。"
        case .badResponse(let code): return "书目服务返回错误（\(code)），请稍后再试。"
        case .unreadable: return "无法解析书目服务的返回内容。"
        }
    }
}

/// Looks books up in CiNii Books (日本国立情报学研究所联合目录), which needs no key and
/// holds most mainland reprints of classical works, with publisher, year and series.
/// Only runs when the user asks, one request per lookup.
enum OnlineBookLookup {
    static let serviceName = "CiNii Books"
    static let endpoint = URL(string: "https://ci.nii.ac.jp/books/opensearch/search")!

    static func search(title: String, author: String = "", session: URLSession = .shared) async throws -> [OnlineBookRecord] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw OnlineBookLookupError.emptyQuery }

        var records = try await fetch(title: title, author: author, session: session)
        if records.isEmpty, !author.isEmpty {
            // Author spellings differ a lot (撰/注/等); retry on the title alone.
            records = try await fetch(title: title, author: "", session: session)
        }
        return records
    }

    private static func fetch(title: String, author: String, session: URLSession) async throws -> [OnlineBookRecord] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "count", value: "20")
        ]
        let authorName = searchableAuthor(author)
        if !authorName.isEmpty { items.append(URLQueryItem(name: "author", value: authorName)) }
        components.queryItems = items

        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("MuTian/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OnlineBookLookupError.badResponse(http.statusCode)
        }
        return try parse(data)
    }

    /// 王引之撰；李花蕾校点 → 王引之
    static func searchableAuthor(_ author: String) -> String {
        let first = author.split(whereSeparator: { "；;、，, ".contains($0) }).first.map(String.init) ?? ""
        return first
            .replacingOccurrences(of: #"^（[^）]*）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(等)?(编著|主编|校注|译注|点校|校点|撰|著|编|注|辑|译|校)$"#, with: "", options: .regularExpression)
    }

    static func parse(_ data: Data) throws -> [OnlineBookRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OnlineBookLookupError.unreadable
        }
        let graph = root["@graph"] as? [[String: Any]] ?? []
        let items = graph.first?["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            let title = simplified(string(item["title"]))
            guard !title.isEmpty else { return nil }
            let url = string(item["@id"])
            let series = (item["dcterms:isPartOf"] as? [[String: Any]])?
                .compactMap { string($0["dc:title"]).nilIfEmpty }
                .first ?? ""
            let (author, dynasty) = splitDynasty(simplified(string(item["dc:creator"])))
            return OnlineBookRecord(
                id: url.isEmpty ? UUID().uuidString : url,
                title: title.replacingOccurrences(of: "巻", with: "卷"),
                author: author,
                dynasty: dynasty,
                publisher: simplified(string(item["dc:publisher"])),
                year: string(item["prism:publicationDate"]).nilIfEmpty ?? string(item["dc:date"]),
                series: cleanSeries(simplified(series)),
                url: url
            )
        }
    }

    private static func string(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let list = value as? [Any] { return list.map { string($0) }.filter { !$0.isEmpty }.joined(separator: "；") }
        if let object = value as? [String: Any] { return string(object["@value"] ?? object["dc:title"]) }
        return ""
    }

    /// 爾雅今注 → 尔雅今注；南開大学出版社 → 南开大学出版社
    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    /// 啸园丛书 / [(清)葛元煦辑], 第6函 → 啸园丛书
    static func cleanSeries(_ series: String) -> String {
        let name = series.components(separatedBy: " / ").first ?? series
        return name.replacingOccurrences(of: #"\s*[;,，]\s*[第]?[0-9]+[函册卷辑]?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// (清)王引之着 → ("王引之著", "清"). The system transform turns 著 into 着, so undo that for authors.
    static func splitDynasty(_ author: String) -> (String, String) {
        var name = author.replacingOccurrences(of: "着", with: "著")
        var dynasty = ""
        let pattern = #"^\s*[\(（\[［〔]\s*([^\)）\]］〕]{1,4})\s*[\)）\]］〕]\s*"#
        if let range = name.range(of: pattern, options: .regularExpression) {
            let inner = String(name[range]).trimmingCharacters(in: CharacterSet(charactersIn: " ()（）[]［］〔〕"))
            if BookNameParser.dynastyNames.contains(inner) {
                dynasty = inner
                name.removeSubrange(range)
            }
        }
        return (name.trimmingCharacters(in: .whitespaces), dynasty)
    }

    /// Puts records matching what the book already says (publisher, year) first.
    static func ranked(_ records: [OnlineBookRecord], for book: Book) -> [OnlineBookRecord] {
        func score(_ record: OnlineBookRecord) -> Int {
            var value = 0
            if !book.publisherText.isEmpty, !record.publisher.isEmpty,
               record.publisher.contains(book.publisherText) || book.publisherText.contains(record.publisher) { value += 3 }
            if record.year.count >= 4, book.edition.contains(record.year.prefix(4)) { value += 2 }
            if record.title == book.title { value += 1 }
            return value
        }
        return records.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (score(lhs.element), score(rhs.element))
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
