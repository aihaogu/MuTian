import Foundation

enum AppPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return resolveSupportDirectory(in: base)
    }()

    static func resolveSupportDirectory(in base: URL, fileManager: FileManager = .default) -> URL {
        let directory = base.appendingPathComponent("木天", isDirectory: true)
        guard !fileManager.fileExists(atPath: directory.path) else { return directory }

        // Keep the legacy name only for migration; never overwrite an existing library.
        let legacy = base.appendingPathComponent("得古", isDirectory: true)
        if fileManager.fileExists(atPath: legacy.path) {
            let staging = base.appendingPathComponent(".mutian-migration-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.copyItem(at: legacy, to: staging)
                try fileManager.moveItem(at: staging, to: directory)
                return directory
            } catch {
                try? fileManager.removeItem(at: staging)
                NSLog("木天资料库迁移失败，继续使用原目录：%@", error.localizedDescription)
                return legacy
            }
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var libraryFile: URL {
        supportDirectory.appendingPathComponent("library.json")
    }

    static var settingsFile: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    static var downloadsFile: URL {
        supportDirectory.appendingPathComponent("downloads.json")
    }

    static var defaultManagedDownloadsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent("木天下载", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var defaultBookgetExecutablePath: String {
        let bundleRoot = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            bundleRoot.appendingPathComponent("bin/bookget").path,
            bundleRoot.appendingPathComponent("bookget/bookget").path,
            FileManager.default.currentDirectoryPath + "/bin/bookget",
            FileManager.default.currentDirectoryPath + "/bookget/bookget"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
}
