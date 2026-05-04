import Foundation

enum FileTypeDetector {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "webp"]
    static let pdfExtensions: Set<String> = ["pdf"]
    static let textExtensions: Set<String> = ["txt", "md", "xml", "json"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPDF(_ url: URL) -> Bool {
        pdfExtensions.contains(url.pathExtension.lowercased())
    }

    static func isText(_ url: URL) -> Bool {
        textExtensions.contains(url.pathExtension.lowercased())
    }

    static func shouldSkipDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") || name == ".git" || name == ".build" || name == "dist"
    }
}
