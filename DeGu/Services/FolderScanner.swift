import Foundation
import PDFKit

struct ScanResult {
    var books: [Book]
    var scannedPath: String
}

enum FolderScanner {
    static func scan(root: URL, existingPaths: Set<String>) -> ScanResult {
        var books: [Book] = []
        var seenImageDirectories = Set<String>()
        let fm = FileManager.default

        func appendPDF(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !existingPaths.contains(path) else { return }
            let pageCount = PDFDocument(url: url)?.pageCount ?? 0
            var book = Book.new(
                title: url.deletingPathExtension().lastPathComponent,
                localPath: path,
                fileType: .pdf,
                pageCount: pageCount
            )
            let metadata = MetadataParser.parseMetadata(in: url.deletingLastPathComponent())
            apply(metadata, to: &book)
            books.append(book)
        }

        func appendImageDirectory(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !existingPaths.contains(path), !seenImageDirectories.contains(path) else { return }
            guard let children = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let images = children.filter(FileTypeDetector.isImage)
            guard !images.isEmpty else { return }
            seenImageDirectories.insert(path)

            var book = Book.new(
                title: url.lastPathComponent,
                localPath: path,
                fileType: .imageSequence,
                pageCount: images.count
            )
            let metadata = MetadataParser.parseMetadata(in: url)
            apply(metadata, to: &book)
            book.pageRecords = NaturalSort.sortURLs(images).enumerated().map { index, imageURL in
                PageRecord(
                    id: UUID(),
                    bookID: book.id,
                    pageIndex: index,
                    imagePath: imageURL.standardizedFileURL.path,
                    ocrText: "",
                    correctedText: "",
                    notes: "",
                    status: "未校对"
                )
            }
            books.append(book)
        }

        if FileTypeDetector.isPDF(root) {
            appendPDF(root)
            return ScanResult(books: books, scannedPath: root.standardizedFileURL.path)
        }

        appendImageDirectory(root)

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ScanResult(books: books, scannedPath: root.standardizedFileURL.path)
        }

        for case let url as URL in enumerator {
            if FileTypeDetector.shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                appendImageDirectory(url)
            } else if values?.isRegularFile == true, FileTypeDetector.isPDF(url) {
                appendPDF(url)
            }
        }

        return ScanResult(books: books, scannedPath: root.standardizedFileURL.path)
    }

    private static func apply(_ metadata: MetadataCandidate, to book: inout Book) {
        if let title = metadata.title, !title.isEmpty {
            book.title = title
        }
        if let author = metadata.author {
            book.author = author
        }
        if let sourceName = metadata.sourceName {
            book.sourceName = sourceName
        }
        if let sourceURL = metadata.sourceURL {
            book.sourceURL = sourceURL
        }
    }
}
