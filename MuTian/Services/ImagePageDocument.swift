import AppKit
import ImageIO
import PDFKit

enum ImageSequenceDocument {
    static func make(pages: [PageRecord]) -> PDFDocument? {
        let document = PDFDocument()
        let ordered = pages.sorted { $0.pageIndex < $1.pageIndex }
        for (index, record) in ordered.enumerated() {
            let url = URL(fileURLWithPath: record.imagePath)
            let size = pointSize(of: url) ?? CGSize(width: 595, height: 842)
            document.insert(ImageFilePage(imageURL: url, size: size), at: index)
        }
        return document.pageCount > 0 ? document : nil
    }

    /// Reads only the image header; scans without a usable DPI are treated as 144 dpi.
    static func pointSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
        let scale = dpi > 72 ? 72 / dpi : 0.5
        let size = CGSize(width: width * scale, height: height * scale)
        return (5...8).contains(orientation) ? CGSize(width: size.height, height: size.width) : size
    }
}

/// A PDF page backed by an image file that is decoded only when the page is drawn.
final class ImageFilePage: PDFPage, @unchecked Sendable {
    private let imageURL: URL

    init(imageURL: URL, size: CGSize) {
        self.imageURL = imageURL
        super.init()
        setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let rect = bounds(for: box)
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        if let image = ImagePageCache.shared.image(for: imageURL) {
            context.interpolationQuality = .high
            context.draw(image, in: rect)
        }
        context.restoreGState()
    }
}

/// PDFView sizes every two-up column to the widest page, so a single fold-out or cover spread
/// pushes all facing pages apart. Oversized pages are swapped for scaled proxies while two-up is on.
enum TwoUpPageNormalizer {
    static let tolerance: CGFloat = 1.12

    @discardableResult
    static func apply(_ enabled: Bool, to document: PDFDocument) -> Int {
        enabled ? normalize(document) : restore(document)
    }

    private static func normalize(_ document: PDFDocument) -> Int {
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        let widths = pages.filter { !($0 is ScaledProxyPage) && $0.rotation % 180 == 0 }
            .map { $0.bounds(for: .cropBox).width }
            .sorted()
        guard !widths.isEmpty else { return 0 }
        let typical = widths[widths.count / 2]
        guard typical > 0 else { return 0 }

        var replaced = 0
        for index in pages.indices {
            let page = pages[index]
            guard !(page is ScaledProxyPage), page.rotation % 180 == 0 else { continue }
            let width = page.bounds(for: .cropBox).width
            guard width > typical * tolerance else { continue }
            document.removePage(at: index)
            document.insert(ScaledProxyPage(original: page, scale: typical / width), at: index)
            replaced += 1
        }
        return replaced
    }

    private static func restore(_ document: PDFDocument) -> Int {
        var restored = 0
        for index in 0..<document.pageCount {
            guard let proxy = document.page(at: index) as? ScaledProxyPage else { continue }
            document.removePage(at: index)
            document.insert(proxy.original, at: index)
            restored += 1
        }
        return restored
    }
}

final class ScaledProxyPage: PDFPage, @unchecked Sendable {
    let original: PDFPage
    private let scale: CGFloat
    private let sourceBox: CGRect

    init(original: PDFPage, scale: CGFloat) {
        self.original = original
        self.scale = scale
        sourceBox = original.bounds(for: .cropBox)
        super.init()
        setBounds(CGRect(x: 0, y: 0, width: sourceBox.width * scale, height: sourceBox.height * scale), for: .mediaBox)
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -sourceBox.minX, y: -sourceBox.minY)
        context.clip(to: sourceBox)
        // A page detached from its document cannot draw itself, so render the underlying PDF page directly.
        if let pageRef = original.pageRef {
            context.drawPDFPage(pageRef)
        } else {
            original.draw(with: .cropBox, to: context)
        }
        context.restoreGState()
    }
}

private final class ImagePageCache: @unchecked Sendable {
    static let shared = ImagePageCache()
    private let cache = NSCache<NSURL, CGImage>()

    private init() {
        cache.countLimit = 10
    }

    func image(for url: URL) -> CGImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4000,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
