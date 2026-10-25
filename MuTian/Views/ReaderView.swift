import AppKit
import PDFKit
import SwiftUI
import WebKit
import Quartz

enum ReaderPresentation {
    case embedded
    case window
}

struct ReaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    let presentation: ReaderPresentation
    @State private var currentPage: Int
    @State private var effectivePageCount: Int?
    @State private var showsOutline: Bool
    @State private var hasPDFOutline = false
    @State private var effectiveScale = 1.0
    @AppStorage("reader.layout") private var pageLayout: ReaderPageLayout = .single
    @AppStorage("reader.continuous") private var continuousScroll = true
    @AppStorage("reader.rightToLeft") private var rightToLeft = false
    @AppStorage("reader.coverAlone") private var coverAlone = true
    @AppStorage("reader.zoomMode") private var zoomMode: ReaderZoomMode = .fitPage
    @AppStorage("reader.zoomScale") private var zoomScale = 1.0
    @AppStorage("reader.textScale") private var textScale = 1.0

    init(book: Book, presentation: ReaderPresentation = .embedded) {
        self.book = book
        self.presentation = presentation
        _currentPage = State(initialValue: max(0, book.lastReadPage))
        _showsOutline = State(initialValue: book.fileType == .ebook)
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
                    pagedReader(source: .pdf(URL(fileURLWithPath: book.localPath)))
                case .imageSequence:
                    pagedReader(source: .images(book.pageRecords))
                case .text:
                    TextFileReader(url: URL(fileURLWithPath: book.localPath), textScale: textScale)
                case .ebook:
                    if isEpubBook {
                        EpubReaderView(book: book, currentPage: $currentPage, chapterCount: $effectivePageCount,
                                       showsChapters: showsOutline, textScale: textScale)
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
        .onChange(of: hasPDFOutline) { _, hasOutline in
            if hasOutline { showsOutline = true }
        }
    }

    private func pagedReader(source: PagedReaderSource) -> some View {
        PagedReaderView(
            source: source,
            pageIndex: $currentPage,
            pageCount: $effectivePageCount,
            showsSidebar: showsOutline,
            hasOutline: $hasPDFOutline,
            options: displayOptions,
            onZoomChange: setZoom,
            effectiveScale: $effectiveScale
        )
    }

    private var displayOptions: ReaderDisplayOptions {
        ReaderDisplayOptions(
            layout: pageLayout,
            continuous: continuousScroll,
            rightToLeft: rightToLeft,
            coverAlone: coverAlone,
            zoom: ReaderZoom(mode: zoomMode, scale: zoomScale)
        )
    }

    private func setZoom(_ zoom: ReaderZoom) {
        if zoomMode != zoom.mode { zoomMode = zoom.mode }
        if zoomScale != zoom.scale { zoomScale = zoom.scale }
    }

    private var unsupportedReader: some View {
        VStack(spacing: 16) {
            DetailPlaceholder(title: "此格式需要外部阅读器", systemImage: "doc.text", message: "当前内置阅读器支持 PDF、图片、文本和 EPUB，Office 文档使用系统预览。此文件可用已安装的兼容应用打开。")
            Button("用默认应用打开") { NSWorkspace.shared.open(URL(fileURLWithPath: book.localPath)) }
        }
    }

    private var readerToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(compact: false)
            toolbarRow(compact: true)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private func toolbarRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            if supportsOutline {
                Button {
                    showsOutline.toggle()
                } label: {
                    Image(systemName: book.fileType == .imageSequence ? "sidebar.left" : "list.bullet.indent")
                        .foregroundStyle(showsOutline ? MuTianTheme.accent : .secondary)
                }
                .help(showsOutline ? "隐藏\(outlineName)" : "显示\(outlineName)")
            }

            Spacer()

            if supportsPaging {
                Button {
                    currentPage = max(0, min(currentPage, maxPageIndex) - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("上一\(readerUnitName)")
                .disabled(currentPage <= 0)

                Text("\(min(currentPage + 1, displayedPageCount)) / \(displayedPageCount) \(readerUnitName)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: compact ? 64 : 90)

                Button {
                    currentPage = min(maxPageIndex, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("下一\(readerUnitName)")
                .disabled(currentPage >= maxPageIndex)
            }

            Spacer()

            if supportsZoom {
                zoomControls(compact: compact)
            }
            if isPagedBook {
                pageLayoutPicker
                layoutMenu
            }
            windowButton
        }
    }

    // MARK: - Zoom & layout

    private var isPagedBook: Bool {
        book.fileType == .pdf || book.fileType == .imageSequence
    }

    private var supportsZoom: Bool {
        isPagedBook || isEpubBook || book.fileType == .text
    }

    private var displayedScale: Double {
        isPagedBook ? effectiveScale : textScale
    }

    @ViewBuilder
    private func zoomControls(compact: Bool) -> some View {
        HStack(spacing: 4) {
            if !compact {
                Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
                    .help("缩小")
                    .keyboardShortcut("-", modifiers: .command)
            }
            Menu {
                if isPagedBook {
                    zoomModeButton("适应窗口", mode: .fitPage)
                        .keyboardShortcut("9", modifiers: .command)
                    zoomModeButton("适应宽度", mode: .fitWidth)
                    Divider()
                }
                Button("实际大小") { setScale(1) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                ForEach(ReaderZoom.presets, id: \.self) { preset in
                    Button("\(Int((preset * 100).rounded()))%") { setScale(preset) }
                }
            } label: {
                Text("\(Int((displayedScale * 100).rounded()))%")
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(zoomHelp)
            if !compact {
                Button(action: zoomIn) { Image(systemName: "plus.magnifyingglass") }
                    .help("放大")
                    .keyboardShortcut("=", modifiers: .command)
            }
        }
    }

    private func zoomModeButton(_ title: String, mode: ReaderZoomMode) -> some View {
        Button {
            zoomMode = mode
        } label: {
            if zoomMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var zoomHelp: String {
        guard isPagedBook else { return "文字缩放" }
        switch zoomMode {
        case .fitPage: return "缩放：适应窗口"
        case .fitWidth: return "缩放：适应宽度"
        case .custom: return "缩放"
        }
    }

    private func zoomIn() { setScale(displayedScale * (isPagedBook ? 1.25 : 1.1)) }

    private func zoomOut() { setScale(displayedScale / (isPagedBook ? 1.25 : 1.1)) }

    private func setScale(_ scale: Double) {
        if isPagedBook {
            zoomScale = ReaderZoom.clamped(scale)
            zoomMode = .custom
        } else {
            textScale = min(max(scale, 0.5), 3)
        }
    }

    private var pageLayoutPicker: some View {
        Picker("页面", selection: $pageLayout) {
            ForEach(ReaderPageLayout.allCases) { layout in
                Image(systemName: layout.systemImage)
                    .help(layout.title)
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("单页 / 双页并排")
    }

    private var layoutMenu: some View {
        Menu {
            Picker("翻页", selection: $continuousScroll) {
                Text("连续滚动").tag(true)
                Text("分页").tag(false)
            }
            .pickerStyle(.inline)

            Divider()

            Toggle("从右向左排列", isOn: $rightToLeft)
            Toggle("封面单独显示", isOn: $coverAlone)
                .disabled(pageLayout != .twoUp)
        } label: {
            Image(systemName: continuousScroll ? "scroll" : "book.pages")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("翻页方式：\(continuousScroll ? "连续滚动" : "分页")")
    }

    private var supportsOutline: Bool {
        book.fileType == .imageSequence || isEpubBook || (book.fileType == .pdf && hasPDFOutline)
    }

    private var outlineName: String {
        book.fileType == .imageSequence ? "页码列表" : "目录"
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
    private var windowButton: some View {
        switch presentation {
        case .embedded:
            Button {
                openWindow(value: book.id)
            } label: {
                Image(systemName: "macwindow.badge.plus")
            }
            .help("在新窗口中阅读")
        case .window:
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("进入或退出全屏")
        }
    }
}

struct TextFileReader: View {
    let url: URL
    var textScale: Double = 1
    @State private var text: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    Text(text)
                        .font(.system(size: NSFont.systemFontSize * 1.1 * textScale, design: .serif))
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

struct EpubReaderView: View {
    let book: Book
    @Binding var currentPage: Int
    @Binding var chapterCount: Int?
    var showsChapters: Bool = true
    var textScale: Double = 1
    @State private var document: EpubDocument?
    @State private var errorMessage: String?
    @State private var anchor: EpubAnchor?
    @State private var selectedEntryID: String?

    var body: some View {
        Group {
            if let document {
                if document.chapters.isEmpty {
                    DetailPlaceholder(title: "没有可读章节", systemImage: "book.closed", message: "这个 EPUB 没有找到可阅读的 HTML/XHTML 章节。")
                } else {
                    HStack(spacing: 0) {
                        if showsChapters {
                            chapterList(document)
                            Divider()
                        }
                        chapterContent(document)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: currentPage) { _, newValue in
            if anchor?.chapter != newValue { anchor = nil }
        }
    }

    @ViewBuilder
    private func chapterList(_ document: EpubDocument) -> some View {
        if document.tableOfContents.isEmpty {
            List(selection: clampedChapterSelection(for: document)) {
                ForEach(document.chapters) { chapter in
                    Text(chapter.title)
                        .lineLimit(2)
                        .tag(chapter.id)
                }
            }
            .frame(width: 220)
            .scrollContentBackground(.hidden)
            .background(.bar)
        } else {
            ReaderOutlineSidebar(
                entries: document.tableOfContents,
                currentID: currentEntryID(in: document.tableOfContents),
                showsTargetNumbers: false
            ) { entry in
                selectedEntryID = entry.id
                anchor = EpubAnchor(chapter: entry.target, fragment: entry.fragment)
                currentPage = min(max(entry.target, 0), max(0, document.chapters.count - 1))
            }
        }
    }

    private func currentEntryID(in entries: [ReaderOutlineEntry]) -> String? {
        let flat = entries.flattened
        if let selectedEntryID, flat.first(where: { $0.id == selectedEntryID })?.target == currentPage {
            return selectedEntryID
        }
        return flat.first { $0.target == currentPage }?.id ?? entries.entry(atOrBefore: currentPage)?.id
    }

    @ViewBuilder
    private func chapterContent(_ document: EpubDocument) -> some View {
        if let chapter = selectedChapter(in: document) {
            EpubWebView(url: chapter.url, readAccessURL: document.rootDirectory,
                        anchor: anchor?.chapter == chapter.id ? anchor : nil, pageZoom: textScale)
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

/// A table-of-contents jump inside an EPUB chapter; a new token re-scrolls even to the same anchor.
struct EpubAnchor: Equatable {
    let chapter: Int
    let fragment: String?
    var token = UUID()
}

struct EpubWebView: NSViewRepresentable {
    let url: URL
    let readAccessURL: URL
    var anchor: EpubAnchor?
    var pageZoom: Double = 1

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if abs(view.pageZoom - pageZoom) > 0.001 { view.pageZoom = pageZoom }
        if coordinator.loadedURL != url {
            coordinator.loadedURL = url
            coordinator.pendingAnchor = anchor
            coordinator.appliedToken = anchor?.token
            view.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        } else if let anchor, coordinator.appliedToken != anchor.token {
            coordinator.appliedToken = anchor.token
            if coordinator.isLoading {
                coordinator.pendingAnchor = anchor
            } else {
                Coordinator.scroll(view, to: anchor)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var pendingAnchor: EpubAnchor?
        var appliedToken: UUID?
        var isLoading = false

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            if let anchor = pendingAnchor {
                pendingAnchor = nil
                Self.scroll(webView, to: anchor)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        static func scroll(_ webView: WKWebView, to anchor: EpubAnchor) {
            guard let fragment = anchor.fragment,
                  let data = try? JSONEncoder().encode(fragment),
                  let literal = String(data: data, encoding: .utf8) else {
                webView.evaluateJavaScript("window.scrollTo(0, 0)")
                return
            }
            webView.evaluateJavaScript("""
            (function(){var id=\(literal);var el=document.getElementById(id)||document.getElementsByName(id)[0];
            if(el){el.scrollIntoView({block:'start'});}else{window.scrollTo(0,0);}})()
            """)
        }
    }
}
