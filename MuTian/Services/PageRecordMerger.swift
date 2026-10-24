import Foundation

enum PageRecordMerger {
    static func fileIdentity(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let volume = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let created = attributes[.creationDate] as? Date else { return nil }
        return "\(volume):\(inode):\(created.timeIntervalSince1970)"
    }

    static func merge(_ scanned: [PageRecord], into book: inout Book) -> Bool {
        let oldPages = book.pageRecords
        let oldArchive = book.archivedPageRecords ?? []
        var available = oldPages + oldArchive
        let readingID = oldPages.first { $0.pageIndex == book.lastReadPage }?.id
        var merged: [PageRecord] = []
        for source in scanned {
            // Prefer a verified file identity so renames retain annotations. Legacy
            // records without an identity can only be matched by their exact path.
            let index = available.firstIndex {
                $0.imagePath == source.imagePath &&
                ($0.fileIdentity == nil || $0.fileIdentity == source.fileIdentity)
            } ?? available.firstIndex {
                source.fileIdentity != nil && $0.fileIdentity == source.fileIdentity
            }
            var page = index.map { available.remove(at: $0) } ?? source
            page.bookID = book.id
            page.pageIndex = source.pageIndex
            page.imagePath = source.imagePath
            page.fileIdentity = source.fileIdentity
            merged.append(page)
        }
        for index in available.indices { available[index].bookID = book.id }
        let changed = oldPages != merged || oldArchive != available || book.pageCount != merged.count
        guard changed else { return false }
        book.pageRecords = merged
        book.archivedPageRecords = available.isEmpty ? nil : available
        book.pageCount = merged.count
        book.lastReadPage = merged.first { $0.id == readingID }?.pageIndex
            ?? min(book.lastReadPage, max(0, merged.count - 1))
        return true
    }
}
