import Foundation

@MainActor
final class DownloadTaskStore: ObservableObject {
    @Published var tasks: [DownloadTask] = [] { didSet { save() } }
    @Published var selectedTaskID: UUID?
    @Published private(set) var parsingTaskIDs: Set<UUID> = []
    @Published private(set) var persistenceError: String?
    private let downloadsFile: URL
    private let logs: DownloadLogStore
    private var isLoading = false
    private var loadFailed = false
    private var runningProcesses: [UUID: Process] = [:]
    private var runTokens: [UUID: UUID] = [:]
    private var probeTokens: [UUID: UUID] = [:]
    private lazy var writer = SnapshotWriter<[DownloadTask]>(url: downloadsFile) { [weak self] error in
        Task { @MainActor [weak self] in self?.persistenceError = error }
    }

    init(downloadsFile: URL? = nil) {
        let file = downloadsFile ?? AppPaths.downloadsFile
        self.downloadsFile = file
        logs = DownloadLogStore(directory: file.deletingLastPathComponent().appendingPathComponent("download-logs"))
        load()
    }

    var selectedTask: DownloadTask? {
        tasks.first { $0.id == selectedTaskID }
    }
    var hasRunningTasks: Bool { !runningProcesses.isEmpty }

    func addDraft(settings: AppSettings) {
        guard !loadFailed else { return }
        let task = DownloadTask.draft(outputDirectory: settings.defaultDownloadDirectory,
            threads: settings.defaultThreads, concurrent: settings.defaultConcurrent,
            retries: settings.defaultRetries, sleepSeconds: settings.defaultSleepSeconds)
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
    }

