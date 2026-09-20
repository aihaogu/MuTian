import AppKit
import PDFKit
import SwiftUI
import WebKit

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
            switch book.fileType {
            case .pdf:
                PDFReaderView(url: URL(fileURLWithPath: book.localPath), pageIndex: $currentPage)
            case .imageSequence:
                ImageSequenceReader(book: book, currentPage: $currentPage)
            case .text:
                TextFileReader(url: URL(fileURLWithPath: book.localPath))
            case .ebook:
                if isEpubBook {
                    EpubReaderView(book: book, currentPage: $currentPage, chapterCount: $effectivePageCount)
                } else {
                    DetailPlaceholder(title: "暂不支持直接阅读", systemImage: "doc.text", message: "当前电子书阅读器支持 EPUB。")
                }
            case .document, .archive, .mixedFolder:
                DetailPlaceholder(title: "暂不支持直接阅读", systemImage: "doc.text", message: "当前阅读器支持 PDF、图片序列、纯文本和 EPUB。")
            }
        }
        .background(MuTianTheme.paper)
        .onChange(of: currentPage) { _, newValue in
            libraryStore.updateReadProgress(bookID: book.id, page: newValue)
        }
    }

    private var readerToolbar: some View {
        HStack {
            Button {
                currentPage = max(0, min(currentPage, maxPageIndex) - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("上一页")
            .disabled(displayedPageCount <= 1)

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
            .disabled(displayedPageCount <= 1)

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

struct PDFReaderView: View {
    let url: URL
    @Binding var pageIndex: Int
    private let document: PDFDocument?

    init(url: URL, pageIndex: Binding<Int>) {
        self.url = url
        _pageIndex = pageIndex
        document = PDFDocument(url: url)
    }

    var body: some View {
        if let document, document.pageCount > 0 {
            PDFReaderRepresentable(document: document, pageIndex: $pageIndex)
                .background(MuTianTheme.paper)
        } else {
            DetailPlaceholder(
                title: "无法直接预览 PDF",
                systemImage: "doc.richtext",
                message: "该文件页数已记录，但 macOS PDFKit 无法渲染它。可先在 Finder 中打开原文件。"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MuTianTheme.paper)
        }
    }
}

struct TextFileReader: View {
    let url: URL

    var body: some View {
        ScrollView {
            Text(fileText)
                .font(.system(.body, design: .serif))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(MuTianTheme.paper)
    }

    private var fileText: String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .unicode) {
            return text
        }
        return "无法读取文本内容。"
    }
}

struct PDFReaderRepresentable: NSViewRepresentable {
    let document: PDFDocument
    @Binding var pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        guard let page = view.document?.page(at: pageIndex) else { return }
        if view.currentPage != page {
            view.go(to: page)
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
        guard book.pageRecords.indices.contains(currentPage) else { return nil }
        return NSImage(contentsOfFile: book.pageRecords[currentPage].imagePath)
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
        .task(id: book.id) {
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
            document = loaded
            chapterCount = loaded.chapters.count
            currentPage = min(max(currentPage, 0), max(0, loaded.chapters.count - 1))
        } catch {
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
