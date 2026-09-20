import Foundation

enum DownloadStatus: String, Codable, CaseIterable, Identifiable {
    case waiting = "待开始"
    case running = "运行中"
    case completed = "已完成"
    case failed = "失败"
    case cancelled = "已取消"
    case imported = "已导入"

    var id: String { rawValue }
}

struct DownloadTask: Identifiable, Codable, Hashable {
    var id: UUID
    var url: String
    var outputDirectory: String
    var mode: Int
    var sequenceRange: String
    var volumeRange: String
    var format: String
    var fileExt: String
    var threads: Int
    var concurrent: Int
    var retries: Int
    var timeoutSeconds: Int
    var sleepSeconds: Int
    var status: DownloadStatus
    var stdoutLog: String
    var stderrLog: String
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var importedBookID: UUID?
    var parsedTitle: String?
    var parsedVolumeCount: Int?

    static func draft(outputDirectory: String) -> DownloadTask {
        DownloadTask(
            id: UUID(),
            url: "",
            outputDirectory: outputDirectory,
            mode: 0,
            sequenceRange: "",
            volumeRange: "",
            format: "full/full/0/default.jpg",
            fileExt: ".jpg",
            threads: 1,
            concurrent: 16,
            retries: 3,
            timeoutSeconds: 300,
            sleepSeconds: 3,
            status: .waiting,
            stdoutLog: "",
            stderrLog: "",
            createdAt: Date(),
            startedAt: nil,
            finishedAt: nil,
            importedBookID: nil,
            parsedTitle: nil,
            parsedVolumeCount: nil
        )
    }
}
