import AppKit
import Foundation

struct AppSettings: Codable {
    var databaseDirectory: String
    var defaultDownloadDirectory: String
    var bookgetExecutablePath: String
    var defaultThreads: Int
    var defaultConcurrent: Int
    var defaultRetries: Int
    var defaultSleepSeconds: Int

    static var defaults: AppSettings {
        AppSettings(
            databaseDirectory: AppPaths.supportDirectory.path,
            defaultDownloadDirectory: AppPaths.defaultManagedDownloadsDirectory.path,
            bookgetExecutablePath: AppPaths.defaultBookgetExecutablePath,
            defaultThreads: 1,
            defaultConcurrent: 16,
            defaultRetries: 3,
            defaultSleepSeconds: 3
        )
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        if let data = try? Data(contentsOf: AppPaths.settingsFile),
           let decoded = try? JSONDecoder.deGu.decode(AppSettings.self, from: data) {
            var migrated = decoded
            if migrated.bookgetExecutablePath.isEmpty {
                migrated.bookgetExecutablePath = AppPaths.defaultBookgetExecutablePath
            }
            settings = migrated
        } else {
            settings = .defaults
        }
    }

    func chooseBookgetExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 bookget 可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.bookgetExecutablePath = url.path
        }
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认下载目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultDownloadDirectory = url.path
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.deGu.encode(settings) else { return }
        try? data.write(to: AppPaths.settingsFile, options: [.atomic])
    }
}

extension JSONEncoder {
    static var deGu: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var deGu: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
