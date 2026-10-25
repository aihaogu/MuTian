import AppKit
import Foundation

@main
struct StoreRegressionChecks {
    @MainActor
    static func main() async {
        do { try await run() }
        catch { print("FAIL: \(error)"); exit(1) }
    }
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "StoreChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor
    static func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            if Date() > deadline { throw NSError(domain: "Timeout: \(message)", code: 1) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    @MainActor
    static func run() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("mutian-store-tests-\(UUID())")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try await testRecovery(base)
        try await testPages(base)
        try await testQueueAndDownloads(base)
        try await testRootRemoval(base)
        try testWriter(base)
        print("PASS: library protection/recovery, page identity/archive, queued imports, download states/defaults/logs, folder removal, persistence flush")
    }

    @MainActor
    static func testRootRemoval(_ base: URL) async throws {
        let fm = FileManager.default
        let outer = base.appendingPathComponent("roots-outer")
        let inner = outer.appendingPathComponent("inner")
        let other = base.appendingPathComponent("roots-other")
        for directory in [inner, other] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        let outerFile = outer.appendingPathComponent("outer.txt")
        let innerFile = inner.appendingPathComponent("inner.txt")
        let otherFile = other.appendingPathComponent("other.txt")
        for file in [outerFile, innerFile, otherFile] { try Data(file.lastPathComponent.utf8).write(to: file) }

        let file = base.appendingPathComponent("roots-library.json")
        let store = LibraryStore(libraryFile: file)
        await store.importURLs([outer, inner, other])
        try require(store.roots.count == 3 && store.books.count == 3, "Root fixture import failed")
        let outerRoot = store.roots.first { $0.path == outer.path }!
        let innerRoot = store.roots.first { $0.path == inner.path }!
        try require(store.bookCount(in: outerRoot) == 2, "Root book count must include nested files")

        try require(store.removeRoots([outerRoot.id]), "Removing a root failed")
        try require(store.roots.count == 2 && Set(store.books.map(\.localPath)) == [innerFile.path, otherFile.path],
            "Removing a root must keep books still covered by another root")
        try require(fm.fileExists(atPath: outerFile.path), "Removing a root must not touch files on disk")
        let backups = try fmContents(base).filter { $0.lastPathComponent.hasPrefix("library-before-folder-removal-") }
        try require(backups.count == 1, "Root removal must back up the index")

        try require(store.removeRoots([innerRoot.id]), "Removing the nested root failed")
        try require(store.books.map(\.localPath) == [otherFile.path], "Nested root books were not removed")
        try require(store.flush(), "Root removal not flushed")
        let reloaded = LibraryStore(libraryFile: file)
        try require(reloaded.roots.map(\.path) == [other.path] && reloaded.books.count == 1, "Root removal did not survive restart")
    }

    @MainActor
    static func testRecovery(_ base: URL) async throws {
        let file = base.appendingPathComponent("broken-library.json")
        let broken = Data("{broken-json".utf8)
        try broken.write(to: file)
        let store = LibraryStore(libraryFile: file)
        let input = base.appendingPathComponent("recovery-test.txt")
        try Data("fixture".utf8).write(to: input)
        let imported = await store.importURLs([input])
        try require(store.loadError != nil && imported.bookIDs.isEmpty, "Corrupt library must block import")
        try require(store.flush(), "Protected library flush")
        try require(try Data(contentsOf: file) == broken, "Corrupt original must remain untouched")
        let invalidBackup = base.appendingPathComponent("invalid-backup.json")
        try broken.write(to: invalidBackup)
        do { try store.restore(from: invalidBackup); throw NSError(domain: "Accepted invalid backup", code: 1) }
        catch is DecodingError { }
        try require(try Data(contentsOf: file) == broken, "Invalid recovery changed original")
        let backup = base.appendingPathComponent("good-backup.json")
        var book = Book.new(title: "preserved", localPath: input.path, fileType: .text, pageCount: 0)
        book.notes = "must survive"; book.isFavorite = true
        try JSONEncoder.muTian.encode(LibrarySnapshot(books: [book], roots: [])).write(to: backup)
        try store.restore(from: backup)
        try require(store.loadError == nil && store.books.first?.id == book.id && store.books.first?.notes == book.notes && store.books.first?.isFavorite == true, "Valid backup restoration failed")
        let preserved = try fmContents(base).filter { $0.lastPathComponent.hasPrefix("library-before-recovery-") }
        try require(preserved.count == 1, "Recovery must preserve damaged original")
        try require(try Data(contentsOf: preserved[0]) == broken, "Wrong preserved original")
    }

