import Foundation
import CryptoKit

struct EpubDocument {
    let title: String
    let rootDirectory: URL
    let chapters: [EpubChapter]
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
        let labelMap = parseChapterLabels(package: package, opfDirectory: opfDirectory)

        let htmlItems = orderedChapterItems(from: package)
        let chapters = htmlItems.enumerated().map { index, item in
            let chapterURL = resolve(item.href, relativeTo: opfDirectory)
            let title = labelMap[chapterURL.standardizedFileURL.path]
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
            chapters: chapters
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

    private static func parseChapterLabels(package: EpubPackage, opfDirectory: URL) -> [String: String] {
        guard
            let tocID = package.tocID,
            let tocItem = package.manifest[tocID]
        else {
            return [:]
        }
        let tocURL = resolve(tocItem.href, relativeTo: opfDirectory)
        guard let parser = XMLParser(contentsOf: tocURL) else {
            return [:]
        }
        let delegate = EpubNCXParser(baseDirectory: tocURL.deletingLastPathComponent())
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.labelsByPath
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
                mediaType: attributeDict["media-type"] ?? ""
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

private final class EpubNCXParser: NSObject, XMLParserDelegate {
    struct PendingPoint {
        var label = ""
        var content = ""
    }

    let baseDirectory: URL
    var labelsByPath: [String: String] = [:]
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
            guard !point.content.isEmpty, !label.isEmpty else { return }
            let url = EpubArchive.resolveForParser(point.content, relativeTo: baseDirectory)
            labelsByPath[url.standardizedFileURL.path] = label
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
