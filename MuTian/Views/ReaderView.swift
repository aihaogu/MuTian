import AppKit
import PDFKit
import SwiftUI
import WebKit
import Quartz

enum ReaderPresentation {
    case embedded
    case fullScreenWindow
}

struct ReaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    let presentation: ReaderPresentation
    @State private var currentPage: Int
    @State private var effectivePageCount: Int?

    init(book: Book, presentation: ReaderPresentation = .embedded) {
        self.book = book
        self.presentation = presentation
        _currentPage = State(initialValue: max(0, book.lastReadPage))
    }

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()
            if !FileManager.default.fileExists(atPath: book.localPath) {
                VStack(spacing: 16) {
                    DetailPlaceholder(title: "找不到原文件", systemImage: "folder.badge.questionmark", message: "文件或所在文件夹已移动，请重新定位。书目和阅读进度仍然保留。")
                    Button("重新定位文件") { libraryStore.relocateFile(for: book) }
                }
            } else {
                switch book.fileType {
                case .pdf:
                    PDFReaderView(url: URL(fileURLWithPath: book.localPath), pageIndex: $currentPage, pageCount: $effectivePageCount)
                case .imageSequence:
                    ImageSequenceReader(book: book, currentPage: $currentPage)
                case .text:
                    TextFileReader(url: URL(fileURLWithPath: book.localPath))
                case .ebook:
                    if isEpubBook {
                        EpubReaderView(book: book, currentPage: $currentPage, chapterCount: $effectivePageCount)
                    } else {
                        unsupportedReader
                    }
                case .document:
                    if ["doc", "docx", "ppt", "pptx", "rtf"].contains(URL(fileURLWithPath: book.localPath).pathExtension.lowercased()) {
                        SystemDocumentReader(url: URL(fileURLWithPath: book.localPath))
                    } else {
                        unsupportedReader
                    }
                case .archive, .mixedFolder:
                    unsupportedReader
                }
            }
        }
        .background(MuTianTheme.paper)
        .onChange(of: currentPage) { _, newValue in
            libraryStore.updateReadProgress(bookID: book.id, page: newValue)
        }
        .onChange(of: book.lastReadPage) { _, newValue in
            if currentPage != newValue { currentPage = max(0, newValue) }
        }
    }

    private var unsupportedReader: some View {
        VStack(spacing: 16) {
            DetailPlaceholder(title: "此格式需要外部阅读器", systemImage: "doc.text", message: "当前内置阅读器支持 PDF、图片、文本和 EPUB，Office 文档使用系统预览。此文件可用已安装的兼容应用打开。")
            Button("用默认应用打开") { NSWorkspace.shared.open(URL(fileURLWithPath: book.localPath)) }
        }
    }

    private var readerToolbar: some View {
        HStack {
            if supportsPaging {
                Button {
                    currentPage = max(0, min(currentPage, maxPageIndex) - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("上一页")
                .disabled(currentPage <= 0)

                Stepper(value: clampedCurrentPage, in: 0...maxPageIndex) {
                    Text("第 \(min(currentPage + 1, displayedPageCount)) / \(displayedPageCount) \(readerUnitName)")
                        .frame(minWidth: 120, alignment: .leading)
                }
                .disabled(displayedPageCount <= 1)

                Button {
                    currentPage = min(maxPageIndex, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("下一页")
                .disabled(currentPage >= maxPageIndex)
            } else if book.fileType == .text || book.fileType == .document {
                Text("连续阅读").foregroundStyle(.secondary)
            }

            Spacer()

            fullScreenButton

            Text(book.localPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var supportsPaging: Bool {
        book.fileType == .pdf || book.fileType == .imageSequence || isEpubBook
    }

    private var displayedPageCount: Int {
        max(effectivePageCount ?? book.pageCount, 1)
    }

    private var maxPageIndex: Int {
        max(0, displayedPageCount - 1)
    }

    private var readerUnitName: String {
        book.fileType == .ebook && isEpubBook ? "章" : "页"
    }

    private var isEpubBook: Bool {
        URL(fileURLWithPath: book.localPath).pathExtension.lowercased() == "epub"
    }

    @ViewBuilder
    private var fullScreenButton: some View {
        switch presentation {
        case .embedded:
            Button {
                openWindow(value: book.id)
            } label: {
                Label("全屏阅读", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .labelStyle(.iconOnly)
            .help("全屏阅读")
        case .fullScreenWindow:
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Label("退出全屏", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .labelStyle(.iconOnly)
            .help("退出全屏")
        }
    }

    private var clampedCurrentPage: Binding<Int> {
        Binding {
            min(max(currentPage, 0), maxPageIndex)
        } set: { newValue in
            currentPage = min(max(newValue, 0), maxPageIndex)
        }
    }
}

private struct LoadedPDF: @unchecked Sendable {
    // Transfer ownership to the main actor after background loading completes.
    let document: PDFDocument?
}

struct PDFReaderView: View {
    let url: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int?
    @State private var document: PDFDocument?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let document {
                PDFReaderRepresentable(document: document, pageIndex: $pageIndex)
            } else if let errorMessage {
                DetailPlaceholder(title: "无法打开 PDF", systemImage: "doc.richtext", message: errorMessage)
            } else {
                ProgressView("正在打开 PDF…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.paper)
        .task(id: url) {
            document = nil
            errorMessage = nil
            let source = url
            let result = await Task.detached(priority: .userInitiated) {
                LoadedPDF(document: PDFDocument(url: source))
            }.value
            guard !Task.isCancelled else { return }
            if let loaded = result.document, !loaded.isLocked, loaded.pageCount > 0 {
                pageCount = loaded.pageCount
                pageIndex = min(max(pageIndex, 0), loaded.pageCount - 1)
                document = loaded
            } else {
                errorMessage = result.document?.isLocked == true
                    ? "此 PDF 已加密，请先用“预览”解锁后再导入。"
                    : "无法解析这个 PDF。请检查文件是否完整、是否具有读取权限，或用“预览”检查原文件。"
            }
        }
    }
}

struct TextFileReader: View {
    let url: URL
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
            } else if let errorMessage {
                DetailPlaceholder(title: "无法读取文本", systemImage: "doc.text", message: errorMessage)
            } else {
                ProgressView("正在读取文本…")
            }
        }
        .background(MuTianTheme.paper)
        .task(id: url) {
            text = nil
            errorMessage = nil
            let source = url
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try TextFileLoader.load(from: source)
                }.value
                guard !Task.isCancelled else { return }
                text = loaded
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PDFReaderRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int

    func makeCoordinator() -> Coordinator { Coordinator(pageIndex: $pageIndex) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.pageIndex = $pageIndex
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }
        let changedDocument = view.document !== document
        if changedDocument { view.document = document }
        let requested = min(max(0, pageIndex), max(0, document.pageCount - 1))
        guard changedDocument || coordinator.requestedPage != requested else { return }
        coordinator.requestedPage = requested
        if let page = document.page(at: requested), view.currentPage !== page {
            view.go(to: page)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        var pageIndex: Binding<Int>
        var requestedPage: Int?
        var isUpdating = false

        init(pageIndex: Binding<Int>) { self.pageIndex = pageIndex }

        @objc func pageChanged(_ notification: Notification) {
            guard !isUpdating, let view = notification.object as? PDFView else { return }
            Task { @MainActor [weak self, weak view] in
                guard let self, let view, let page = view.currentPage, let document = view.document else { return }
                let index = document.index(for: page)
                guard index != NSNotFound else { return }
                self.requestedPage = index
                if self.pageIndex.wrappedValue != index { self.pageIndex.wrappedValue = index }
            }
        }
    }
}

struct SystemDocumentReader: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) != url as NSURL {
            view.previewItem = url as NSURL
        }
    }
}

struct ImageSequenceReader: View {
    let book: Book
    @Binding var currentPage: Int

    var body: some View {
        HSplitView {
            List(selection: $currentPage) {
                ForEach(book.pageRecords, id: \.pageIndex) { page in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text("\(page.pageIndex + 1)")
                    }
                    .tag(page.pageIndex)
                }
            }
            .frame(minWidth: 72, idealWidth: 96, maxWidth: 130)
            .scrollContentBackground(.hidden)
            .background(.bar)

            ScrollView([.horizontal, .vertical]) {
                if let image = currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DetailPlaceholder(title: "无法读取当前页", systemImage: "photo", message: "文件可能已移动，或当前页影像不可读。")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(MuTianTheme.paper)
        }
    }

    private var currentImage: NSImage? {
        guard let page = book.pageRecords.first(where: { $0.pageIndex == currentPage }) else { return nil }
        return NSImage(contentsOfFile: page.imagePath)
    }
}

struct EpubReaderView: View {
    let book: Book
    @Binding var currentPage: Int
    @Binding var chapterCount: Int?
    @State private var document: EpubDocument?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let document {
                if document.chapters.isEmpty {
                    DetailPlaceholder(title: "没有可读章节", systemImage: "book.closed", message: "这个 EPUB 没有找到可阅读的 HTML/XHTML 章节。")
                } else {
                    HSplitView {
                        chapterList(document)
                        chapterContent(document)
                    }
                }
            } else if let errorMessage {
                DetailPlaceholder(title: "无法打开 EPUB", systemImage: "book.closed", message: errorMessage)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在打开 EPUB...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MuTianTheme.paper)
            }
        }
        .task(id: book.localPath) {
            await loadDocument()
        }
    }

    private func chapterList(_ document: EpubDocument) -> some View {
        List(selection: clampedChapterSelection(for: document)) {
            ForEach(document.chapters) { chapter in
                Text(chapter.title)
                    .lineLimit(2)
                    .tag(chapter.id)
            }
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 300)
        .scrollContentBackground(.hidden)
        .background(.bar)
    }

    @ViewBuilder
    private func chapterContent(_ document: EpubDocument) -> some View {
        if let chapter = selectedChapter(in: document) {
            EpubWebView(url: chapter.url, readAccessURL: document.rootDirectory)
                .background(MuTianTheme.paper)
        } else {
            DetailPlaceholder(title: "请选择章节", systemImage: "list.bullet", message: "从左侧目录选择要阅读的章节。")
        }
    }

    @MainActor
    private func loadDocument() async {
        document = nil
        errorMessage = nil
        chapterCount = nil

        do {
            let url = URL(fileURLWithPath: book.localPath)
            let loaded = try await Task.detached(priority: .userInitiated) {
                try EpubArchive.load(from: url)
            }.value
            guard !Task.isCancelled else { return }
            document = loaded
            chapterCount = loaded.chapters.count
            currentPage = min(max(currentPage, 0), max(0, loaded.chapters.count - 1))
        } catch {
            guard !Task.isCancelled else { return }
            chapterCount = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func selectedChapter(in document: EpubDocument) -> EpubChapter? {
        let index = min(max(currentPage, 0), max(0, document.chapters.count - 1))
        return document.chapters.first { $0.id == index }
    }

    private func clampedChapterSelection(for document: EpubDocument) -> Binding<Int> {
        Binding {
            min(max(currentPage, 0), max(0, document.chapters.count - 1))
        } set: { newValue in
            currentPage = min(max(newValue, 0), max(0, document.chapters.count - 1))
        }
    }
}

struct EpubWebView: NSViewRepresentable {
    let url: URL
    let readAccessURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.loadFileURL(url, allowingReadAccessTo: readAccessURL)
    }

    final class Coordinator {
        var loadedURL: URL?
    }
}
