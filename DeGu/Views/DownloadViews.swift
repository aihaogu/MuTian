import AppKit
import SwiftUI

struct DownloadTaskListView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载")
                        .font(.headline)
                    Text("\(downloadStore.tasks.count) 个任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    downloadStore.addDraft(defaultDirectory: settingsStore.settings.defaultDownloadDirectory)
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(downloadStore.tasks) { task in
                            DownloadTaskRowView(task: task)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 120, idealHeight: 210, maxHeight: 280)

                Divider()

                DownloadTaskLogPanel(task: downloadStore.selectedTask)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DeGuTheme.detailBackground)
        .navigationTitle("下载")
    }
}

private struct DownloadTaskRowView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(DeGuTheme.downloadColor(task.status))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(task.url.isEmpty ? "未填写 URL" : task.url)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(text: task.status.rawValue, color: DeGuTheme.downloadColor(task.status))
                        Text(task.outputDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        selectTask()
                        downloadStore.probe(
                            taskID: task.id,
                            bookgetPath: settingsStore.settings.bookgetExecutablePath
                        )
                    } label: {
                        if downloadStore.isParsing(taskID: task.id) {
                            Label("解析中", systemImage: "hourglass")
                        } else {
                            Label("解析", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .disabled(downloadStore.isParsing(taskID: task.id) || task.status == .running)

                    if task.status == .running {
                        Button {
                            selectTask()
                            downloadStore.cancel(taskID: task.id)
                        } label: {
                            Label("取消", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            selectTask()
                            downloadStore.run(
                                taskID: task.id,
                                bookgetPath: settingsStore.settings.bookgetExecutablePath,
                                libraryStore: libraryStore
                            )
                        } label: {
                            Label("开始下载", systemImage: "play.fill")
                        }
                    }

                    Button(role: .destructive) {
                        downloadStore.delete(taskID: task.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("删除任务")
                }
                .controlSize(.small)
            }

            if let summaryText {
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

        }
        .padding(10)
        .background(isSelected ? DeGuTheme.accent.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? DeGuTheme.accent.opacity(0.30) : DeGuTheme.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectTask()
        }
        .contextMenu {
            if task.status == .running {
                Button("取消") {
                    downloadStore.cancel(taskID: task.id)
                }
            } else {
                Button("解析") {
                    downloadStore.probe(
                        taskID: task.id,
                        bookgetPath: settingsStore.settings.bookgetExecutablePath
                    )
                }
                Button("开始下载") {
                    downloadStore.run(
                        taskID: task.id,
                        bookgetPath: settingsStore.settings.bookgetExecutablePath,
                        libraryStore: libraryStore
                    )
                }
            }
            Button(role: .destructive) {
                downloadStore.delete(taskID: task.id)
            } label: {
                Text("删除任务")
            }
        }
    }

    private var isSelected: Bool {
        downloadStore.selectedTaskID == task.id
    }

    private var summaryText: String? {
        guard task.parsedTitle != nil || task.parsedVolumeCount != nil else { return nil }
        let title = task.parsedTitle ?? "未识别书名"
        if let volumeCount = task.parsedVolumeCount {
            return "\(title) · \(volumeCount) 册"
        }
        return title
    }

    private var progress: DownloadProgressSnapshot? {
        DownloadProgressSnapshot(task: task)
    }

    private func selectTask() {
        downloadStore.selectedTaskID = task.id
    }
}

private struct DownloadProgressSnapshot {
    let completed: Int
    let total: Int

    init?(task: DownloadTask) {
        let text = [task.stdoutLog, task.stderrLog].joined(separator: "\n")
        var latestCompleted = 0
        var latestTotal = 0

        for line in text.split(separator: "\n") {
            guard line.first == "[", let closeBracket = line.firstIndex(of: "]") else { continue }
            let value = line[line.index(after: line.startIndex)..<closeBracket]
            let parts = value.split(separator: "/", maxSplits: 1)
            guard parts.count == 2,
                  let completed = Int(parts[0]),
                  let total = Int(parts[1]),
                  total > 0 else {
                continue
            }
            latestCompleted = max(latestCompleted, completed)
            latestTotal = total
        }

        guard latestTotal > 0 else { return nil }
        completed = min(latestCompleted, latestTotal)
        total = latestTotal
    }
}

private struct DownloadTaskLogPanel: View {
    let task: DownloadTask?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日志")
                .font(.headline)

            if let task {
                ScrollView {
                    Text(logText(for: task).isEmpty ? "暂无日志" : logText(for: task))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(logText(for: task).isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("选择一个下载任务后显示日志。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }

    private func logText(for task: DownloadTask) -> String {
        [task.stdoutLog, task.stderrLog].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct DownloadDetailView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        if let task = downloadStore.selectedTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        Section("任务") {
                            TextField("URL", text: binding(task, \.url))
                            HStack {
                                TextField("输出目录", text: binding(task, \.outputDirectory))
                                Button {
                                    chooseOutputDirectory(for: task)
                                } label: {
                                    Label("选择", systemImage: "folder")
                                }
                            }
                            Picker("下载模式", selection: intBinding(task, \.mode)) {
                                Text("默认").tag(0)
                                Text("通用批量").tag(1)
                                Text("IIIF manifest").tag(2)
                            }
                            TextField("页码范围，如 4:434", text: binding(task, \.sequenceRange))
                            TextField("册数范围，如 1:10", text: binding(task, \.volumeRange))
                        }

                        Section("参数") {
                            TextField("IIIF format", text: binding(task, \.format))
                            TextField("扩展名", text: binding(task, \.fileExt))
                            Stepper("线程：\(task.threads)", value: intBinding(task, \.threads), in: 1...64)
                            Stepper("并发：\(task.concurrent)", value: intBinding(task, \.concurrent), in: 1...128)
                            Stepper("重试：\(task.retries)", value: intBinding(task, \.retries), in: 0...20)
                            Stepper("超时：\(task.timeoutSeconds) 秒", value: intBinding(task, \.timeoutSeconds), in: 10...3600)
                            Stepper("间隔：\(task.sleepSeconds) 秒", value: intBinding(task, \.sleepSeconds), in: 0...120)
                        }
                    }
                    .formStyle(.grouped)
                    .deGuPanel()

                }
                .padding(18)
            }
            .background(DeGuTheme.detailBackground)
        } else {
            DetailPlaceholder(title: "选择或新建下载任务", systemImage: "arrow.down.circle", message: "点击下载列表中的“新建”后再填写下载配置。")
        }
    }

    private func binding(_ task: DownloadTask, _ keyPath: WritableKeyPath<DownloadTask, String>) -> Binding<String> {
        Binding(
            get: { downloadStore.tasks.first(where: { $0.id == task.id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var edited = downloadStore.tasks.first(where: { $0.id == task.id }) else { return }
                edited[keyPath: keyPath] = value
                downloadStore.update(edited)
            }
        )
    }

    private func intBinding(_ task: DownloadTask, _ keyPath: WritableKeyPath<DownloadTask, Int>) -> Binding<Int> {
        Binding(
            get: { downloadStore.tasks.first(where: { $0.id == task.id })?[keyPath: keyPath] ?? 0 },
            set: { value in
                guard var edited = downloadStore.tasks.first(where: { $0.id == task.id }) else { return }
                edited[keyPath: keyPath] = value
                downloadStore.update(edited)
            }
        )
    }

    private func chooseOutputDirectory(for task: DownloadTask) {
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !task.outputDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: task.outputDirectory)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var edited = downloadStore.tasks.first(where: { $0.id == task.id }) else { return }
        edited.outputDirectory = url.path
        downloadStore.update(edited)
    }
}
