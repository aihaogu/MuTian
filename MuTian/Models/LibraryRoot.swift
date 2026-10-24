import Foundation

struct LibraryRoot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String
    var createdAt: Date
    var lastScannedAt: Date?

    static func new(path: String) -> LibraryRoot {
        LibraryRoot(id: UUID(), path: path, createdAt: Date(), lastScannedAt: nil)
    }
}
