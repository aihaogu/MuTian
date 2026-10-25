import Foundation
import PDFKit

/// One table-of-contents entry; `target` is a PDF page index or an EPUB chapter index.
struct ReaderOutlineEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let target: Int
    var fragment: String? = nil
    var children: [ReaderOutlineEntry] = []
}

extension Array where Element == ReaderOutlineEntry {
    var flattened: [ReaderOutlineEntry] {
        flatMap { [$0] + $0.children.flattened }
    }

    /// The last entry in reading order that starts at or before `target`.
    func entry(atOrBefore target: Int) -> ReaderOutlineEntry? {
        flattened.last { $0.target <= target }
    }

    func ancestorIDs(of id: String) -> [String] {
        for entry in self where entry.children.flattened.contains(where: { $0.id == id }) {
            return [entry.id] + entry.children.ancestorIDs(of: id)
        }
        return []
    }
}

enum PDFOutlineReader {
    static func entries(from document: PDFDocument) -> [ReaderOutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        return children(of: root, in: document, path: "")
    }

    private static func children(of node: PDFOutline, in document: PDFDocument, path: String) -> [ReaderOutlineEntry] {
        (0..<node.numberOfChildren).compactMap { index in
            guard let child = node.child(at: index) else { return nil }
            let id = path.isEmpty ? "\(index)" : "\(path).\(index)"
            let nested = children(of: child, in: document, path: id)
            let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let target = pageIndex(of: child, in: document) ?? nested.first?.target else { return nil }
            return ReaderOutlineEntry(id: id, title: title.isEmpty ? "第 \(target + 1) 页" : title, target: target, children: nested)
        }
    }

    private static func pageIndex(of outline: PDFOutline, in document: PDFDocument) -> Int? {
        let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        guard let page = destination?.page else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }
}
