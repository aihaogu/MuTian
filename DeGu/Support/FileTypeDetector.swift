import Foundation

enum FileTypeDetector {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "webp"]
    static let pdfExtensions: Set<String> = ["pdf"]
    static let textExtensions: Set<String> = ["txt", "md", "xml", "json"]
    static let ebookExtensions: Set<String> = ["epub", "mobi", "azw3"]
    static let documentExtensions: Set<String> = ["djvu", "uvz", "doc", "docx", "ppt", "pptx"]
    static let archiveExtensions: Set<String> = ["zip"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPDF(_ url: URL) -> Bool {
        pdfExtensions.contains(url.pathExtension.lowercased())
    }

    static func isText(_ url: URL) -> Bool {
        textExtensions.contains(url.pathExtension.lowercased())
    }

    static func bookFileType(for url: URL) -> BookFileType? {
        let ext = url.pathExtension.lowercased()
        if pdfExtensions.contains(ext) { return .pdf }
        if textExtensions.contains(ext), !isMetadataFile(url), !isLikelySidecarResource(url) { return .text }
        if ebookExtensions.contains(ext) { return .ebook }
        if documentExtensions.contains(ext) { return .document }
        if archiveExtensions.contains(ext) { return .archive }
        return nil
    }

    static func isSupportedBookFile(_ url: URL) -> Bool {
        bookFileType(for: url) != nil
    }

    static func shouldSkipDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name == ".git" || name == ".build" || name == "dist"
    }

    static func isLikelySidecarResource(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let sidecarMarkers = ["更多资源", "扫此码", "扫码", "公众号", "readme", "新建 文本文档", "新建文本文档"]
        return sidecarMarkers.contains { name.contains($0) }
    }

    private static func isMetadataFile(_ url: URL) -> Bool {
        ["metadata", "manifest", "info"].contains(url.deletingPathExtension().lastPathComponent.lowercased())
    }
}
