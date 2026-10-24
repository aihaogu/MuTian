import Foundation

/// Logs are independent of downloads.json; each stream is capped at 2 MiB.
final class DownloadLogStore: @unchecked Sendable {
    private struct Entry { let text: String; let id: UUID; let stderr: Bool }
    private let queue = DispatchQueue(label: "dev.local.MuTian.download-logs", qos: .utility)
    private let directory: URL
    private let limit = 2 * 1024 * 1024
    private var pending: [Entry] = []
    private var failure: String?

    init(directory: URL) { self.directory = directory }

    private func url(_ id: UUID, stderr: Bool) -> URL {
        directory.appendingPathComponent("\(id)-\(stderr ? "stderr" : "stdout").log")
    }

    func append(_ text: String, id: UUID, stderr: Bool) {
        queue.async {
            self.pending.append(Entry(text: text, id: id, stderr: stderr))
            self.drain()
        }
    }

    private func drain() {
        while let entry = pending.first {
            do { try write(entry); pending.removeFirst(); failure = nil }
            catch { failure = error.localizedDescription; return }
        }
    }

    private func write(_ entry: Entry) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = url(entry.id, stderr: entry.stderr)
        let data = Data(entry.text.utf8)
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        if size + UInt64(data.count) > limit {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            try reader.seek(toOffset: size > UInt64(limit / 2) ? size - UInt64(limit / 2) : 0)
            let tail = try reader.readToEnd() ?? Data()
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: (tail + data).suffix(limit))
        } else {
            try handle.write(contentsOf: data)
        }
    }

    func tail(id: UUID, stderr: Bool) -> String {
        queue.sync {
            drain()
            guard let handle = try? FileHandle(forReadingFrom: url(id, stderr: stderr)) else { return "" }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 32_768 ? size - 32_768 : 0)
            return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        }
    }

    func remove(id: UUID) {
        queue.async {
            self.pending.removeAll { $0.id == id }
            for stderr in [false, true] { try? FileManager.default.removeItem(at: self.url(id, stderr: stderr)) }
            if self.pending.isEmpty { self.failure = nil }
        }
    }

    func flush() -> String? { queue.sync { drain(); return failure } }
}
