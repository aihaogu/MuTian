import Foundation

@MainActor
final class DownloadTaskStore: ObservableObject {
    @Published var tasks: [DownloadTask] = [] {
        didSet { save() }
    }
    @Published var selectedTaskID: UUID?
    private var runningProcesses: [UUID: Process] = [:]

    init() {
        load()
    }

    var selectedTask: DownloadTask? {
        guard let selectedTaskID else { return tasks.first }
        return tasks.first { $0.id == selectedTaskID }
    }

    func addDraft(defaultDirectory: String) {
        let task = DownloadTask.draft(outputDirectory: defaultDirectory)
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
    }

    func update(_ task: DownloadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }

    func run(taskID: UUID, bookgetPath: String, libraryStore: LibraryStore) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard !bookgetPath.isEmpty else {
            tasks[index].status = .failed
            tasks[index].stderrLog += "\n未设置 bookget 可执行文件路径。"
            return
        }

        let executable = URL(fileURLWithPath: bookgetPath)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            tasks[index].status = .failed
            tasks[index].stderrLog += "\nbookget 路径不可执行：\(bookgetPath)"
            return
        }

        var task = tasks[index]
        guard !task.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            task.status = .failed
            task.stderrLog += "\n下载 URL 不能为空。"
            tasks[index] = task
            return
        }

        try? FileManager.default.createDirectory(
            atPath: task.outputDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = executable
        process.arguments = buildArguments(for: task)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        task.status = .running
        task.startedAt = Date()
        task.stdoutLog += "\n$ \(executable.path) \(process.arguments?.joined(separator: " ") ?? "")\n"
        tasks[index] = task
        let currentTaskID = task.id
        runningProcesses[currentTaskID] = process

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendStdout(text, to: currentTaskID)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendStderr(text, to: currentTaskID)
            }
        }

        process.terminationHandler = { [weak self, weak libraryStore] process in
            Task { @MainActor in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self?.finish(taskID: currentTaskID, exitCode: process.terminationStatus, libraryStore: libraryStore)
            }
        }

        do {
            try process.run()
        } catch {
            appendStderr("\n启动失败：\(error.localizedDescription)", to: currentTaskID)
            finish(taskID: currentTaskID, exitCode: -1, libraryStore: libraryStore)
        }
    }

    func cancel(taskID: UUID) {
        runningProcesses[taskID]?.terminate()
        runningProcesses[taskID] = nil
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
        tasks[index].finishedAt = Date()
    }

    private func buildArguments(for task: DownloadTask) -> [String] {
        var arguments: [String] = [
            "--input", task.url,
            "--dir", task.outputDirectory,
            "--downloader_mode", "\(task.mode)",
            "--format", task.format,
            "--ext", task.fileExt,
            "--threads", "\(task.threads)",
            "--concurrent", "\(task.concurrent)",
            "--retries", "\(task.retries)",
            "--timeout", "\(task.timeoutSeconds)",
            "--sleep", "\(task.sleepSeconds)"
        ]
        if !task.sequenceRange.isEmpty {
            arguments += ["--sequence", task.sequenceRange]
        }
        if !task.volumeRange.isEmpty {
            arguments += ["--volume", task.volumeRange]
        }
        return arguments
    }

    private func appendStdout(_ text: String, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].stdoutLog += text
    }

    private func appendStderr(_ text: String, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].stderrLog += text
    }

    private func finish(taskID: UUID, exitCode: Int32, libraryStore: LibraryStore?) {
        runningProcesses[taskID] = nil
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].finishedAt = Date()
        tasks[index].status = exitCode == 0 ? .completed : .failed
        if exitCode == 0, let libraryStore {
            let outputDirectory = tasks[index].outputDirectory
            Task {
                await libraryStore.importURLs([URL(fileURLWithPath: outputDirectory)])
                if let imported = libraryStore.books.first(where: { $0.localPath.hasPrefix(outputDirectory) }) {
                    if let currentIndex = tasks.firstIndex(where: { $0.id == taskID }) {
                        tasks[currentIndex].status = .imported
                        tasks[currentIndex].importedBookID = imported.id
                    }
                }
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.downloadsFile),
              let decoded = try? JSONDecoder.deGu.decode([DownloadTask].self, from: data) else {
            return
        }
        tasks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.deGu.encode(tasks) else { return }
        try? data.write(to: AppPaths.downloadsFile, options: [.atomic])
    }
}
