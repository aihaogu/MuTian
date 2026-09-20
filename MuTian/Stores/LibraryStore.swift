import AppKit
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    private var isLoading = false
    @Published var books: [Book] = [] {
        didSet { save() }
    }
    @Published var roots: [LibraryRoot] = [] {
        didSet { save() }
    }
    @Published var classifications: [Classification] = ClassificationSeed.all
    @Published var selectedBookID: UUID?
    @Published var isBookDetailVisible: Bool = false
    @Published var sidebarSelection: SidebarSelection = .all
    @Published var searchText: String = ""
    @Published var isScanning: Bool = false
    @Published var lastImportMessage: String = ""

    init() {
        load()
    }

    var selectedBook: Book? {
        guard let selectedBookID else { return nil }
        return filteredBooks.first { $0.id == selectedBookID }
    }

    var sources: [String] {
        Array(Set(books.map(\.sourceName).filter { !$0.isEmpty })).sorted()
    }

    func classificationName(for id: String) -> String {
        guard let node = classifications.first(where: { $0.id == id }) else { return "未分类" }
        if let parentID = node.parentID, let parent = classifications.first(where: { $0.id == parentID }) {
            return "\(parent.name) / \(node.name)"
        }
        return node.name
    }

    func children(of parentID: String?) -> [Classification] {
        classifications
            .filter { $0.parentID == parentID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var filteredBooks: [Book] {
        var rows = books
        switch sidebarSelection {
        case .all:
            break
        case .favorites:
            rows = rows.filter(\.isFavorite)
        case .downloads, .statistics:
            break
        case .status(let status):
            rows = rows.filter { $0.status == status }
        case .classification(let id):
            rows = rows.filter { $0.classificationID == id || classificationDescendants(of: id).contains($0.classificationID) }
        case .source(let source):
            rows = rows.filter { $0.sourceName == source }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter { book in
                let haystack = [
                    book.title,
                    book.author,
                    book.dynasty,
                    book.edition,
                    book.sourceName,
                    book.localPath,
                    book.notes,
                    book.tags.joined(separator: " ")
                ].joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(query)
            }
        }

        return rows.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入古籍文件夹或 PDF"
        panel.message = "选择本地文件夹或 PDF 后导入到资料库。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            Task {
                await importURLs(panel.urls)
            }
        }
    }

    func importURLs(_ urls: [URL]) async {
        guard !urls.isEmpty, !isScanning else { return }
        let accessibleURLs = urls.filter { FileManager.default.isReadableFile(atPath: $0.path) }
        let unavailableCount = urls.count - accessibleURLs.count
        guard !accessibleURLs.isEmpty else {
            lastImportMessage = "文件或目录不可用，请重新定位；已有书目已保留。"
            return
        }
        isScanning = true
        lastImportMessage = "正在扫描 \(urls.count) 个路径..."

        let results = await Task.detached(priority: .userInitiated) {
            accessibleURLs.map { FolderScanner.scan(root: $0) }
        }.value

        var imported = 0
        var refreshed = 0
        var removed = 0
        var updatedBooks = books
        var updatedRoots = roots
        let requestedPaths = Set(results.filter(\.isComplete).map(\.scannedPath))

        for result in results {
            if !updatedRoots.contains(where: { $0.path == result.scannedPath }) {
                updatedRoots.append(.new(path: result.scannedPath))
            }

            for candidate in result.books {
                if let index = updatedBooks.firstIndex(where: { $0.localPath == candidate.localPath }) {
                    if mergeScannedBook(candidate, into: &updatedBooks[index]) {
                        refreshed += 1
                    }
                } else {
                    updatedBooks.append(candidate)
                    imported += 1
                }
            }

            let scannedPaths = Set(result.books.map(\.localPath))
            let beforePruneCount = updatedBooks.count
            if result.isComplete {
                updatedBooks.removeAll { book in
                    isPath(book.localPath, insideOrEqualTo: result.scannedPath) && !scannedPaths.contains(book.localPath)
                }
            }
            removed += beforePruneCount - updatedBooks.count
        }

        for index in updatedRoots.indices {
            if requestedPaths.contains(updatedRoots[index].path) {
                updatedRoots[index].lastScannedAt = Date()
            }
        }

        roots = updatedRoots
        books = updatedBooks
        isScanning = false
        lastImportMessage = "导入完成：新增 \(imported) 部，更新 \(refreshed) 部，移除失效条目 \(removed) 部。"
        if unavailableCount > 0 || results.contains(where: { !$0.isComplete }) {
            lastImportMessage += " 部分路径不可用，相关旧书目已保留。"
        }
        syncSelectionWithFilter()
    }

    func rescanKnownRoots() async {
        let urls = roots.map { URL(fileURLWithPath: $0.path) }
        await importURLs(urls)
    }

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        var updated = book
        updated.updatedAt = Date()
        books[index] = updated
    }

    func toggleFavorite(_ book: Book) {
        var edited = book
        edited.isFavorite.toggle()
        update(edited)
    }

    func updateReadProgress(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard books[index].lastReadPage != max(0, page) else { return }
        books[index].lastReadPage = max(0, page)
        books[index].lastReadAt = Date()
        books[index].updatedAt = Date()
    }

    func selectBook(_ book: Book) {
        selectedBookID = book.id
        isBookDetailVisible = true
    }

    func setBookDetailVisible(_ isVisible: Bool) {
        guard selectedBookID != nil || !isVisible else { return }
        isBookDetailVisible = isVisible
    }

    func revealInFinder(_ book: Book) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.localPath)])
    }

    func relocateFile(for book: Book) {
        let panel = NSOpenPanel()
        panel.title = book.fileType == .imageSequence ? "定位图片所在文件夹" : "定位原文件"
        panel.canChooseDirectories = book.fileType == .imageSequence
        panel.canChooseFiles = book.fileType != .imageSequence
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var snapshot = LibrarySnapshot(books: books, roots: roots)
        guard LibraryPathRepair.repair(&snapshot, from: URL(fileURLWithPath: book.localPath), to: url) > 0 else { return }
        do {
            let backup = AppPaths.supportDirectory.appendingPathComponent("library-before-relocation-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: AppPaths.libraryFile, to: backup)
        } catch {
            lastImportMessage = "无法备份资料库，未修改文件位置：\(error.localizedDescription)"
            return
        }
        isLoading = true
        books = snapshot.books
        roots = snapshot.roots
        isLoading = false
        save()
    }

    func countsByTopClassification() -> [(String, Int)] {
        let topNodes = children(of: nil).filter { $0.id != Classification.defaultUnclassifiedID }
        return topNodes.map { node in
            let ids = Set([node.id] + classificationDescendants(of: node.id))
            return (node.name, books.filter { ids.contains($0.classificationID) }.count)
        } + [("未分类", books.filter { $0.classificationID == Classification.defaultUnclassifiedID }.count)]
    }

    func syncSelectionWithFilter() {
        let rows = filteredBooks
        guard let selectedBookID else {
            return
        }
        if !rows.contains(where: { $0.id == selectedBookID }) {
            self.selectedBookID = nil
            isBookDetailVisible = false
        }
    }

    private func classificationDescendants(of id: String) -> [String] {
        let childIDs = classifications.filter { $0.parentID == id }.map(\.id)
        return childIDs + childIDs.flatMap { classificationDescendants(of: $0) }
    }

    private func mergeScannedBook(_ scanned: Book, into current: inout Book) -> Bool {
        var changed = false

        func fill(_ keyPath: WritableKeyPath<Book, String>, with value: String) {
            guard current[keyPath: keyPath].isEmpty, !value.isEmpty else { return }
            current[keyPath: keyPath] = value
            changed = true
        }

        if current.pageCount <= 0, scanned.pageCount > 0 {
            current.pageCount = scanned.pageCount
            changed = true
        }
        if current.classificationID == Classification.defaultUnclassifiedID,
           scanned.classificationID != Classification.defaultUnclassifiedID {
            current.classificationID = scanned.classificationID
            changed = true
        }
        fill(\.author, with: scanned.author)
        fill(\.dynasty, with: scanned.dynasty)
        fill(\.edition, with: scanned.edition)
        fill(\.sourceName, with: scanned.sourceName)
        fill(\.sourceURL, with: scanned.sourceURL)

        if scanned.fileType == .imageSequence,
           (current.pageRecords.isEmpty || current.pageRecords.count != scanned.pageRecords.count) {
            current.pageRecords = scanned.pageRecords
            current.pageCount = scanned.pageCount
            changed = true
        }

        if changed {
            current.updatedAt = Date()
        }
        return changed
    }

    private func isPath(_ path: String, insideOrEqualTo rootPath: String) -> Bool {
        if path == rootPath { return true }
        let normalizedRoot = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(normalizedRoot)
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile),
              var snapshot = try? JSONDecoder.muTian.decode(LibrarySnapshot.self, from: data) else {
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let changes = LibraryPathRepair.repair(&snapshot,
            from: home.appendingPathComponent("得古测试"),
            to: home.appendingPathComponent("木天测试"))
        if changes > 0 {
            let backup = AppPaths.supportDirectory.appendingPathComponent("library-before-path-repair-\(UUID().uuidString).json")
            do {
                try data.write(to: backup, options: [.atomic])
            } catch {
                snapshot = (try? JSONDecoder.muTian.decode(LibrarySnapshot.self, from: data)) ?? snapshot
                lastImportMessage = "路径修复前无法备份资料库：\(error.localizedDescription)"
            }
        }
        isLoading = true
        books = snapshot.books
        roots = snapshot.roots
        isLoading = false
        if changes > 0 { save() }
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = LibrarySnapshot(books: books, roots: roots)
        guard let data = try? JSONEncoder.muTian.encode(snapshot) else { return }
        try? data.write(to: AppPaths.libraryFile, options: [.atomic])
    }
}
