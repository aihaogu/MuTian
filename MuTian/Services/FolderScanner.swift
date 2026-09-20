import Foundation
import PDFKit

struct ScanResult {
    var books: [Book]
    var scannedPath: String
    var isComplete = true
}

enum FolderScanner {
    private static let minimumImageSequencePageCount = 2

    static func scan(root: URL) -> ScanResult {
        var books: [Book] = []
        var seenImageDirectories = Set<String>()
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: root.path) else {
            return ScanResult(books: [], scannedPath: root.standardizedFileURL.path, isComplete: false)
        }
        var isComplete = true

        func appendBookFile(_ url: URL) {
            guard let fileType = FileTypeDetector.bookFileType(for: url) else { return }
            let path = url.standardizedFileURL.path
            let pageCount = fileType == .pdf ? pdfPageCount(for: url) : 0
            var book = Book.new(
                title: url.deletingPathExtension().lastPathComponent,
                localPath: path,
                fileType: fileType,
                pageCount: pageCount
            )
            let metadata = MetadataParser.parseMetadata(for: url, root: root)
            apply(metadata, to: &book)
            books.append(book)
        }

        func appendImageDirectory(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !seenImageDirectories.contains(path) else { return }
            guard let children = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { isComplete = false; return }

            let images = children.filter { FileTypeDetector.isImage($0) && !FileTypeDetector.isLikelySidecarResource($0) }
            guard images.count >= minimumImageSequencePageCount else { return }
            seenImageDirectories.insert(path)

            var book = Book.new(
                title: url.lastPathComponent,
                localPath: path,
                fileType: .imageSequence,
                pageCount: images.count
            )
            let metadata = MetadataParser.parseMetadata(for: url, root: root)
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

        if FileTypeDetector.isSupportedBookFile(root) {
            appendBookFile(root)
            return ScanResult(books: books, scannedPath: root.standardizedFileURL.path)
        }

        appendImageDirectory(root)

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in isComplete = false; return true }
        ) else {
            return ScanResult(books: books, scannedPath: root.standardizedFileURL.path, isComplete: false)
        }

        for case let url as URL in enumerator {
            if FileTypeDetector.shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values == nil { isComplete = false }
            if values?.isDirectory == true {
                appendImageDirectory(url)
            } else if values?.isRegularFile == true {
                appendBookFile(url)
            }
        }

        return ScanResult(books: books, scannedPath: root.standardizedFileURL.path, isComplete: isComplete)
    }

    private static func apply(_ metadata: MetadataCandidate, to book: inout Book) {
        if let title = metadata.title, !title.isEmpty {
            book.title = title
        }
        if let author = metadata.author {
            book.author = author
        }
        if let dynasty = metadata.dynasty {
            book.dynasty = dynasty
        }
        if let edition = metadata.edition {
            book.edition = edition
        }
        if let classificationID = metadata.classificationID {
            book.classificationID = classificationID
        }
        if let sourceName = metadata.sourceName {
            book.sourceName = sourceName
        }
        if let sourceURL = metadata.sourceURL {
            book.sourceURL = sourceURL
        }
    }

    private static func pdfPageCount(for url: URL) -> Int {
        let pdfKitCount = PDFDocument(url: url)?.pageCount ?? 0
        if pdfKitCount > 0 {
            return pdfKitCount
        }
        return fallbackPDFPageCount(for: url)
    }

    private static func fallbackPDFPageCount(for url: URL) -> Int {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return 0 }
        let text = String(decoding: data, as: UTF8.self)
        let pattern = #"/Type\s*/Pages[\s\S]{0,200000}?/Count\s+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let counts = regex.matches(in: text, range: range).compactMap { match -> Int? in
            for index in 1..<match.numberOfRanges {
                guard let capture = Range(match.range(at: index), in: text) else { continue }
                return Int(text[capture])
            }
            return nil
        }
        return counts.max() ?? 0
    }
}
