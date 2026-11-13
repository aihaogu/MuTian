import Foundation

/// Spreadsheet round trip for bibliographic fields. Rows are matched back by the book ID column,
/// so titles and paths can be edited freely in Numbers or Excel.
enum LibraryCSV {
    static let idHeader = "ID"
    static let fields = BookField.allCases
    static let headers = [idHeader] + fields.map(\.rawValue) + ["文件名", "路径"]

    static func export(_ books: [Book]) -> Data {
        var lines = [headers.map(escape).joined(separator: ",")]
        for book in books {
            let values = [book.id.uuidString] + fields.map { book[keyPath: $0.keyPath] } + [book.fileName, book.localPath]
            lines.append(values.map(escape).joined(separator: ","))
        }
        // A byte-order mark lets Excel open the file as UTF-8.
        return Data("\u{FEFF}".utf8) + Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    enum ImportError: LocalizedError {
        case unreadable
        case missingIDColumn
        case malformedCSV
        case duplicateID

        var errorDescription: String? {
            switch self {
            case .unreadable: return "无法读取表格，请保存为 UTF-8 编码的 CSV。"
            case .missingIDColumn: return "表格缺少“ID”列，请使用木天导出的表格修改后再导入。"
            case .malformedCSV: return "表格格式有误：请检查引号、列数及重复列名，然后重新导出 CSV。"
            case .duplicateID: return "表格中存在重复的书目 ID，请为每部书目只保留一行后再导入。"
            }
        }
    }

    /// Returns one proposal per book whose fields differ from the spreadsheet.
    static func proposals(from data: Data, books: [Book]) throws -> [BookChangeProposal] {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError.unreadable
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = try parse(text)
        guard let header = rows.first, let idColumn = header.firstIndex(of: idHeader) else {
            throw ImportError.missingIDColumn
        }
        guard Set(header).count == header.count else { throw ImportError.malformedCSV }
        let columns: [(BookField, Int)] = fields.compactMap { field in
            header.firstIndex(of: field.rawValue).map { (field, $0) }
        }
        let byID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        var seenIDs: Set<UUID> = []
        return try rows.dropFirst().compactMap { row in
            guard row.count == header.count else { throw ImportError.malformedCSV }
            guard idColumn < row.count, let id = UUID(uuidString: row[idColumn].trimmingCharacters(in: .whitespaces)),
                  let book = byID[id] else { return nil }
            guard seenIDs.insert(id).inserted else { throw ImportError.duplicateID }
            let changes = columns.compactMap { field, column -> FieldChange? in
                guard column < row.count else { return nil }
                let newValue = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                let oldValue = book[keyPath: field.keyPath]
                guard newValue != oldValue, !(field == .title && newValue.isEmpty) else { return nil }
                return FieldChange(field: field, oldValue: oldValue, newValue: newValue, isAccepted: true)
            }
            return changes.isEmpty ? nil : BookChangeProposal(bookID: id, fileName: book.fileName, changes: changes)
        }
    }

    static func escape(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var closedQuote = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let char = pending { pending = nil; return char }
            return iterator.next()
        }

        while let char = next() {
            if inQuotes {
                if char == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else {
                            inQuotes = false
                            closedQuote = true
                            pending = following
                        }
                    } else {
                        inQuotes = false
                        closedQuote = true
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"":
                guard field.isEmpty, !closedQuote else { throw ImportError.malformedCSV }
                inQuotes = true
            case ",": row.append(field); field = ""; closedQuote = false
            case "\r\n", "\n", "\r":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
                closedQuote = false
            default:
                guard !closedQuote else { throw ImportError.malformedCSV }
                field.append(char)
            }
        }
        guard !inQuotes else { throw ImportError.malformedCSV }
        if !field.isEmpty || !row.isEmpty || closedQuote {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
