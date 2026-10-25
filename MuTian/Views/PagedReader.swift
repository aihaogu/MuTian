import AppKit
import ImageIO
import PDFKit
import SwiftUI

enum ReaderPageLayout: String, CaseIterable, Identifiable {
    case single
    case twoUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "单页"
        case .twoUp: "双页并排"
        }
    }

    var systemImage: String {
        switch self {
        case .single: "rectangle.portrait"
        case .twoUp: "rectangle.split.2x1"
        }
    }
}

enum ReaderZoomMode: String {
    case fitPage
    case fitWidth
    case custom
}

struct ReaderZoom: Equatable {
    var mode: ReaderZoomMode
    var scale: Double

    static let minScale = 0.1
    static let maxScale = 8.0
    static let presets: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    static func clamped(_ scale: Double) -> Double {
        min(max(scale, minScale), maxScale)
    }
}

struct ReaderDisplayOptions: Equatable {
    var layout: ReaderPageLayout
    var continuous: Bool
    var rightToLeft: Bool
    var coverAlone: Bool
    var zoom: ReaderZoom

    var displayMode: PDFDisplayMode {
        switch (layout, continuous) {
        case (.single, true): .singlePageContinuous
        case (.single, false): .singlePage
        case (.twoUp, true): .twoUpContinuous
        case (.twoUp, false): .twoUp
        }
    }
}

enum PagedReaderSource: Equatable {
    case pdf(URL)
    case images([PageRecord])

    var identity: String {
        switch self {
        case .pdf(let url):
            url.path
        case .images(let pages):
            "images|\(pages.count)|\(pages.first?.imagePath ?? "")|\(pages.last?.imagePath ?? "")"
        }
    }
}

/// PDFs and scanned image sequences share one PDFView, so zoom and page layouts behave identically.
struct PagedReaderView: View {
    let source: PagedReaderSource
    @Binding var pageIndex: Int
    @Binding var pageCount: Int?
    var showsSidebar: Bool
    @Binding var hasOutline: Bool
    let options: ReaderDisplayOptions
    let onZoomChange: (ReaderZoom) -> Void
    @Binding var effectiveScale: Double

    @State private var document: PDFDocument?
    @State private var outline: [ReaderOutlineEntry] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let document {
                HStack(spacing: 0) {
                    if showsSidebar {
                        sidebar(pageCount: document.pageCount)
                        Divider()
                    }
                    PagedDocumentView(
                        document: document,
                        pageIndex: $pageIndex,
                        options: options,
                        onZoomChange: onZoomChange,
                        effectiveScale: $effectiveScale
                    )
                }
            } else if let errorMessage {
                DetailPlaceholder(title: errorTitle, systemImage: "doc.richtext", message: errorMessage)
            } else {
                ProgressView(isImages ? "正在准备影像…" : "正在打开 PDF…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.paper)
        .task(id: source.identity) {
            await load()
        }
    }

    @ViewBuilder
    private func sidebar(pageCount: Int) -> some View {
        if isImages {
            List(selection: Binding(get: { pageIndex }, set: { if let value = $0 { pageIndex = value } })) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Text("\(index + 1)")
                        .monospacedDigit()
                        .tag(Optional(index))
                }
            }
            .frame(width: 76)
            .scrollContentBackground(.hidden)
            .background(.bar)
        } else if !outline.isEmpty {
            ReaderOutlineSidebar(
                entries: outline,
                currentID: outline.entry(atOrBefore: pageIndex)?.id,
                showsTargetNumbers: true
            ) { entry in
                pageIndex = entry.target
            }
        }
    }

    private var isImages: Bool {
        if case .images = source { return true }
        return false
    }

    private var errorTitle: String {
        isImages ? "无法读取影像" : "无法打开 PDF"
    }

    @MainActor
    private func load() async {
        document = nil
        outline = []
        hasOutline = false
        errorMessage = nil
        let source = source
        let result = await Task.detached(priority: .userInitiated) { () -> LoadedPagedDocument in
            switch source {
            case .pdf(let url):
                return LoadedPagedDocument(document: PDFDocument(url: url))
            case .images(let pages):
                return LoadedPagedDocument(document: ImageSequenceDocument.make(pages: pages))
            }
        }.value
        guard !Task.isCancelled else { return }

        guard let loaded = result.document, !loaded.isLocked, loaded.pageCount > 0 else {
            if isImages {
                errorMessage = "没有找到可读取的页面影像。文件可能已移动，请重新扫描资料库。"
            } else {
                errorMessage = result.document?.isLocked == true
                    ? "此 PDF 已加密，请先用“预览”解锁后再导入。"
                    : "无法解析这个 PDF。请检查文件是否完整、是否具有读取权限，或用“预览”检查原文件。"
            }
            return
        }
        pageCount = loaded.pageCount
        pageIndex = min(max(pageIndex, 0), loaded.pageCount - 1)
        if !isImages {
            outline = PDFOutlineReader.entries(from: loaded)
            hasOutline = !outline.isEmpty
        }
        document = loaded
    }
}

private struct LoadedPagedDocument: @unchecked Sendable {
    // Transfer ownership to the main actor after background loading completes.
    let document: PDFDocument?
}

