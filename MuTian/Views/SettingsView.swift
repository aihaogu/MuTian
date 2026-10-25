import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        Form {
            Section {
                pathRow("资料库", path: settingsStore.settings.databaseDirectory) { EmptyView() }
                LabeledContent("资料库文件夹") {
                    HStack(spacing: 8) {
                        Text("\(libraryStore.roots.count) 个位置")
                            .foregroundStyle(.secondary)
                        OpenLibraryFoldersButton(title: "管理…")
                    }
                }
                pathRow("默认下载目录", path: settingsStore.settings.defaultDownloadDirectory) {
                    Button("选择…") { settingsStore.chooseDownloadDirectory() }
                }
                pathRow("下载引擎", path: engineDisplayPath) {
                    if !isBuiltInEngine {
                        Button("恢复内置") {
                            settingsStore.settings.bookgetExecutablePath = AppPaths.defaultBookgetExecutablePath
                        }
                    }
                    Button("选择…") { settingsStore.chooseBookgetExecutable() }
                }
            } header: {
                Text("路径")
            } footer: {
                Text("导入时只记录本地路径，不移动原文件；新下载的文件保存到默认下载目录。")
                    .foregroundStyle(.secondary)
            }

            Section("新任务默认参数") {
                HStack(spacing: 24) {
                    Stepper("线程　\(settingsStore.settings.defaultThreads)", value: $settingsStore.settings.defaultThreads, in: 1...64)
                    Stepper("并发　\(settingsStore.settings.defaultConcurrent)", value: $settingsStore.settings.defaultConcurrent, in: 1...128)
                }
                HStack(spacing: 24) {
                    Stepper("重试　\(settingsStore.settings.defaultRetries) 次", value: $settingsStore.settings.defaultRetries, in: 0...20)
                    Stepper("间隔　\(settingsStore.settings.defaultSleepSeconds) 秒", value: $settingsStore.settings.defaultSleepSeconds, in: 0...120)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 370)
        .tint(MuTianTheme.accent)
    }

    private var isBuiltInEngine: Bool {
        settingsStore.settings.bookgetExecutablePath == AppPaths.defaultBookgetExecutablePath
    }

    private var engineDisplayPath: String {
        isBuiltInEngine ? "内置引擎" : settingsStore.settings.bookgetExecutablePath
    }

    private func pathRow<Actions: View>(_ title: String, path: String, @ViewBuilder actions: () -> Actions) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(path.isEmpty ? "未设置" : path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
                actions()
            }
        }
    }
}
