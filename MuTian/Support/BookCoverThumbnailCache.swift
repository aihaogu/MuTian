import AppKit
import Foundation
import ImageIO
import PDFKit

struct BookCoverThumbnailRequest: Hashable, Sendable {
    let key: String
    let fileTypeRawValue: String
    let localPath: String
    let firstImagePath: String?

    var hasRenderableSource: Bool {
        if fileTypeRawValue == BookFileType.pdf.rawValue {
            return !localPath.isEmpty
        }
        if fileTypeRawValue == BookFileType.imageSequence.rawValue {
            return firstImagePath?.isEmpty == false
        }
        return false
    }

    init(book: Book) {
        fileTypeRawValue = book.fileType.rawValue
        localPath = book.localPath
        firstImagePath = book.pageRecords.first?.imagePath

        let sourcePath = book.fileType == .imageSequence ? firstImagePath : localPath
        let signature = Self.fileSignature(for: sourcePath)
        key = "\(book.fileType.rawValue)|\(sourcePath ?? "")|\(signature)"
    }

    private static func fileSignature(for path: String?) -> String {
        guard let path, !path.isEmpty else { return "missing" }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return "\(Int(modified))-\(size)"
    }
}

actor BookCoverThumbnailCache {
    static let shared = BookCoverThumbnailCache()

    private let cacheLimit = 180
    private var thumbnails: [String: Data] = [:]
    private var keyOrder: [String] = []
    private var inFlight: [String: Task<Data?, Never>] = [:]

    func thumbnailData(for request: BookCoverThumbnailRequest, maxPixelDimension: Int = 640) async -> Data? {
        guard request.hasRenderableSource else { return nil }
        if let cached = thumbnails[request.key] {
            return cached
        }
        if let task = inFlight[request.key] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            Self.renderThumbnailData(for: request, maxPixelDimension: maxPixelDimension)
        }
        inFlight[request.key] = task
        let data = await task.value
        inFlight[request.key] = nil

        if let data {
            store(data, for: request.key)
        }
        return data
    }

    private func store(_ data: Data, for key: String) {
        thumbnails[key] = data
        keyOrder.removeAll { $0 == key }
        keyOrder.append(key)

        while keyOrder.count > cacheLimit {
            let oldestKey = keyOrder.removeFirst()
            thumbnails.removeValue(forKey: oldestKey)
        }
    }

    private static func renderThumbnailData(for request: BookCoverThumbnailRequest, maxPixelDimension: Int) -> Data? {
        if request.fileTypeRawValue == BookFileType.pdf.rawValue {
            return pdfThumbnailData(path: request.localPath, maxPixelDimension: maxPixelDimension)
        }
        if request.fileTypeRawValue == BookFileType.imageSequence.rawValue,
           let firstImagePath = request.firstImagePath {
            return imageThumbnailData(path: firstImagePath, maxPixelDimension: maxPixelDimension)
        }
        return nil
    }

    private static func pdfThumbnailData(path: String, maxPixelDimension: Int) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            return nil
        }

        let bounds = page.bounds(for: .mediaBox)
        let aspectRatio = max(0.2, min(2.0, bounds.width / max(bounds.height, 1)))
        let width = CGFloat(maxPixelDimension)
        let height = min(CGFloat(maxPixelDimension) * 1.6, width / aspectRatio)
        let image = page.thumbnail(of: NSSize(width: width, height: height), for: .mediaBox)
        return pngData(from: image)
    }

    private static func imageThumbnailData(path: String, maxPixelDimension: Int) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .png, properties: [:])
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            guard let tiffData = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiffData) else {
                return nil
            }
            return representation.representation(using: .png, properties: [:])
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
