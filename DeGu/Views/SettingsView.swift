import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("路径") {
                LabeledContent("资料库") {
                    Text(settingsStore.settings.databaseDirectory)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    TextField("默认下载目录", text: $settingsStore.settings.defaultDownloadDirectory)
                    Button("选择...") {
                        settingsStore.chooseDownloadDirectory()
                    }
                }
                HStack {
                    TextField("bookget 可执行文件", text: $settingsStore.settings.bookgetExecutablePath)
                    Button("选择...") {
                        settingsStore.chooseBookgetExecutable()
                    }
                }
            }

            Section("bookget 默认参数") {
                Stepper("线程：\(settingsStore.settings.defaultThreads)", value: $settingsStore.settings.defaultThreads, in: 1...64)
                Stepper("并发：\(settingsStore.settings.defaultConcurrent)", value: $settingsStore.settings.defaultConcurrent, in: 1...128)
                Stepper("重试：\(settingsStore.settings.defaultRetries)", value: $settingsStore.settings.defaultRetries, in: 0...20)
                Stepper("间隔：\(settingsStore.settings.defaultSleepSeconds) 秒", value: $settingsStore.settings.defaultSleepSeconds, in: 0...120)
            }

            Section("导入策略") {
                Text("已有古籍文件夹导入时只建立索引并记录原路径，不复制、不移动、不重命名原文件。bookget 下载产生的新文件默认保存到得古下载目录。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620, height: 420)
        .tint(DeGuTheme.accent)
    }
}