struct PagedDocumentView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let options: ReaderDisplayOptions
    let onZoomChange: (ReaderZoom) -> Void
    @Binding var effectiveScale: Double

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ResizingPDFView {
        let view = ResizingPDFView()
        view.autoScales = false
        view.displayDirection = .vertical
        view.minScaleFactor = ReaderZoom.minScale
        view.maxScaleFactor = ReaderZoom.maxScale
        let coordinator = context.coordinator
        view.onResize = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.viewResized(view)
        }
        view.onUserMagnify = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.userMagnified(view)
        }
        let center = NotificationCenter.default
        center.addObserver(coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        center.addObserver(coordinator, selector: #selector(Coordinator.scaleChanged(_:)), name: .PDFViewScaleChanged, object: view)
        return view
    }

    func updateNSView(_ view: ResizingPDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        let changedDocument = view.document !== document
        if changedDocument { view.document = document }

        let changedOptions = changedDocument || coordinator.appliedOptions != options
        if changedOptions {
            let anchorIndex = view.currentPage.map { document.index(for: $0) }
            if changedDocument || coordinator.appliedOptions?.layout != options.layout {
                TwoUpPageNormalizer.apply(options.layout == .twoUp, to: document)
            }
            if view.displayMode != options.displayMode { view.displayMode = options.displayMode }
            view.displaysAsBook = options.layout == .twoUp && options.coverAlone
            view.displaysRTL = options.rightToLeft
            coordinator.appliedOptions = options
            coordinator.applyZoom(to: view)
            if !changedDocument, let anchorIndex, anchorIndex != NSNotFound, let page = document.page(at: anchorIndex) {
                view.go(to: page)
            }
        }

        let requested = min(max(0, pageIndex), max(0, document.pageCount - 1))
        guard changedDocument || coordinator.requestedPage != requested else { return }
        coordinator.requestedPage = requested
        if let page = document.page(at: requested), view.currentPage !== page {
            view.go(to: page)
        }
    }

    static func dismantleNSView(_ view: ResizingPDFView, coordinator: Coordinator) {
        view.onResize = nil
        view.onUserMagnify = nil
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PagedDocumentView
        var appliedOptions: ReaderDisplayOptions?
        var requestedPage: Int?
        var isUpdating = false

        init(parent: PagedDocumentView) { self.parent = parent }

        func applyZoom(to view: PDFView) {
            guard let options = appliedOptions else { return }
            let scale: Double
            switch options.zoom.mode {
            case .custom:
                scale = options.zoom.scale
            case .fitPage, .fitWidth:
                guard let fit = fitScales(for: view, options: options) else { return }
                scale = options.zoom.mode == .fitPage ? min(fit.width, fit.height) : fit.width
            }
            let clamped = ReaderZoom.clamped(scale)
            if abs(view.scaleFactor - clamped) > 0.0005 {
                view.scaleFactor = clamped
            }
            report(scale: clamped)
        }

        private func fitScales(for view: PDFView, options: ReaderDisplayOptions) -> (width: Double, height: Double)? {
            guard let page = view.currentPage ?? view.document?.page(at: 0) else { return nil }
            var size = page.bounds(for: view.displayBox).size
            if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
            guard size.width > 0, size.height > 0, view.bounds.width > 0, view.bounds.height > 0 else { return nil }

            let columns: CGFloat = options.layout == .twoUp ? 2 : 1
            let margins = view.displaysPageBreaks ? view.pageBreakMargins : NSEdgeInsetsZero
            let scroller = NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
            let availableWidth = view.bounds.width - scroller - (margins.left + margins.right) * columns - 12
            let availableHeight = view.bounds.height - (margins.top + margins.bottom) - 12
            return (
                width: max(0.01, availableWidth / (size.width * columns)),
                height: max(0.01, availableHeight / size.height)
            )
        }

        private func report(scale: Double) {
            let binding = parent.$effectiveScale
            DispatchQueue.main.async {
                if abs(binding.wrappedValue - scale) > 0.0005 { binding.wrappedValue = scale }
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? PDFView else { return }
            Task { @MainActor [weak self, weak view] in
                guard let self, let view, let page = view.currentPage, let document = view.document else { return }
                let index = document.index(for: page)
                guard index != NSNotFound else { return }
                self.requestedPage = index
                if self.parent.pageIndex != index { self.parent.pageIndex = index }
            }
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            report(scale: Double(view.scaleFactor))
        }

        func userMagnified(_ view: PDFView) {
            let scale = ReaderZoom.clamped(Double(view.scaleFactor))
            report(scale: scale)
            let zoom = ReaderZoom(mode: .custom, scale: scale)
            appliedOptions?.zoom = zoom
            let onZoomChange = parent.onZoomChange
            DispatchQueue.main.async { onZoomChange(zoom) }
        }

        func viewResized(_ view: PDFView) {
            guard let mode = appliedOptions?.zoom.mode, mode != .custom else { return }
            applyZoom(to: view)
        }
    }
}

final class ResizingPDFView: PDFView {
    var onResize: (() -> Void)?
    var onUserMagnify: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        if event.phase == .ended || event.phase == .cancelled || event.phase == [] { onUserMagnify?() }
    }

    override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
        DispatchQueue.main.async { [weak self] in self?.onUserMagnify?() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifyIfResized()
    }

    override func layout() {
        super.layout()
        notifyIfResized()
    }

    private func notifyIfResized() {
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0 else { return }
        lastSize = bounds.size
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}
