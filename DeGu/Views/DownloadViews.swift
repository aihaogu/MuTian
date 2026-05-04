import SwiftUI

struct DownloadTaskListView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下载任务")
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

            List(selection: $downloadStore.selectedTaskID) {
                ForEach(downloadStore.tasks) { task in
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
                    }
                    .tag(task.id)
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(DeGuTheme.detailBackground)
        .navigationTitle("下载")
    }
}

struct DownloadDetailView: View {
    @EnvironmentObject private var downloadStore: DownloadTaskStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        if let task = downloadStore.selectedTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("下载配置")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("由 Python 版 bookget 执行，完成后自动建立资料库索引。")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(text: task.status.rawValue, color: DeGuTheme.downloadColor(task.status))
                    }
                    .deGuPanel()

                    Form {
                        Section("任务") {
                            TextField("URL", text: binding(task, \.url))
                            TextField("输出目录", text: binding(task, \.outputDirectory))
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

                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("bookget") {
                            Text(settingsStore.settings.bookgetExecutablePath.isEmpty ? "未设置" : settingsStore.settings.bookgetExecutablePath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        HStack {
                            Button {
                                downloadStore.run(
                                    taskID: task.id,
                                    bookgetPath: settingsStore.settings.bookgetExecutablePath,
                                    libraryStore: libraryStore
                                )
                            } label: {
                                Label("开始下载", systemImage: "play")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(task.status == .running)

                            Button(role: .destructive) {
                                downloadStore.cancel(taskID: task.id)
                            } label: {
                                Label("取消", systemImage: "stop")
                            }
                            .disabled(task.status != .running)
                        }
                    }
                    .deGuPanel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("日志")
                            .font(.headline)
                        TextEditor(text: logBinding(task))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                    }
                    .deGuPanel()
                }
                .padding(18)
            }
            .background(DeGuTheme.detailBackground)
        } else {
            DetailPlaceholder(title: "没有下载任务", systemImage: "arrow.down.circle", message: "点击工具栏“下载”或左侧“下载任务”中新建任务。")
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

    private func logBinding(_ task: DownloadTask) -> Binding<String> {
        Binding(
            get: {
                guard let current = downloadStore.tasks.first(where: { $0.id == task.id }) else { return "" }
                return [current.stdoutLog, current.stderrLog].filter { !$0.isEmpty }.joined(separator: "\n")
            },
            set: { _ in }
        )
    }
}
