import Foundation

struct LibrarySnapshot: Codable, Sendable {
    var books: [Book]
    var roots: [LibraryRoot]
}

enum LibraryPathRepair {
    /// Change only missing paths with a verified destination; keep IDs and metadata intact.
    static func repair(_ snapshot: inout LibrarySnapshot, from oldRoot: URL, to newRoot: URL) -> Int {
        let oldPath = oldRoot.standardizedFileURL.path
        let newPath = newRoot.standardizedFileURL.path
        let fm = FileManager.default
        var changes = 0
        func resolve(_ path: String) -> String {
            guard !fm.fileExists(atPath: path),
                  path == oldPath || path.hasPrefix(oldPath + "/") else { return path }
            let candidate = newPath + path.dropFirst(oldPath.count)
            guard fm.fileExists(atPath: candidate) else { return path }
            changes += 1
            return candidate
        }
        for index in snapshot.books.indices {
            snapshot.books[index].localPath = resolve(snapshot.books[index].localPath)
            for page in snapshot.books[index].pageRecords.indices {
                snapshot.books[index].pageRecords[page].imagePath = resolve(snapshot.books[index].pageRecords[page].imagePath)
            }
        }
        for index in snapshot.books.indices {
            if var archived = snapshot.books[index].archivedPageRecords {
                for page in archived.indices { archived[page].imagePath = resolve(archived[page].imagePath) }
                snapshot.books[index].archivedPageRecords = archived
            }
        }
        for index in snapshot.roots.indices {
            snapshot.roots[index].path = resolve(snapshot.roots[index].path)
        }
        return changes
    }
}
