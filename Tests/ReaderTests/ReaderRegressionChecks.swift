import AppKit
import Darwin
import CoreFoundation
import Foundation
import PDFKit

@main
struct ReaderRegressionChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ReaderChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() {
        setbuf(stdout, nil)
        do { try run() } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("mutian-readers-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        try testPaths(in: temporary)
        try testText()
        try testEpub(in: temporary)
        let missing = FolderScanner.scan(root: temporary.appendingPathComponent("missing"))
        try require(!missing.isComplete && missing.books.isEmpty, "Unavailable roots must not produce a complete empty scan")
        print("PASS: path repair, metadata preservation, missing-root scan, text encodings")

        if CommandLine.arguments.count == 3 {
            try checkLibrary(at: URL(fileURLWithPath: CommandLine.arguments[1]), newRoot: URL(fileURLWithPath: CommandLine.arguments[2]), cache: temporary)
        }
    }

    static func testPaths(in base: URL) throws {
        let fm = FileManager.default
        let old = base.appendingPathComponent("old")
        let new = base.appendingPathComponent("new")
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("book".utf8).write(to: new.appendingPathComponent("book.pdf"))
        try Data("image".utf8).write(to: new.appendingPathComponent("01.jpg"))
        var book = Book.new(title: "Test", localPath: old.appendingPathComponent("book.pdf").path, fileType: .pdf, pageCount: 100)
        book.lastReadPage = 37
        book.isFavorite = true
        book.notes = "Preserve notes"
        book.pageRecords = [PageRecord(id: UUID(), bookID: book.id, pageIndex: 0, imagePath: old.appendingPathComponent("01.jpg").path, ocrText: "OCR", correctedText: "Correction", notes: "Page note", status: "Checked")]
        var untouched = book
        untouched.id = UUID()
        untouched.localPath = old.path + "-other/book.pdf"
        var missing = book
        missing.id = UUID()
        missing.localPath = old.appendingPathComponent("missing.pdf").path
        missing.pageRecords = []
        var snapshot = LibrarySnapshot(books: [book, untouched, missing], roots: [.new(path: old.path)])
        let changes = LibraryPathRepair.repair(&snapshot, from: old, to: new)
        try require(changes == 4, "Unexpected repaired path count")
        var expected = book
        expected.localPath = new.appendingPathComponent("book.pdf").path
        expected.pageRecords[0].imagePath = new.appendingPathComponent("01.jpg").path
        try require(snapshot.books[0] == expected, "Metadata or page annotations changed")
        try require(snapshot.books[1].localPath == untouched.localPath, "Prefix collision")
        try require(snapshot.books[2] == missing, "Missing destination must not be invented")
        try require(snapshot.roots[0].path == new.path, "Root did not move")
        try require(LibraryPathRepair.repair(&snapshot, from: old, to: new) == 0, "Repair must be idempotent")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data().write(to: old.appendingPathComponent("book.pdf"))
        snapshot.books = [book]
        _ = LibraryPathRepair.repair(&snapshot, from: old, to: new)
        try require(snapshot.books[0].localPath == book.localPath, "An existing original must not be redirected")
    }

    static func testText() throws {
        let sample = "天地玄黄，宇宙洪荒。\nTest 123"
        let cases: [(String.Encoding, [UInt8])] = [(.utf8, []), (.utf8, [0xEF,0xBB,0xBF]), (.utf16LittleEndian, [0xFF,0xFE]), (.utf16BigEndian, [0xFE,0xFF]), (.utf32LittleEndian, [0xFF,0xFE,0,0])]
        for (encoding, bom) in cases {
            let data = Data(bom) + sample.data(using: encoding)!
            try require(try TextFileLoader.decode(data) == sample, "Unicode encoding failed: \(encoding)")
        }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        try require(try TextFileLoader.decode(sample.data(using: gb)!) == sample, "GB18030 failed")
        try require(try TextFileLoader.decode(Data()) == "", "Empty text failed")
    }

    static func testEpub(in base: URL) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/legacy-permissions.epub")
        let cache = base.appendingPathComponent("fixture-cache")
        let document = try EpubArchive.load(from: fixture, cacheDirectory: cache)
        try require(document.chapters.count == 1, "Legacy ZIP directory permissions blocked extraction")
        let first = base.appendingPathComponent("a", isDirectory: true)
        let second = base.appendingPathComponent("b", isDirectory: true)
        var roots: [URL] = []
        for directory in [first, second] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent("same-name.epub")
            try FileManager.default.copyItem(at: fixture, to: copy)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: copy.path)
            roots.append(try EpubArchive.load(from: copy, cacheDirectory: cache).rootDirectory)
        }
        try require(roots[0] != roots[1], "Same-name books must not share their extracted contents")
    }

    static func checkLibrary(at libraryURL: URL, newRoot: URL, cache: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshot = try decoder.decode(LibrarySnapshot.self, from: Data(contentsOf: libraryURL))
        for root in snapshot.roots where !FileManager.default.fileExists(atPath: root.path) && URL(fileURLWithPath: root.path).lastPathComponent == "得古测试" {
            _ = LibraryPathRepair.repair(&snapshot, from: URL(fileURLWithPath: root.path), to: newRoot)
        }
        try require(snapshot.books.allSatisfy { FileManager.default.fileExists(atPath: $0.localPath) }, "Unresolved books")
        print("PASS: \(snapshot.books.count) real book paths")
        let images = snapshot.books.flatMap(\.pageRecords)
        for page in images {
            try require(NSImage(contentsOfFile: page.imagePath)?.isValid == true, "Unreadable image: \(page.imagePath)")
        }
        print("PASS: \(images.count) actual image pages")
        let texts = snapshot.books.filter { $0.fileType == .text }
        for book in texts {
            _ = try TextFileLoader.load(from: URL(fileURLWithPath: book.localPath))
        }
        print("PASS: \(texts.count) actual text files")
        let epubs = snapshot.books.filter { URL(fileURLWithPath: $0.localPath).pathExtension.lowercased() == "epub" }
        for book in epubs {
            print("Checking EPUB: \(book.title)")
            let document = try EpubArchive.load(from: URL(fileURLWithPath: book.localPath), cacheDirectory: cache.appendingPathComponent("epubs"))
            try require(!document.chapters.isEmpty, "Empty EPUB")
            print("PASS EPUB: \(document.chapters.count) chapters — \(book.title)")
        }
        let pdfs = snapshot.books.filter { $0.fileType == .pdf }.filter {
            $0.title.contains("国榷_03") || $0.title.contains("中国寺庙宝典 01") || $0.title.contains("清代官员履历档案全编全三十卷合集 (下冊)")
        }
        try require(!pdfs.isEmpty, "Missing PDF samples")
        for book in pdfs {
            let document = PDFDocument(url: URL(fileURLWithPath: book.localPath))
            try require(document != nil && document!.pageCount > 0, "Unreadable PDF: \(book.title)")
            let image = document!.page(at: 0)!.thumbnail(of: NSSize(width: 160, height: 220), for: .mediaBox)
            try require(image.isValid, "PDF render failed")
            print("PASS PDF: \(document!.pageCount) pages — \(book.title)")
        }
    }
}