    func update(_ task: DownloadTask) {
        guard !loadFailed, runningProcesses[task.id] == nil, !isParsing(taskID: task.id),
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    func isParsing(taskID: UUID) -> Bool { parsingTaskIDs.contains(taskID) }

    func probe(taskID: UUID, bookgetPath: String) {
        guard !loadFailed, let task = tasks.first(where: { $0.id == taskID }),
              !isParsing(taskID: taskID), runningProcesses[taskID] == nil else { return }
        guard validate(task: task, executable: bookgetPath) else { return }
        let token = UUID()
        probeTokens[taskID] = token
        parsingTaskIDs.insert(taskID)
        appendLog("\n正在解析链接…\n", to: taskID)
        let operation = Task.detached(priority: .userInitiated) {
            runProbeProcess(executable: URL(fileURLWithPath: bookgetPath), url: task.url, mode: task.mode)
        }
        Task { [weak self] in
            let result = await operation.value
            guard let self, self.probeTokens[taskID] == token else { return }
            self.probeTokens[taskID] = nil
            self.parsingTaskIDs.remove(taskID)
            if !result.stderr.isEmpty { self.appendLog(result.stderr, to: taskID, stderr: true) }
            guard result.exitCode == 0 else {
                self.appendLog("\n解析失败，退出码：\(result.exitCode)\n", to: taskID, stderr: true)
                return
            }
            do {
                let info = try JSONDecoder().decode(DownloadProbeInfo.self, from: Data(result.stdout.utf8))
                guard let index = self.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                self.tasks[index].parsedTitle = info.title.isEmpty ? nil : info.title
                self.tasks[index].parsedVolumeCount = info.volumeCount
                self.appendLog("解析完成：\(info.title)，\(info.volumeCount) 册\n", to: taskID)
            } catch { self.appendLog("解析结果读取失败：\(error.localizedDescription)\n", to: taskID, stderr: true) }
        }
    }

    private func validate(task: DownloadTask, executable: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            appendLog("下载引擎不可用，请在设置中选择 bookget 可执行文件。\n", to: task.id, stderr: true)
            return false
        }
        guard !task.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog("URL 不能为空。\n", to: task.id, stderr: true)
            return false
        }
        return true
    }

    func run(taskID: UUID, bookgetPath: String, libraryStore: LibraryStore) {
        guard !loadFailed, runningProcesses[taskID] == nil, !isParsing(taskID: taskID),
              let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var task = tasks[index]
        guard validate(task: task, executable: bookgetPath) else {
            tasks[index].status = .failed
            return
        }
        guard !task.outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog("输出目录不能为空。\n", to: taskID, stderr: true)
            tasks[index].status = .failed
            return
        }
        let token = UUID()
        let directory = URL(fileURLWithPath: (task.outputDirectory as NSString).expandingTildeInPath)
            .appendingPathComponent("task-\(taskID)", isDirectory: true).standardizedFileURL
        let report = downloadsFile.deletingLastPathComponent().appendingPathComponent("download-results/\(token).json")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch {
            appendLog("无法创建下载目录：\(error.localizedDescription)\n", to: taskID, stderr: true)
            tasks[index].status = .failed
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bookgetPath)
        process.arguments = buildArguments(for: task, directory: directory, report: report)
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        task.status = .running
        task.startedAt = Date()
        task.finishedAt = nil
        task.importedBookID = nil
        task.importedBookIDs = nil
        task.stdoutLog = ""
        task.stderrLog = ""
        tasks[index] = task
        runTokens[taskID] = token
        runningProcesses[taskID] = process
        appendLog("\n开始下载：\(task.url)\n保存到：\(directory.path)\n", to: taskID)
        flush()
        do {
            try process.run()
            // Drain both pipes concurrently and finish only after EOF. This avoids
            // pipe-buffer deadlocks and losing the final result/error messages.
            let group = DispatchGroup()
            for (pipe, isError) in [(output, false), (errors, true)] {
                group.enter()
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    var buffer = Data()
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of: 10) {
                            let line = String(decoding: buffer[...newline], as: UTF8.self)
                            buffer.removeSubrange(...newline)
                            Task { @MainActor [weak self] in
                                guard self?.runTokens[taskID] == token else { return }
                                self?.appendLog(line, to: taskID, stderr: isError)
                            }
                        }
                        if buffer.count > 65_536 {
                            let text = String(decoding: buffer, as: UTF8.self)
                            buffer.removeAll(keepingCapacity: true)
                            Task { @MainActor [weak self] in
                                guard self?.runTokens[taskID] == token else { return }
                                self?.appendLog(text, to: taskID, stderr: isError)
                            }
                        }
                    }
                    if !buffer.isEmpty {
                        let text = String(decoding: buffer, as: UTF8.self)
                        Task { @MainActor [weak self] in
                            guard self?.runTokens[taskID] == token else { return }
                            self?.appendLog(text, to: taskID, stderr: isError)
                        }
                    }
                    try? pipe.fileHandleForReading.close()
                    group.leave()
                }
            }
            DispatchQueue.global(qos: .utility).async { [weak self, weak libraryStore] in
                process.waitUntilExit()
                group.wait()
                Task { @MainActor [weak self, weak libraryStore] in
                    await self?.finish(taskID: taskID, token: token, exitCode: process.terminationStatus,
                        report: report, directory: directory, libraryStore: libraryStore)
                }
            }
        } catch {
            runningProcesses[taskID] = nil
            runTokens[taskID] = nil
            tasks[index].status = .failed
            tasks[index].finishedAt = Date()
            appendLog("启动失败：\(error.localizedDescription)\n", to: taskID, stderr: true)
        }
    }

    func cancel(taskID: UUID) {
        runTokens[taskID] = nil
        let process = runningProcesses.removeValue(forKey: taskID)
        if process?.isRunning == true { process?.terminate() }
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
        tasks[index].finishedAt = Date()
        flush()
    }

    func delete(taskID: UUID) {
        cancel(taskID: taskID)
        probeTokens[taskID] = nil
        parsingTaskIDs.remove(taskID)
        tasks.removeAll { $0.id == taskID }
        logs.remove(id: taskID)
        if selectedTaskID == taskID { selectedTaskID = tasks.first?.id }
    }

    private func buildArguments(for task: DownloadTask, directory: URL, report: URL) -> [String] {
        var args = ["--input", task.url.trimmingCharacters(in: .whitespacesAndNewlines),
            "--dir", directory.path, "--result-file", report.path,
            "--downloader_mode", "\(task.mode)", "--format", task.format, "--ext", task.fileExt,
            "--threads", "\(task.threads)", "--concurrent", "\(task.concurrent)",
            "--retries", "\(task.retries)", "--timeout", "\(task.timeoutSeconds)", "--sleep", "\(task.sleepSeconds)"]
        if !task.sequenceRange.isEmpty { args += ["--sequence", task.sequenceRange] }
        if !task.volumeRange.isEmpty { args += ["--volume", task.volumeRange] }
        return args
    }

    private func appendLog(_ text: String, to taskID: UUID, stderr: Bool = false) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        logs.append(text, id: taskID, stderr: stderr)
        isLoading = true // Log updates do not rewrite the task snapshot.
        if stderr { tasks[index].stderrLog = String((tasks[index].stderrLog + text).suffix(32_768)) }
        else { tasks[index].stdoutLog = String((tasks[index].stdoutLog + text).suffix(32_768)) }
        isLoading = false
    }

    private func finish(taskID: UUID, token: UUID, exitCode: Int32, report: URL,
                        directory: URL, libraryStore: LibraryStore?) async {
        defer { try? FileManager.default.removeItem(at: report) }
        guard runTokens[taskID] == token,
              let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        runningProcesses[taskID] = nil
        tasks[index].finishedAt = Date()
        guard exitCode == 0 else {
            tasks[index].status = .failed
            appendLog("下载失败（退出码 \(exitCode)）；重新开始会校验并跳过已完成文件。\n", to: taskID, stderr: true)
            flush()
            return
        }
        do {
            let result = try JSONDecoder().decode(DownloadResultManifest.self, from: Data(contentsOf: report))
            let paths = try result.validatedDirectories(inside: directory)
            tasks[index].status = .completed
            flush()
            if let libraryStore {
                let imported = await libraryStore.importURLs(paths) { [weak self] in
                    self?.runTokens[taskID] == token
                }
                guard runTokens[taskID] == token,
                      let current = tasks.firstIndex(where: { $0.id == taskID }) else { return }
                if !imported.bookIDs.isEmpty && libraryStore.flush() {
                    tasks[current].importedBookIDs = imported.bookIDs
                    tasks[current].importedBookID = imported.bookIDs.first
                    tasks[current].status = .imported
                } else {
                    appendLog("下载完成，未导入书目；请检查资料库错误提示后手动导入下载目录。\n", to: taskID, stderr: true)
                }
            }
        } catch {
            if let current = tasks.firstIndex(where: { $0.id == taskID }) { tasks[current].status = .failed }
            appendLog("下载结果校验失败：\(error.localizedDescription)\n", to: taskID, stderr: true)
        }
        flush()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: downloadsFile.path) else { return }
        do {
            var decoded = try JSONDecoder.muTian.decode([DownloadTask].self, from: Data(contentsOf: downloadsFile))
            for index in decoded.indices {
                let id = decoded[index].id
                // Migrate legacy inline logs once, before removing them from JSON.
                if !decoded[index].stdoutLog.isEmpty { logs.append(decoded[index].stdoutLog, id: id, stderr: false) }
                if !decoded[index].stderrLog.isEmpty { logs.append(decoded[index].stderrLog, id: id, stderr: true) }
                decoded[index].stdoutLog = logs.tail(id: id, stderr: false)
                decoded[index].stderrLog = logs.tail(id: id, stderr: true)
                if decoded[index].status == .running {
                    decoded[index].status = .interrupted
                    decoded[index].finishedAt = Date()
                }
            }
            if let error = logs.flush() {
                throw NSError(domain: "DownloadLogMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            isLoading = true
            tasks = decoded
            isLoading = false
            save()
        } catch {
            loadFailed = true
            persistenceError = "下载记录无法读取，原文件已保护：\(error.localizedDescription)"
        }
    }

    private func save() {
        guard !isLoading, !loadFailed else { return }
        writer.schedule(tasks.map { task in
            var snapshot = task
            snapshot.stdoutLog = ""
            snapshot.stderrLog = ""
            return snapshot
        })
    }

    @discardableResult
    func flush() -> Bool {
        if loadFailed { return true }
        if let error = logs.flush() { persistenceError = error; return false }
        do { try writer.flush(); persistenceError = nil; return true }
        catch { persistenceError = "下载记录保存失败：\(error.localizedDescription)"; return false }
    }

    func shutdown() -> Bool {
        for (id, process) in runningProcesses {
            runTokens[id] = nil
            if process.isRunning { process.terminate() }
            if let index = tasks.firstIndex(where: { $0.id == id }) {
                tasks[index].status = .interrupted
                tasks[index].finishedAt = Date()
            }
        }
        runningProcesses.removeAll()
        return flush()
    }
}