    @MainActor
    static func testPages(_ base: URL) async throws {
        let fm = FileManager.default
        let directory = base.appendingPathComponent("images")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["01.jpg", "02.jpg"] { try Data(name.utf8).write(to: directory.appendingPathComponent(name)) }
        let file = base.appendingPathComponent("pages-library.json")
        let store = LibraryStore(libraryFile: file)
        await store.importURLs([directory])
        var book = store.books[0]
        book.pageRecords[0].notes = "note"; book.pageRecords[0].ocrText = "OCR"
        book.pageRecords[0].correctedText = "corrected"
        let pageID = book.pageRecords[0].id
        store.update(book)
        try fm.moveItem(at: directory.appendingPathComponent("01.jpg"), to: directory.appendingPathComponent("03.jpg"))
        await store.importURLs([directory])
        let renamed = store.books[0].pageRecords.first { $0.id == pageID }
        try require(renamed?.notes == "note" && renamed?.imagePath.hasSuffix("03.jpg") == true, "Rename lost annotations or kept stale path")
        try require(store.books[0].lastReadPage == 1, "Rename/reorder changed the reading page")
        try Data("new".utf8).write(to: directory.appendingPathComponent("04.jpg"))
        await store.importURLs([directory])
        try require(store.books[0].pageRecords.count == 3, "New page missing")
        try require(store.books[0].pageRecords.allSatisfy { $0.bookID == book.id }, "Page bookID mismatch")
        let held = base.appendingPathComponent("held-image.jpg")
        try fm.moveItem(at: directory.appendingPathComponent("03.jpg"), to: held)
        await store.importURLs([directory])
        try require(store.books[0].archivedPageRecords?.first?.notes == "note", "Removed page annotation was destroyed")
        try fm.moveItem(at: held, to: directory.appendingPathComponent("05.jpg"))
        await store.importURLs([directory])
        try require(store.books[0].pageRecords.first { $0.id == pageID }?.correctedText == "corrected", "Reappeared page did not recover")
        // Old snapshots without file identities still preserve annotations by path.
        book = store.books[0]
        for i in book.pageRecords.indices { book.pageRecords[i].fileIdentity = nil }
        store.update(book)
        await store.importURLs([directory])
        try require(store.books[0].pageRecords.first { $0.id == pageID }?.ocrText == "OCR", "Legacy page merge lost OCR")
        try require(store.flush(), "Page changes not flushed")
        let reloaded = LibraryStore(libraryFile: file)
        try require(reloaded.books[0].pageRecords == store.books[0].pageRecords && reloaded.books[0].id == store.books[0].id, "Page changes did not survive restart")
    }

