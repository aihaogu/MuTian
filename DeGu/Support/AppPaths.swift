import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("得古", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        let directory = documents.appendingPathComponent("拾古下载", isDirectory: true)
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