struct DownloadResultManifest: Decodable {
    let version: Int
    let saved: Int
    let skipped: Int
    let failed: Int
    let files: [String]
    let output_directories: [String]

    func validatedDirectories(inside root: URL) throws -> [URL] {
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let directories = output_directories.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        let fileURLs = files.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        guard version == 1, failed == 0, saved >= 0, skipped >= 0, saved + skipped > 0,
              files.count == saved + skipped, !directories.isEmpty,
              directories.allSatisfy({ $0.path.hasPrefix(prefix) }),
              fileURLs.allSatisfy({ $0.path.hasPrefix(prefix) && FileManager.default.isReadableFile(atPath: $0.path) }),
              Set(directories) == Set(fileURLs.map { $0.deletingLastPathComponent() }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return directories
    }
}

private struct ProbeProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
private struct DownloadProbeInfo: Decodable {
    let title: String
    let volumeCount: Int
    enum CodingKeys: String, CodingKey { case title; case volumeCount = "volume_count" }
}
private func runProbeProcess(executable: URL, url: String, mode: Int) -> ProbeProcessResult {
    let process = Process()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mutian-probe-\(UUID())")
    defer { try? FileManager.default.removeItem(at: temporary) }
    do {
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let stdout = temporary.appendingPathComponent("stdout"), stderr = temporary.appendingPathComponent("stderr")
        try Data().write(to: stdout); try Data().write(to: stderr)
        let output = try FileHandle(forWritingTo: stdout), errors = try FileHandle(forWritingTo: stderr)
        defer { try? output.close(); try? errors.close() }
        process.executableURL = executable
        process.arguments = ["--probe", "--input", url, "--downloader_mode", "\(mode)"]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        return ProbeProcessResult(exitCode: process.terminationStatus,
            stdout: String(decoding: try Data(contentsOf: stdout), as: UTF8.self),
            stderr: String(decoding: try Data(contentsOf: stderr), as: UTF8.self))
    } catch { return ProbeProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription) }
}
