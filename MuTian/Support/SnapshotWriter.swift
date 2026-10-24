import Foundation

/// Encoding and atomic writes happen on one queue. A flush is a barrier for all
/// previously scheduled changes, including the most recent debounced snapshot.
final class SnapshotWriter<Value: Encodable & Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.local.MuTian.persistence", qos: .utility)
    private let url: URL
    private let report: @Sendable (String?) -> Void
    private var pending: Value?
    private var scheduled: DispatchWorkItem?

    init(url: URL, report: @escaping @Sendable (String?) -> Void = { _ in }) {
        self.url = url
        self.report = report
    }

    func schedule(_ value: Value) {
        queue.async {
            self.pending = value
            self.scheduled?.cancel()
            let work = DispatchWorkItem { [weak self] in
                do { try self?.writePending() } catch { self?.report(error.localizedDescription) }
            }
            self.scheduled = work
            self.queue.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    func flush() throws {
        try queue.sync {
            scheduled?.cancel()
            scheduled = nil
            try writePending()
        }
    }

    private func writePending() throws {
        guard let pending else { return }
        let data = try JSONEncoder.muTian.encode(pending)
        try data.write(to: url, options: [.atomic])
        self.pending = nil
        report(nil)
    }
}
