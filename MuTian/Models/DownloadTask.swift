import Foundation

enum DownloadStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case waiting = "待开始"
    case running = "运行中"
    case interrupted = "已中断"
    case completed = "已完成"
    case failed = "失败"
    case cancelled = "已取消"
    case imported = "已导入"

    var id: String { rawValue }
}

struct DownloadTask: Identifiable, Codable, Hashable, Sendable {
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
    var importedBookIDs: [UUID]? = nil

    static func draft(outputDirectory: String, threads: Int = 1, concurrent: Int = 16, retries: Int = 3, sleepSeconds: Int = 3) -> DownloadTask {
        DownloadTask(
            id: UUID(),
            url: "",
            outputDirectory: outputDirectory,
            mode: 0,
            sequenceRange: "",
            volumeRange: "",
            format: "full/full/0/default.jpg",
            fileExt: ".jpg",
            threads: threads,
            concurrent: concurrent,
            retries: retries,
            timeoutSeconds: 300,
            sleepSeconds: sleepSeconds,
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