    @MainActor
    static func testQueueAndDownloads(_ base: URL) async throws {
        let fm = FileManager.default
        let root = base.appendingPathComponent("downloads-test")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("old.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("old".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let library = LibraryStore(libraryFile: root.appendingPathComponent("library.json"), scanner: { url in
            Thread.sleep(forTimeInterval: 0.15)
            return FolderScanner.scan(root: url)
        })
        async let one = library.importURLs([first])
        async let two = library.importURLs([second])
        let results = await (one, two)
        try require(results.0.bookIDs.count == 1 && results.1.bookIDs.count == 1 && library.books.count == 2, "Queued import discarded a request")
        let file = root.appendingPathComponent("downloads.json")
        let store = DownloadTaskStore(downloadsFile: file)
        let settings = AppSettings(databaseDirectory: root.path, defaultDownloadDirectory: root.path,
            bookgetExecutablePath: "", defaultThreads: 4, defaultConcurrent: 7, defaultRetries: 6, defaultSleepSeconds: 2)
        store.addDraft(settings: settings)
        var task = store.tasks[0]
        try require(task.threads == 4 && task.concurrent == 7 && task.retries == 6 && task.sleepSeconds == 2, "New task ignored settings")
        task.url = "success"; store.update(task)
        let engine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fake_bookget.py").path
        async let scan = library.importURLs([first])
        try await waitFor("scanner started") { library.isScanning }
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        _ = await scan
        try await waitFor("import result") { store.tasks[0].status == .imported || store.tasks[0].status == .failed }
        try require(store.tasks[0].status == .imported, "Successful download not imported: \(store.tasks[0].stderrLog)")
        let imported = library.books.first { $0.id == store.tasks[0].importedBookID }
        try require(imported?.localPath.hasSuffix("download.txt") == true && imported?.localPath != first.path, "Download linked to an old book")
        task = store.tasks[0]; task.url = "sleep"; store.update(task)
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        try await waitFor("child ready") { store.tasks[0].stdoutLog.contains("READY") }
        store.cancel(taskID: task.id)
        try await Task.sleep(for: .milliseconds(400))
        try require(store.tasks[0].status == .cancelled, "Exit callback overwrote cancellation")
        // Retry before the old process exits; stale callbacks must not own the new run.
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        try await waitFor("second child ready") { store.tasks[0].stdoutLog.contains("READY") }
        store.cancel(taskID: task.id)
        task = store.tasks[0]; task.url = "flood"; store.update(task)
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        try await waitFor("flood done") { store.tasks[0].status == .imported || store.tasks[0].status == .failed }
        try await Task.sleep(for: .milliseconds(350))
        try require(store.tasks[0].status == .imported, "Old callback corrupted retry")
        try require(store.tasks[0].stdoutLog.contains("FINAL-LOG-LINE") && store.tasks[0].stdoutLog.count <= 32_768, "Log tail missing or unbounded")
        try require(store.flush(), "Download snapshot/log flush failed")
        let persisted = try JSONDecoder.muTian.decode([DownloadTask].self, from: Data(contentsOf: file))
        try require(persisted[0].stdoutLog.isEmpty && persisted[0].stderrLog.isEmpty, "Logs still embedded in JSON")
        let reload = DownloadTaskStore(downloadsFile: file)
        try require(reload.tasks[0].stdoutLog.contains("FINAL-LOG-LINE"), "Separate log not restored")
        try require(reload.flush(), "Reload flush")
        task = store.tasks[0]; task.url = "empty"; store.update(task)
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        try await waitFor("empty result rejected") { store.tasks[0].status != .running }
        try require(store.tasks[0].status == .failed && store.tasks[0].importedBookID == nil, "Exit zero without result falsely imported old book")
        task = store.tasks[0]; task.url = "sleep"; store.update(task)
        store.run(taskID: task.id, bookgetPath: engine, libraryStore: library)
        try await waitFor("shutdown fixture") { store.tasks[0].stdoutLog.contains("READY") }
        try require(store.shutdown(), "Shutdown flush failed")
        try require(store.tasks[0].status == .interrupted, "Shutdown did not mark interrupted")
        let legacyFile = root.appendingPathComponent("legacy-downloads.json")
        task.status = .running
        try JSONEncoder.muTian.encode([task]).write(to: legacyFile)
        let legacy = DownloadTaskStore(downloadsFile: legacyFile)
        try require(legacy.tasks[0].status == .interrupted && !legacy.hasRunningTasks, "Restart retained phantom running task")
        try require(legacy.flush() && library.flush(), "Final flush failed")
    }

    static func testWriter(_ base: URL) throws {
        let file = base.appendingPathComponent("writer.json")
        let writer = SnapshotWriter<[Int]>(url: file)
        for value in 0..<100 { writer.schedule([value]) }
        try writer.flush()
        let result = try JSONDecoder().decode([Int].self, from: Data(contentsOf: file))
        try require(result == [99], "Flush lost the newest debounced snapshot")
        let absent = base.appendingPathComponent("absent/state.json")
        let retry = SnapshotWriter<[Int]>(url: absent)
        retry.schedule([42])
        do { try retry.flush(); throw NSError(domain: "Expected write failure", code: 1) }
        catch is CocoaError { }
        try FileManager.default.createDirectory(at: absent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try retry.flush()
        try require(try JSONDecoder().decode([Int].self, from: Data(contentsOf: absent)) == [42], "Failed save not retryable")
        let logDirectory = base.appendingPathComponent("retry-logs")
        try Data("blocked by a file".utf8).write(to: logDirectory)
        let logs = DownloadLogStore(directory: logDirectory)
        let id = UUID()
        logs.append("recoverable log", id: id, stderr: false)
        try require(logs.flush() != nil, "Expected log write error")
        try FileManager.default.removeItem(at: logDirectory)
        try require(logs.flush() == nil && logs.tail(id: id, stderr: false) == "recoverable log", "Failed log not retryable")
        logs.append(String(repeating: "x", count: 3 * 1024 * 1024) + "END", id: id, stderr: false)
        try require(logs.flush() == nil, "Log rotation failed")
        let logFile = logDirectory.appendingPathComponent("\(id)-stdout.log")
        try require(try Data(contentsOf: logFile).count <= 2 * 1024 * 1024 && logs.tail(id: id, stderr: false).hasSuffix("END"), "Log rotation exceeded cap or lost tail")
    }
    static func fmContents(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}
