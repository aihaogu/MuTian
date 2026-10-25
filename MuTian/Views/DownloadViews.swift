import AppKit
import SwiftUI

private enum DownloadFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case unfinished = "未完成"
    case finished = "已完成"

    var id: String { rawValue }

    func includes(_ task: DownloadTask) -> Bool {
        switch self {
        case .all: return true
        case .unfinished: return !task.status.isFinished
        case .finished: return task.status.isFinished
        }
    }
}

private extension DownloadStatus {
    var isFinished: Bool { self == .completed || self == .imported }

    var symbol: String {
        switch self {
        case .waiting: return "clock"
        case .running: return "arrow.down.circle.fill"
        case .interrupted: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .imported: return "books.vertical.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var filter: DownloadFilter = .all

    var body: some View {
        let tasks = downloadStore.tasks.filter(filter.includes)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = downloadStore.persistenceError {
                    persistenceBanner(error)
                }

                DownloadComposer()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("下载任务")
                            .font(.system(.headline, design: .serif))
                        Spacer()
                        Picker("筛选", selection: $filter) {
                            ForEach(DownloadFilter.allCases) { filter in
                                Text("\(filter.rawValue) \(downloadStore.tasks.filter(filter.includes).count)")
                                    .tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if tasks.isEmpty {
                        Text(downloadStore.tasks.isEmpty ? "还没有下载任务。在上方粘贴链接开始第一次下载。" : "这一类下没有任务。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                DownloadTaskCard(task: task)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .background(MuTianTheme.detailBackground)
        .navigationTitle("下载")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button {
                    openDownloadFolder()
                } label: {
                    Label("打开下载文件夹", systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .help("在 Finder 中打开默认下载目录")
            }
        }
    }

    private var subtitle: String {
        let running = downloadStore.tasks.filter { $0.status == .running }.count
        let total = downloadStore.tasks.count
        return running > 0 ? "\(running) 个进行中 · 共 \(total) 个" : "共 \(total) 个任务"
    }

    private func persistenceBanner(_ error: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MuTianTheme.cinnabar)
            Text(error)
                .lineLimit(3)
            Spacer(minLength: 8)
            Button("重试保存") { downloadStore.flush() }
        }
        .font(.callout)
        .padding(12)
        .background(MuTianTheme.cinnabar.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func openDownloadFolder() {
        let path = settingsStore.settings.defaultDownloadDirectory
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}

// MARK: - New download

private struct DownloadComposer: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var draft = DownloadTask.draft(outputDirectory: "")
    @State private var showsOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建下载")
                .font(.system(.headline, design: .serif))

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("链接", text: $draft.url, prompt: Text("粘贴古籍页面或 IIIF manifest 链接，回车开始下载"))
                    .textFieldStyle(.plain)
                    .onSubmit { submit(startDownload: true) }
                if !trimmedURL.isEmpty {
                    Button {
                        draft.url = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help("清空链接")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MuTianTheme.paper, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MuTianTheme.hairline, lineWidth: 1)
            }

            HStack(spacing: 14) {
                Button {
                    chooseDirectory()
                } label: {
                    Label(directoryName, systemImage: "folder")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help("保存到：\(draft.outputDirectory)")

                Button {
                    withAnimation(.snappy(duration: 0.2)) { showsOptions.toggle() }
                } label: {
                    Label("下载选项", systemImage: showsOptions ? "chevron.up" : "slider.horizontal.3")
                }
                .buttonStyle(.borderless)

                Spacer(minLength: 8)

                Button("先解析") { submit(startDownload: false) }
                    .help("只识别书名和册数，不下载")
                    .disabled(trimmedURL.isEmpty)
                Button("开始下载") { submit(startDownload: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedURL.isEmpty)
            }
            .font(.callout)

            if showsOptions {
                Divider()
                DownloadOptionsGrid(task: $draft, includesSource: false)
            }
        }
        .muTianPanel()
        .onAppear(perform: resetDraftIfNeeded)
    }

    private var trimmedURL: String {
        draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var directoryName: String {
        let name = URL(fileURLWithPath: draft.outputDirectory).lastPathComponent
        return name.isEmpty ? "选择保存位置" : name
    }

    private func resetDraftIfNeeded() {
        guard draft.outputDirectory.isEmpty else { return }
        let settings = settingsStore.settings
        draft = .draft(outputDirectory: settings.defaultDownloadDirectory,
            threads: settings.defaultThreads, concurrent: settings.defaultConcurrent,
            retries: settings.defaultRetries, sleepSeconds: settings.defaultSleepSeconds)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: draft.outputDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            draft.outputDirectory = url.path
        }
    }

    private func submit(startDownload: Bool) {
        let url = trimmedURL
        guard !url.isEmpty else { return }
        downloadStore.addDraft(settings: settingsStore.settings)
        guard let created = downloadStore.selectedTask else { return }

        var task = draft
        task.id = created.id
        task.createdAt = created.createdAt
        task.url = url
        task.status = .waiting
        downloadStore.update(task)

        let enginePath = settingsStore.settings.bookgetExecutablePath
        if startDownload {
            downloadStore.selectedTaskID = nil
            downloadStore.run(taskID: task.id, bookgetPath: enginePath, libraryStore: libraryStore)
        } else {
            downloadStore.probe(taskID: task.id, bookgetPath: enginePath)
        }
        draft.url = ""
    }
}

// MARK: - Task card

private struct DownloadTaskCard: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
                .padding(12)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleExpanded)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    DownloadOptionsGrid(task: taskBinding, includesSource: true)
                        .disabled(isLocked)
                    DownloadLogView(text: logText)
                }
                .padding(14)
            }
        }
        .background(MuTianTheme.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? MuTianTheme.accent.opacity(0.35) : MuTianTheme.hairline, lineWidth: 1)
        }
        .contextMenu { menuItems }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: task.status.symbol)
                .font(.title2)
                .foregroundStyle(MuTianTheme.downloadColor(task.status))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, design: task.parsedTitle == nil ? .default : .serif))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(statusLine)
                        .foregroundStyle(MuTianTheme.downloadColor(task.status))
                    ForEach(details, id: \.self) { detail in
                        Text("·")
                        Text(detail)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if task.status == .running, let progress {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .controlSize(.small)
                        .padding(.top, 2)
                } else if task.status == .running {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            primaryAction
                .controlSize(.small)

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if isParsing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("解析中").font(.caption).foregroundStyle(.secondary)
            }
        } else if task.status == .running {
            Button("取消", systemImage: "stop.fill", action: cancel)
        } else if let book = importedBook {
            Button("查看书目", systemImage: "books.vertical") {
                libraryStore.sidebarSelection = .all
                libraryStore.selectBook(book)
            }
        } else if task.status.isFinished {
            Button("打开文件夹", systemImage: "folder", action: revealOutput)
        } else {
            Button(task.status == .waiting ? "开始下载" : "重试",
                   systemImage: task.status == .waiting ? "arrow.down" : "arrow.clockwise",
                   action: run)
                .disabled(task.url.isEmpty)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if task.status == .running {
            Button("取消下载", action: cancel)
        } else {
            Button("解析", action: probe).disabled(isParsing || task.url.isEmpty)
            Button(task.status.isFinished ? "重新下载" : "开始下载", action: run).disabled(isParsing || task.url.isEmpty)
        }
        Button("在 Finder 中显示", action: revealOutput)
        Button("复制链接") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.url, forType: .string)
        }
        .disabled(task.url.isEmpty)
        Divider()
        Button("删除任务", role: .destructive) {
            downloadStore.delete(taskID: task.id)
        }
        .disabled(task.status == .running)
    }

    private var isExpanded: Bool { downloadStore.selectedTaskID == task.id }
    private var isParsing: Bool { downloadStore.isParsing(taskID: task.id) }
    private var isLocked: Bool { task.status == .running || isParsing }
    private var progress: DownloadProgressSnapshot? { DownloadProgressSnapshot(task: task) }

    private var title: String {
        if let parsedTitle = task.parsedTitle, !parsedTitle.isEmpty { return parsedTitle }
        return task.url.isEmpty ? "未填写链接" : task.url
    }

    private var statusLine: String {
        if task.status == .running, let progress {
            return "\(task.status.rawValue) \(progress.completed)/\(progress.total)"
        }
        return task.status.rawValue
    }

    private var details: [String] {
        var parts: [String] = []
        if let host = URL(string: task.url)?.host, !host.isEmpty { parts.append(host) }
        if let volumes = task.parsedVolumeCount { parts.append("\(volumes) 册") }
        if let date = task.finishedAt ?? task.startedAt {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts
    }

    private var importedBook: Book? {
        let ids = Set((task.importedBookIDs ?? []) + [task.importedBookID].compactMap { $0 })
        guard !ids.isEmpty else { return nil }
        return libraryStore.books.first { ids.contains($0.id) }
    }

    private var logText: String {
        [task.stdoutLog, task.stderrLog].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var taskBinding: Binding<DownloadTask> {
        Binding(
            get: { downloadStore.tasks.first(where: { $0.id == task.id }) ?? task },
            set: { downloadStore.update($0) }
        )
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.2)) {
            downloadStore.selectedTaskID = isExpanded ? nil : task.id
        }
    }

    private func run() {
        downloadStore.run(taskID: task.id, bookgetPath: settingsStore.settings.bookgetExecutablePath, libraryStore: libraryStore)
    }

    private func probe() {
        downloadStore.selectedTaskID = task.id
        downloadStore.probe(taskID: task.id, bookgetPath: settingsStore.settings.bookgetExecutablePath)
    }

    private func cancel() {
        downloadStore.cancel(taskID: task.id)
    }

    private func revealOutput() {
        let url = URL(fileURLWithPath: task.outputDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - Shared parts

private struct DownloadOptionsGrid: View {
    @Binding var task: DownloadTask
    let includesSource: Bool
    @State private var showsAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                if includesSource {
                    GridRow {
                        label("链接")
                        TextField("链接", text: $task.url)
                            .gridCellColumns(3)
                    }
                    GridRow {
                        label("保存到")
                        HStack(spacing: 8) {
                            Text(task.outputDirectory)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(task.outputDirectory)
                            Spacer(minLength: 0)
                            Button("更改…", action: chooseDirectory)
                                .controlSize(.small)
                        }
                        .gridCellColumns(3)
                    }
                }
                GridRow {
                    label("下载模式")
                    Picker("下载模式", selection: $task.mode) {
                        Text("默认").tag(0)
                        Text("通用批量").tag(1)
                        Text("IIIF manifest").tag(2)
                    }
                    .labelsHidden()
                    .fixedSize()
                    label("页码范围")
                    TextField("页码范围", text: $task.sequenceRange, prompt: Text("全部，如 4:434"))
                }
                GridRow {
                    label("册数范围")
                    TextField("册数范围", text: $task.volumeRange, prompt: Text("全部，如 1:10"))
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
            .textFieldStyle(.roundedBorder)

            DisclosureGroup("高级参数", isExpanded: $showsAdvanced) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        label("IIIF 格式")
                        TextField("IIIF 格式", text: $task.format)
                        label("扩展名")
                        TextField("扩展名", text: $task.fileExt)
                    }
                    GridRow {
                        label("线程")
                        numberStepper($task.threads, in: 1...64)
                        label("并发")
                        numberStepper($task.concurrent, in: 1...128)
                    }
                    GridRow {
                        label("重试")
                        numberStepper($task.retries, in: 0...20, unit: "次")
                        label("超时")
                        numberStepper($task.timeoutSeconds, in: 10...3600, step: 10, unit: "秒")
                    }
                    GridRow {
                        label("间隔")
                        numberStepper($task.sleepSeconds, in: 0...120, unit: "秒")
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)
            }
            .font(.callout)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func numberStepper(_ value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1, unit: String = "") -> some View {
        Stepper(value: value, in: range, step: step) {
            Text(unit.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(unit)")
                .monospacedDigit()
        }
        .fixedSize()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择保存位置"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if !task.outputDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: task.outputDirectory)
        }
        if panel.runModal() == .OK, let url = panel.url {
            task.outputDirectory = url.path
        }
    }
}

private struct DownloadLogView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("日志")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(text.isEmpty)
            }
            ScrollView {
                Text(text.isEmpty ? "暂无日志" : text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(height: 160)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
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
