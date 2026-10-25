import Foundation
import CryptoKit

struct EpubDocument {
    let title: String
    let rootDirectory: URL
    let chapters: [EpubChapter]
    var tableOfContents: [ReaderOutlineEntry] = []
}

struct EpubChapter: Identifiable, Hashable {
    let id: Int
    let title: String
    let url: URL
}

enum EpubArchive {
    static func load(from epubURL: URL, cacheDirectory: URL? = nil) throws -> EpubDocument {
        guard FileManager.default.isReadableFile(atPath: epubURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let extractedRoot = try extractedRoot(for: epubURL, cacheDirectory: cacheDirectory)
        let containerURL = extractedRoot.appendingPathComponent("META-INF/container.xml")
        let opfRelativePath = try parseContainer(at: containerURL)
        let opfURL = resolve(opfRelativePath, relativeTo: extractedRoot)
        let package = try parsePackage(at: opfURL)
        let opfDirectory = opfURL.deletingLastPathComponent()
        let ncx = parseNCX(package: package, opfDirectory: opfDirectory)

        let htmlItems = orderedChapterItems(from: package)
        let chapterURLs = htmlItems.map { resolve($0.href, relativeTo: opfDirectory) }
        var chapterIndexByPath: [String: Int] = [:]
        for (index, url) in chapterURLs.enumerated() where chapterIndexByPath[url.path] == nil {
            chapterIndexByPath[url.path] = index
        }

        let nav = parseNav(package: package, opfDirectory: opfDirectory)
        let tocPoints = (nav.isComplete && !nav.points.isEmpty) || ncx.points.isEmpty ? nav.points : ncx.points
        let tableOfContents = outlineEntries(from: tocPoints, chapterIndexByPath: chapterIndexByPath)
        var tocTitles: [Int: String] = [:]
        for entry in tableOfContents.flattened where tocTitles[entry.target] == nil {
            tocTitles[entry.target] = entry.title
        }

        let chapters = htmlItems.enumerated().map { index, item in
            let chapterURL = chapterURLs[index]
            let title = ncx.labelsByPath[chapterURL.standardizedFileURL.path]
                ?? tocTitles[index]
                ?? fallbackChapterTitle(from: item, index: index)
            return EpubChapter(id: index, title: title, url: chapterURL)
        }

        guard !chapters.isEmpty else {
            throw EpubError.emptySpine
        }
        guard chapters.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.url.path) }) else {
            throw EpubError.missingChapter
        }

        return EpubDocument(
            title: package.title.isEmpty ? epubURL.deletingPathExtension().lastPathComponent : package.title,
            rootDirectory: extractedRoot,
            chapters: chapters,
            tableOfContents: tableOfContents
        )
    }

    private static func extractedRoot(for epubURL: URL, cacheDirectory: URL?) throws -> URL {
        let fm = FileManager.default
        let cacheRoot = cacheDirectory ?? AppPaths.supportDirectory.appendingPathComponent("epub-cache", isDirectory: true)
        try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let directory = cacheRoot.appendingPathComponent(cacheKey(for: epubURL), isDirectory: true)
        let marker = directory.appendingPathComponent(".extraction-complete")
        if fm.fileExists(atPath: marker.path) {
            return directory
        }

        try? fm.removeItem(at: directory)
        let staging = cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", epubURL.path, staging.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw EpubError.extractionFailed(message ?? "解包退出码 \(process.terminationStatus)")
        }

        guard fm.fileExists(atPath: staging.appendingPathComponent("META-INF/container.xml").path) else {
            throw EpubError.missingContainer
        }
        try Data().write(to: staging.appendingPathComponent(".extraction-complete"))
        do {
            try fm.moveItem(at: staging, to: directory)
        } catch {
            // Another reading window may have completed the same extraction first.
            guard fm.fileExists(atPath: marker.path) else { throw error }
        }
        return directory
    }

    private static func parseContainer(at url: URL) throws -> String {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EpubError.missingContainer
        }
        let delegate = EpubContainerParser()
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.rootfilePath, !path.isEmpty else {
            throw EpubError.invalidContainer
        }
        return path
    }

    private static func parsePackage(at url: URL) throws -> EpubPackage {
        guard let data = try? Data(contentsOf: url) else { throw EpubError.missingPackage }
        func parse(_ content: Data) -> EpubPackage? {
            let parser = XMLParser(data: content)
            let delegate = EpubPackageParser()
            parser.delegate = delegate
            guard parser.parse() else { return nil }
            return EpubPackage(
                title: delegate.title.trimmingCharacters(in: .whitespacesAndNewlines),
                manifest: delegate.manifest,
                spineIDs: delegate.spineIDs,
                tocID: delegate.tocID
            )
        }
        if let package = parse(data) { return package }
        // Some exported books contain illegal double hyphens in informational XML
        // comments. Retry without comments; keep the original archive untouched.
        if let xml = String(data: data, encoding: .utf8) {
            let withoutComments = xml.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            if withoutComments != xml, let package = parse(Data(withoutComments.utf8)) { return package }
        }
        throw EpubError.invalidPackage
    }

    private static func parseNCX(package: EpubPackage, opfDirectory: URL) -> (labelsByPath: [String: String], points: [EpubTocPoint]) {
        let tocItem = package.tocID.flatMap { package.manifest[$0] }
            ?? package.manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }
        guard let tocItem else { return ([:], []) }
        let tocURL = resolve(tocItem.href, relativeTo: opfDirectory)
        guard let parser = XMLParser(contentsOf: tocURL) else {
            return ([:], [])
        }
        let delegate = EpubNCXParser(baseDirectory: tocURL.deletingLastPathComponent())
        parser.delegate = delegate
        _ = parser.parse()
        return (delegate.labelsByPath, delegate.roots)
    }

    /// EPUB 3 navigation document (`<nav epub:type="toc">`).
    private static func parseNav(package: EpubPackage, opfDirectory: URL) -> (points: [EpubTocPoint], isComplete: Bool) {
        guard let navItem = package.manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }) else {
            return ([], false)
        }
        let navURL = resolve(navItem.href, relativeTo: opfDirectory)
        guard let parser = XMLParser(contentsOf: navURL) else { return ([], false) }
        let delegate = EpubNavParser(baseDirectory: navURL.deletingLastPathComponent())
        parser.delegate = delegate
        let succeeded = parser.parse()
        return (delegate.roots, succeeded)
    }

    private static func outlineEntries(from points: [EpubTocPoint], chapterIndexByPath: [String: Int], path: String = "") -> [ReaderOutlineEntry] {
        points.enumerated().compactMap { offset, point in
            let id = path.isEmpty ? "\(offset)" : "\(path).\(offset)"
            let children = outlineEntries(from: point.children, chapterIndexByPath: chapterIndexByPath, path: id)
            if let target = point.url.flatMap({ chapterIndexByPath[$0.path] }) {
                return ReaderOutlineEntry(id: id, title: point.title.isEmpty ? "未命名章节" : point.title,
                    target: target, fragment: point.fragment, children: children)
            }
            guard let first = children.first else { return nil }
            return ReaderOutlineEntry(id: id, title: point.title.isEmpty ? first.title : point.title,
                target: first.target, fragment: first.fragment, children: children)
        }
    }

    private static func orderedChapterItems(from package: EpubPackage) -> [EpubManifestItem] {
        let spineItems = package.spineIDs.compactMap { package.manifest[$0] }
            .filter(\.isHTML)
        if !spineItems.isEmpty {
            return spineItems
        }
        return package.manifest.values
            .filter(\.isHTML)
            .sorted { $0.href.localizedStandardCompare($1.href) == .orderedAscending }
    }

    private static func fallbackChapterTitle(from item: EpubManifestItem, index: Int) -> String {
        let name = (item.href.removingPercentEncoding ?? item.href)
            .split(separator: "/")
            .last
            .map(String.init) ?? ""
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "章节 \(index + 1)" : stem
    }

    private static func resolve(_ href: String, relativeTo directory: URL) -> URL {
        let withoutFragment = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        let decoded = withoutFragment.removingPercentEncoding ?? withoutFragment
        let relativePath = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(fileURLWithPath: relativePath, relativeTo: directory).standardizedFileURL
    }

    private static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let name = sanitized(url.deletingPathExtension().lastPathComponent)
        let identity = "\(url.standardizedFileURL.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(name.prefix(40))-\(digest)"
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let compacted = String(scalars).split(separator: "-").joined(separator: "-")
        return compacted.isEmpty ? "book" : compacted
    }
}

