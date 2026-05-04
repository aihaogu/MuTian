import PDFKit
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let book: Book
    @State private var currentPage: Int

    init(book: Book) {
        self.book = book
        _currentPage = State(initialValue: max(0, book.lastReadPage))
    }

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()
            switch book.fileType {
            case .pdf:
                PDFReaderRepresentable(url: URL(fileURLWithPath: book.localPath), pageIndex: $currentPage)
                    .background(DeGuTheme.paper)
            case .imageSequence:
                ImageSequenceReader(book: book, currentPage: $currentPage)
            case .text, .mixedFolder:
                DetailPlaceholder(title: "暂不支持直接阅读", systemImage: "doc.text", message: "当前阅读器优先支持 PDF 和图片序列。")
            }
        }
        .background(DeGuTheme.paper)
        .onChange(of: currentPage) { _, newValue in
            libraryStore.updateReadProgress(bookID: book.id, page: newValue)
        }
    }

    private var readerToolbar: some View {
        HStack {
            Button {
                currentPage = max(0, currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("上一页")

            Stepper(value: $currentPage, in: 0...max(0, book.pageCount - 1)) {
                Text("第 \(min(currentPage + 1, max(book.pageCount, 1))) / \(max(book.pageCount, 1)) 页")
                    .frame(minWidth: 120, alignment: .leading)
            }
            .disabled(book.pageCount <= 0)

            Button {
                currentPage = min(max(0, book.pageCount - 1), currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("下一页")

            Spacer()

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
}

struct PDFReaderRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document == nil || view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
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
            .background(DeGuTheme.paper)
        }
    }

    private var currentImage: NSImage? {
        guard book.pageRecords.indices.contains(currentPage) else { return nil }
        return NSImage(contentsOfFile: book.pageRecords[currentPage].imagePath)
    }
}
