import Foundation

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
    static func load(from epubURL: URL) throws -> EpubDocument {
        let extractedRoot = try extractedRoot(for: epubURL)
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

        return EpubDocument(
            title: package.title.isEmpty ? epubURL.deletingPathExtension().lastPathComponent : package.title,
            rootDirectory: extractedRoot,
            chapters: chapters
        )
    }

    private static func extractedRoot(for epubURL: URL) throws -> URL {
        let fm = FileManager.default
        let cacheRoot = AppPaths.supportDirectory.appendingPathComponent("epub-cache", isDirectory: true)
        try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let directory = cacheRoot.appendingPathComponent(cacheKey(for: epubURL), isDirectory: true)
        let marker = directory.appendingPathComponent("META-INF/container.xml")
        if fm.fileExists(atPath: marker.path) {
            return directory
        }

        try? fm.removeItem(at: directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-oq", epubURL.path, "-d", directory.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw EpubError.unzipFailed(message ?? "unzip 退出码 \(process.terminationStatus)")
        }

        guard fm.fileExists(atPath: marker.path) else {
            throw EpubError.missingContainer
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
        guard let parser = XMLParser(contentsOf: url) else {
            throw EpubError.missingPackage
        }
        let delegate = EpubPackageParser()
        parser.delegate = delegate
        guard parser.parse() else {
            throw EpubError.invalidPackage
        }
        return EpubPackage(
            title: delegate.title.trimmingCharacters(in: .whitespacesAndNewlines),
            manifest: delegate.manifest,
            spineIDs: delegate.spineIDs,
            tocID: delegate.tocID
        )
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
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let name = sanitized(url.deletingPathExtension().lastPathComponent)
        return "\(name)-\(size)-\(modified)"
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
    case unzipFailed(String)

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
        case .unzipFailed(let message):
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
