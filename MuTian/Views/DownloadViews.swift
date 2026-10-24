import AppKit
import SwiftUI

struct DownloadTaskListView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = downloadStore.persistenceError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(error)
                        .foregroundStyle(MuTianTheme.cinnabar)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button("重试保存") { downloadStore.flush() }
                        .controlSize(.small)
                }
                .font(.caption)
                .padding(10)
                Divider()
            }

            if downloadStore.tasks.isEmpty {
                DetailPlaceholder(title: "还没有下载任务", systemImage: "arrow.down.circle", message: "点击工具栏的“新建任务”，粘贴古籍页面链接。")
            } else {
                List(selection: $downloadStore.selectedTaskID) {
                    ForEach(downloadStore.tasks) { task in
                        DownloadTaskRowView(task: task)
                            .tag(task.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
        .navigationTitle("下载")
        .navigationSubtitle("\(downloadStore.tasks.count) 个任务")
    }
}

private struct DownloadTaskRowView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: task.parsedTitle == nil ? .default : .serif))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                StatusBadge(text: task.status.rawValue, color: MuTianTheme.downloadColor(task.status))
            }

            if let progress = DownloadProgressSnapshot(task: task), task.status == .running {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .controlSize(.small)
            } else if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            DownloadTaskActions(task: task, downloadStore: downloadStore, settingsStore: settingsStore, libraryStore: libraryStore).menuItems
        }
    }

    private var title: String {
        if let parsedTitle = task.parsedTitle, !parsedTitle.isEmpty { return parsedTitle }
        return task.url.isEmpty ? "未填写链接" : task.url
    }

    private var subtitle: String? {
        var parts: [String] = []
        if task.parsedTitle != nil, !task.url.isEmpty { parts.append(task.url) }
        if let volumeCount = task.parsedVolumeCount { parts.append("\(volumeCount) 册") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
private struct DownloadTaskActions {
    let task: DownloadTask
    let downloadStore: DownloadTaskStore
    let settingsStore: SettingsStore
    let libraryStore: LibraryStore

    var isParsing: Bool { downloadStore.isParsing(taskID: task.id) }
    var isRunning: Bool { task.status == .running }

    func probe() {
        downloadStore.selectedTaskID = task.id
        downloadStore.probe(taskID: task.id, bookgetPath: settingsStore.settings.bookgetExecutablePath)
    }

    func run() {
        downloadStore.selectedTaskID = task.id
        downloadStore.run(taskID: task.id, bookgetPath: settingsStore.settings.bookgetExecutablePath, libraryStore: libraryStore)
    }

    func cancel() {
        downloadStore.cancel(taskID: task.id)
    }

    func delete() {
        downloadStore.delete(taskID: task.id)
    }

    @ViewBuilder
    var menuItems: some View {
        if isRunning {
            Button("取消下载", action: cancel)
        } else {
            Button("解析", action: probe).disabled(isParsing)
            Button("开始下载", action: run).disabled(isParsing)
        }
        Divider()
        Button("删除任务", role: .destructive, action: delete)
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

struct DownloadDetailView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showsAdvanced = false
    @State private var showsLog = false

    var body: some View {
        if let task = downloadStore.selectedTask {
            let actions = DownloadTaskActions(task: task, downloadStore: downloadStore, settingsStore: settingsStore, libraryStore: libraryStore)
            let isLocked = actions.isRunning || actions.isParsing
            VStack(spacing: 0) {
                header(task, actions: actions)
                Divider()
                Form {
                    Section("任务") {
                        TextField("链接", text: binding(task, \.url), prompt: Text("古籍页面或 IIIF manifest 地址"))
                        LabeledContent("输出目录") {
                            HStack(spacing: 8) {
                                Text(task.outputDirectory.isEmpty ? "未选择" : task.outputDirectory)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(task.outputDirectory)
                                Button("选择…") { chooseOutputDirectory(for: task) }
                            }
                        }
                        Picker("下载模式", selection: intBinding(task, \.mode)) {
                            Text("默认").tag(0)
                            Text("通用批量").tag(1)
                            Text("IIIF manifest").tag(2)
                        }
                        TextField("页码范围", text: binding(task, \.sequenceRange), prompt: Text("如 4:434，留空为全部"))
                        TextField("册数范围", text: binding(task, \.volumeRange), prompt: Text("如 1:10，留空为全部"))
                    }
                    .disabled(isLocked)

                    Section {
                        DisclosureGroup("高级参数", isExpanded: $showsAdvanced) {
                            TextField("IIIF 格式", text: binding(task, \.format))
                            TextField("扩展名", text: binding(task, \.fileExt))
                            Stepper("线程　\(task.threads)", value: intBinding(task, \.threads), in: 1...64)
                            Stepper("并发　\(task.concurrent)", value: intBinding(task, \.concurrent), in: 1...128)
                            Stepper("重试　\(task.retries) 次", value: intBinding(task, \.retries), in: 0...20)
                            Stepper("超时　\(task.timeoutSeconds) 秒", value: intBinding(task, \.timeoutSeconds), in: 10...3600)
                            Stepper("间隔　\(task.sleepSeconds) 秒", value: intBinding(task, \.sleepSeconds), in: 0...120)
                        }
                    }
                    .disabled(isLocked)

                    Section {
                        DisclosureGroup("日志", isExpanded: $showsLog) {
                            ScrollView {
                                Text(logText(for: task).isEmpty ? "暂无日志" : logText(for: task))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(logText(for: task).isEmpty ? .secondary : .primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .frame(minHeight: 120, maxHeight: 280)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .background(MuTianTheme.detailBackground)
        } else {
            DetailPlaceholder(title: "选择或新建下载任务", systemImage: "arrow.down.circle", message: "在左侧选择任务，或点击工具栏的“新建任务”。")
        }
    }

    private func header(_ task: DownloadTask, actions: DownloadTaskActions) -> some View {
        HStack(spacing: 10) {
            StatusBadge(text: task.status.rawValue, color: MuTianTheme.downloadColor(task.status))

            if let progress = DownloadProgressSnapshot(task: task) {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .frame(maxWidth: 220)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if actions.isRunning {
                Button("取消", systemImage: "stop.fill", action: actions.cancel)
            } else {
                Button(actions.isParsing ? "解析中…" : "解析", systemImage: "doc.text.magnifyingglass", action: actions.probe)
                    .disabled(actions.isParsing || task.url.isEmpty)
                Button("开始下载", systemImage: "arrow.down", action: actions.run)
                    .buttonStyle(.borderedProminent)
                    .disabled(actions.isParsing || task.url.isEmpty)
            }

            Menu {
                Button("删除任务", role: .destructive, action: actions.delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func logText(for task: DownloadTask) -> String {
        [task.stdoutLog, task.stderrLog].filter { !$0.isEmpty }.joined(separator: "\n")
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