private enum EpubError: LocalizedError {
    case missingContainer
    case invalidContainer
    case missingPackage
    case invalidPackage
    case emptySpine
    case missingChapter
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "EPUB 中缺少 META-INF/container.xml。"
        case .invalidContainer:
            return "无法从 container.xml 读取 OPF 路径。"
        case .missingPackage:
            return "EPUB 中缺少 OPF 包文件。"
        case .invalidPackage:
            return "无法解析 EPUB 的 OPF 包文件。"
        case .emptySpine:
            return "EPUB 中没有可阅读的 HTML/XHTML 章节。"
        case .missingChapter:
            return "EPUB 的目录引用了缺失的章节文件，请检查文件是否完整。"
        case .extractionFailed(let message):
            return "EPUB 解包失败：\(message)"
        }
    }
}

private struct EpubPackage {
    let title: String
    let manifest: [String: EpubManifestItem]
    let spineIDs: [String]
    let tocID: String?
}

private struct EpubManifestItem {
    let id: String
    let href: String
    let mediaType: String
    var properties: String = ""

    var isHTML: Bool {
        let ext = href.split(separator: "#", maxSplits: 1).first.map(String.init)?
            .lowercased()
            .split(separator: ".")
            .last
            .map(String.init)
        return mediaType.contains("xhtml")
            || mediaType.contains("html")
            || ext == "xhtml"
            || ext == "html"
            || ext == "htm"
    }
}

