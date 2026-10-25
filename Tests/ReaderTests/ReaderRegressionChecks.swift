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
        try testPDFOutline(in: temporary)
        try testEpubTableOfContents(in: temporary)
        try testImagePages(in: temporary)
        try testTwoUpNormalization()
        let missing = FolderScanner.scan(root: temporary.appendingPathComponent("missing"))
        try require(!missing.isComplete && missing.books.isEmpty, "Unavailable roots must not produce a complete empty scan")
        print("PASS: path repair, metadata preservation, missing-root scan, text encodings, PDF/EPUB tables of contents, lazy image pages, two-up page widths")

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

    static func testImagePages(in base: URL) throws {
        func writeImage(_ name: String, width: Int, height: Int, color: CGColor, dpi: Double?) throws -> URL {
            let url = base.appendingPathComponent(name)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "image context", code: 1)
            }
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                throw NSError(domain: "image write", code: 1)
            }
            var properties: [CFString: Any] = [:]
            if let dpi { properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            try require(CGImageDestinationFinalize(destination), "Could not write \(name)")
            return url
        }

        let red = try writeImage("red.png", width: 600, height: 900, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1), dpi: 300)
        let blue = try writeImage("blue.png", width: 400, height: 200, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1), dpi: nil)
        let bookID = UUID()
        func record(_ index: Int, _ url: URL) -> PageRecord {
            PageRecord(id: UUID(), bookID: bookID, pageIndex: index, imagePath: url.path, ocrText: "", correctedText: "", notes: "", status: "")
        }
        let pages = [record(2, base.appendingPathComponent("missing.png")), record(1, blue), record(0, red)]
        guard let document = ImageSequenceDocument.make(pages: pages) else { throw NSError(domain: "image document", code: 1) }
        try require(document.pageCount == 3, "Image document page count wrong")

        let sizes = (0..<3).map { document.page(at: $0)!.bounds(for: .mediaBox).size }
        try require(sizes[0] == CGSize(width: 144, height: 216), "300 dpi page should be sized in points: \(sizes[0])")
        try require(sizes[1] == CGSize(width: 200, height: 100), "Page without DPI should use the fallback scale: \(sizes[1])")
        try require(sizes[2] == CGSize(width: 595, height: 842), "Unreadable page should keep a placeholder size: \(sizes[2])")

        func centerColor(of index: Int) throws -> NSColor {
            let page = document.page(at: index)!
            let size = page.bounds(for: .mediaBox).size
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "render", code: index)
            }
            page.draw(with: .mediaBox, to: context.cgContext)
            context.flushGraphics()
            guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else {
                throw NSError(domain: "pixel", code: index)
            }
            return color
        }
        let first = try centerColor(of: 0), second = try centerColor(of: 1), missing = try centerColor(of: 2)
        try require(first.redComponent > 0.8 && first.blueComponent < 0.2, "Image page should draw its picture: \(first)")
        try require(second.blueComponent > 0.8 && second.redComponent < 0.2, "Pages should follow pageIndex order: \(second)")
        try require(missing.redComponent > 0.9 && missing.blueComponent > 0.9, "Missing image should draw a blank page: \(missing)")
    }

    static func testTwoUpNormalization() throws {
        func page(width: Int, height: Int, draw: (CGContext) -> Void) throws -> PDFPage {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "context", code: 1)
            }
            draw(context)
            guard let image = context.makeImage(), let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: width, height: height))) else {
                throw NSError(domain: "page", code: 1)
            }
            return page
        }
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let document = PDFDocument()
        for index in 0..<4 {
            document.insert(try page(width: 400, height: 600) { $0.setFillColor(white); $0.fill(CGRect(x: 0, y: 0, width: 400, height: 600)) }, at: index)
        }
        let spread = try page(width: 1200, height: 600) { context in
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 300, y: 0, width: 900, height: 600))
        }
        spread.setBounds(CGRect(x: 300, y: 0, width: 900, height: 600), for: .cropBox)
        document.insert(spread, at: 2)

        try require(TwoUpPageNormalizer.apply(true, to: document) == 1, "Only the oversized page should be normalized")
        try require(TwoUpPageNormalizer.apply(true, to: document) == 0, "Normalizing twice must not stack proxies")
        let widths = (0..<document.pageCount).map { document.page(at: $0)!.bounds(for: .cropBox).width }
        try require(widths.allSatisfy { abs($0 - 400) < 0.5 }, "Two-up pages should share one column width: \(widths)")
        let proxy = document.page(at: 2)!
        try require(abs(proxy.bounds(for: .cropBox).height - 600 * 400 / 900) < 0.5, "Proxy must keep the page aspect ratio")

        let size = proxy.bounds(for: .mediaBox).size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "render", code: 1) }
        proxy.draw(with: .mediaBox, to: context.cgContext)
        context.flushGraphics()
        for x in [bitmap.pixelsWide / 20, bitmap.pixelsWide / 2] {
            let color = bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB)
            try require((color?.redComponent ?? 0) > 0.8 && (color?.blueComponent ?? 1) < 0.2, "Proxy should draw the cropped area at x=\(x): \(String(describing: color))")
        }

        try require(TwoUpPageNormalizer.apply(false, to: document) == 1, "Leaving two-up should restore the original page")
        try require(document.page(at: 2) === spread && document.pageCount == 5, "Original page must be restored in place")
    }

    static func testPDFOutline(in base: URL) throws {
        let image = NSImage(size: NSSize(width: 60, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 60, height: 80).fill()
        image.unlockFocus()

        let document = PDFDocument()
        for index in 0..<5 {
            guard let page = PDFPage(image: image) else { throw NSError(domain: "PDF page", code: 1) }
            document.insert(page, at: index)
        }
        func outline(_ label: String, page: Int) -> PDFOutline {
            let item = PDFOutline()
            item.label = label
            item.destination = PDFDestination(page: document.page(at: page)!, at: .zero)
            return item
        }
        let root = PDFOutline()
        let volumeOne = outline("卷一", page: 0)
        volumeOne.insertChild(outline("序", page: 1), at: 0)
        root.insertChild(volumeOne, at: 0)
        root.insertChild(outline("卷二", page: 3), at: 1)
        document.outlineRoot = root
        let file = base.appendingPathComponent("outline.pdf")
        try require(document.write(to: file), "Could not write outline PDF")

        guard let reloaded = PDFDocument(url: file) else { throw NSError(domain: "PDF reload", code: 1) }
        let entries = PDFOutlineReader.entries(from: reloaded)
        try require(entries.map(\.title) == ["卷一", "卷二"] && entries.map(\.target) == [0, 3], "PDF top-level bookmarks wrong: \(entries)")
        try require(entries[0].children.first?.title == "序" && entries[0].children.first?.target == 1, "PDF nested bookmark lost")
        try require(entries.entry(atOrBefore: 2)?.title == "序" && entries.entry(atOrBefore: 4)?.title == "卷二", "Current bookmark lookup wrong")
        try require(entries.ancestorIDs(of: entries[0].children[0].id) == [entries[0].id], "Bookmark ancestors wrong")
        try require(PDFOutlineReader.entries(from: document).count == 2, "In-memory outline unreadable")
    }

    static func testEpubTableOfContents(in base: URL) throws {
        let nav = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="landmarks"><ol><li><a href="ch2.xhtml">不应出现</a></li></ol></nav>
        <nav epub:type="toc"><ol>
          <li><a href="ch1.xhtml">第一章</a><ol><li><a href="ch1.xhtml#s2">第二节</a></li></ol></li>
          <li><span>附录</span><ol><li><a href="ch2.xhtml">第二章</a></li></ol></li>
        </ol></nav></body></html>
        """
        let document = try loadGeneratedEpub(in: base, name: "nav", nav: nav)
        let toc = document.tableOfContents
        try require(toc.map(\.title) == ["第一章", "附录"], "EPUB nav top level wrong: \(toc.map(\.title))")
        try require(toc[0].children.first?.target == 0 && toc[0].children.first?.fragment == "s2", "EPUB nav anchor lost")
        try require(toc[1].target == 1 && toc[1].children.first?.title == "第二章", "EPUB heading without link must point to its first child")
        try require(document.chapters.map(\.title) == ["NCX 一", "NCX 二"], "Chapter names should still prefer NCX labels")

        let broken = try loadGeneratedEpub(in: base, name: "broken-nav", nav: "<html><body><nav epub:type=\"toc\"><ol><li><a href=\"ch1.xhtml\">坏&nbsp;目录</a></li></ol></nav></body></html>")
        try require(broken.tableOfContents.map(\.title) == ["NCX 一", "NCX 二"] && broken.tableOfContents[0].children.first?.fragment == "n1",
            "Malformed nav must fall back to the nested NCX table of contents")
    }

    static func loadGeneratedEpub(in base: URL, name: String, nav: String) throws -> EpubDocument {
        let fm = FileManager.default
        let source = base.appendingPathComponent("\(name)-source", isDirectory: true)
        let oebps = source.appendingPathComponent("OEBPS", isDirectory: true)
        try fm.createDirectory(at: source.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)
        let files: [(URL, String)] = [
            (source.appendingPathComponent("mimetype"), "application/epub+zip"),
            (source.appendingPathComponent("META-INF/container.xml"), """
            <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """),
            (oebps.appendingPathComponent("content.opf"), """
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>目录测试</dc:title></metadata>
            <manifest>
              <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
              <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
              <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
              <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine></package>
            """),
            (oebps.appendingPathComponent("toc.ncx"), """
            <?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>
              <navPoint id="p1"><navLabel><text>NCX 一</text></navLabel><content src="ch1.xhtml"/>
                <navPoint id="p1a"><navLabel><text>NCX 一·上</text></navLabel><content src="ch1.xhtml#n1"/></navPoint>
              </navPoint>
              <navPoint id="p2"><navLabel><text>NCX 二</text></navLabel><content src="ch2.xhtml"/></navPoint>
            </navMap></ncx>
            """),
            (oebps.appendingPathComponent("nav.xhtml"), nav),
            (oebps.appendingPathComponent("ch1.xhtml"), "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p id=\"s2\">一</p></body></html>"),
            (oebps.appendingPathComponent("ch2.xhtml"), "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>二</p></body></html>"),
        ]
        for (url, contents) in files { try Data(contents.utf8).write(to: url) }

        let epub = base.appendingPathComponent("\(name).epub")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", source.path, epub.path]
        try zip.run()
        zip.waitUntilExit()
        try require(zip.terminationStatus == 0, "Could not build \(name).epub")
        return try EpubArchive.load(from: epub, cacheDirectory: base.appendingPathComponent("toc-cache"))
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
