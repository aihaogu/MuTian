import Foundation

/// One editable bibliographic field, shared by recognition, batch editing, online lookup and CSV.
enum BookField: String, CaseIterable, Identifiable, Sendable {
    case title = "书名"
    case volume = "卷册"
    case author = "作者"
    case dynasty = "朝代"
    case publisher = "出版社"
    case edition = "版本"
    case series = "丛书"

    var id: String { rawValue }

    var keyPath: WritableKeyPath<Book, String> {
        switch self {
        case .title: return \.title
        case .volume: return \.volumeText
        case .author: return \.author
        case .dynasty: return \.dynasty
        case .publisher: return \.publisherText
        case .edition: return \.edition
        case .series: return \.seriesText
        }
    }

    func value(in parsed: ParsedBookName) -> String {
        switch self {
        case .title: return parsed.title
        case .volume: return parsed.volume
        case .author: return parsed.author
        case .dynasty: return parsed.dynasty
        case .publisher: return parsed.publisher
        case .edition: return parsed.edition
        case .series: return parsed.series
        }
    }
}

struct FieldChange: Identifiable, Hashable, Sendable {
    var field: BookField
    var oldValue: String
    var newValue: String
    var isAccepted: Bool

    var id: String { field.rawValue }
}

struct BookChangeProposal: Identifiable, Hashable, Sendable {
    var bookID: UUID
    var fileName: String
    var changes: [FieldChange]

    var id: UUID { bookID }
    var acceptedCount: Int { changes.filter(\.isAccepted).count }
}

enum BookRecognition {
    /// Compares what the file name says with what the book currently holds.
    /// A change is pre-accepted only when the current value still looks machine-made:
    /// empty, or a fragment of the file name (the v1.0 importer copied pieces of it verbatim).
    static func proposal(for book: Book, parsed: ParsedBookName) -> BookChangeProposal? {
        let fileName = book.fileName
        var changes: [FieldChange] = []
        for field in BookField.allCases {
            let newValue = field.value(in: parsed).trimmingCharacters(in: .whitespacesAndNewlines)
            let oldValue = book[keyPath: field.keyPath]
            guard !newValue.isEmpty, newValue != oldValue else { continue }
            changes.append(FieldChange(
                field: field,
                oldValue: oldValue,
                newValue: newValue,
                isAccepted: looksGenerated(oldValue, fileName: fileName, field: field)
            ))
        }
        return changes.isEmpty ? nil : BookChangeProposal(bookID: book.id, fileName: fileName, changes: changes)
    }

    static func looksGenerated(_ value: String, fileName: String, field: BookField) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if field == .title { return trimmed == fileName }
        return fileName.contains(trimmed)
    }

    static func apply(_ proposal: BookChangeProposal, to book: inout Book) -> Bool {
        var changed = false
        for change in proposal.changes where change.isAccepted {
            book[keyPath: change.field.keyPath] = change.newValue
            changed = true
        }
        return changed
    }
}