private final class EpubContainerParser: NSObject, XMLParserDelegate {
    var rootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard rootfilePath == nil, elementName.lowercased() == "rootfile" else { return }
        rootfilePath = attributeDict["full-path"]
    }
}

private final class EpubPackageParser: NSObject, XMLParserDelegate {
    var title = ""
    var manifest: [String: EpubManifestItem] = [:]
    var spineIDs: [String] = []
    var tocID: String?
    private var isCollectingTitle = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        switch name {
        case "title":
            isCollectingTitle = true
        case "item":
            guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
            manifest[id] = EpubManifestItem(
                id: id,
                href: href,
                mediaType: attributeDict["media-type"] ?? "",
                properties: attributeDict["properties"] ?? ""
            )
        case "spine":
            tocID = attributeDict["toc"]
        case "itemref":
            guard let idref = attributeDict["idref"] else { return }
            spineIDs.append(idref)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollectingTitle else { return }
        title += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if normalized(elementName) == "title" {
            isCollectingTitle = false
        }
    }
}

private struct EpubTocPoint {
    var title: String
    var url: URL?
    var fragment: String?
    var children: [EpubTocPoint] = []

    init(title: String, href: String?, baseDirectory: URL) {
        self.title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let href, !href.isEmpty else { return }
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        url = parts[0].isEmpty ? nil : EpubArchive.resolveForParser(parts[0], relativeTo: baseDirectory)
        fragment = parts.count > 1 && !parts[1].isEmpty ? (parts[1].removingPercentEncoding ?? parts[1]) : nil
    }
}

private final class EpubNCXParser: NSObject, XMLParserDelegate {
    struct PendingPoint {
        var label = ""
        var content = ""
        var children: [EpubTocPoint] = []
    }

    let baseDirectory: URL
    var labelsByPath: [String: String] = [:]
    var roots: [EpubTocPoint] = []
    private var stack: [PendingPoint] = []
    private var isCollectingLabel = false

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        switch name {
        case "navpoint":
            stack.append(PendingPoint())
        case "text":
            isCollectingLabel = !stack.isEmpty
        case "content":
            guard !stack.isEmpty, let src = attributeDict["src"] else { return }
            stack[stack.count - 1].content = src
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollectingLabel, !stack.isEmpty else { return }
        stack[stack.count - 1].label += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalized(elementName)
        switch name {
        case "text":
            isCollectingLabel = false
        case "navpoint":
            guard let point = stack.popLast() else { return }
            let label = point.label.trimmingCharacters(in: .whitespacesAndNewlines)
            var node = EpubTocPoint(title: label, href: point.content, baseDirectory: baseDirectory)
            node.children = point.children
            if stack.isEmpty { roots.append(node) } else { stack[stack.count - 1].children.append(node) }
            guard !point.content.isEmpty, !label.isEmpty else { return }
            let url = EpubArchive.resolveForParser(point.content, relativeTo: baseDirectory)
            labelsByPath[url.standardizedFileURL.path] = label
        default:
            break
        }
    }
}

private final class EpubNavParser: NSObject, XMLParserDelegate {
    struct PendingItem {
        var title = ""
        var href: String?
        var children: [EpubTocPoint] = []
    }

    let baseDirectory: URL
    var roots: [EpubTocPoint] = []
    private var navDepth = 0
    private var foundToc = false
    private var stack: [PendingItem] = []
    private var isCollectingTitle = false

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        if name == "nav" {
            if navDepth > 0 {
                navDepth += 1
            } else if !foundToc {
                let type = attributeDict.first { normalized($0.key) == "type" }?.value ?? ""
                if type.split(separator: " ").contains("toc") { navDepth = 1 }
            }
            return
        }
        guard navDepth > 0 else { return }
        switch name {
        case "li":
            stack.append(PendingItem())
        case "a":
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].href = attributeDict["href"]
            isCollectingTitle = stack[stack.count - 1].title.isEmpty
        case "span":
            guard !stack.isEmpty else { return }
            isCollectingTitle = stack[stack.count - 1].title.isEmpty
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollectingTitle, !stack.isEmpty else { return }
        stack[stack.count - 1].title += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalized(elementName)
        guard navDepth > 0 else { return }
        switch name {
        case "nav":
            navDepth -= 1
            if navDepth == 0 { foundToc = true }
        case "a", "span":
            isCollectingTitle = false
        case "li":
            guard let item = stack.popLast() else { return }
            var node = EpubTocPoint(title: item.title, href: item.href, baseDirectory: baseDirectory)
            node.children = item.children
            if stack.isEmpty { roots.append(node) } else { stack[stack.count - 1].children.append(node) }
        default:
            break
        }
    }
}

private func normalized(_ elementName: String) -> String {
    elementName.lowercased().split(separator: ":").last.map(String.init) ?? elementName.lowercased()
}

private extension EpubArchive {
    static func resolveForParser(_ href: String, relativeTo directory: URL) -> URL {
        resolve(href, relativeTo: directory)
    }
}
