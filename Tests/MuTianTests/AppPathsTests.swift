import Foundation

final class AppPathsTests {
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base)
    }

    func testFreshInstallCreatesNamedDirectory() throws {
        try withTemporaryDirectory { base in
            let directory = AppPaths.resolveSupportDirectory(in: base)
            expectEqual(directory.lastPathComponent, "木天")
            precondition(FileManager.default.fileExists(atPath: directory.path))
        }
    }

    func testMigrationPreservesAllRecordsAndOriginals() throws {
        try withTemporaryDirectory { base in
            let legacy = base.appendingPathComponent("得古")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            let files = ["library.json", "settings.json", "downloads.json"]
            for file in files {
                try Data(file.utf8).write(to: legacy.appendingPathComponent(file))
            }
            let directory = AppPaths.resolveSupportDirectory(in: base)
            expectEqual(directory.lastPathComponent, "木天")
            for file in files {
                expectEqual(try Data(contentsOf: directory.appendingPathComponent(file)),
                               try Data(contentsOf: legacy.appendingPathComponent(file)))
            }
            expectEqual(AppPaths.resolveSupportDirectory(in: base), directory)
            expectEqual(try FileManager.default.contentsOfDirectory(atPath: base.path).count, 2)
        }
    }

    func testExistingLibraryIsNeverOverwritten() throws {
        try withTemporaryDirectory { base in
            for name in ["得古", "木天"] {
                let directory = base.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(name.utf8).write(to: directory.appendingPathComponent("library.json"))
            }
            let directory = AppPaths.resolveSupportDirectory(in: base)
            expectEqual(try Data(contentsOf: directory.appendingPathComponent("library.json")), Data("木天".utf8))
        }
    }

    func testFailedMigrationUsesOriginalAndRemovesPartialCopy() throws {
        try withTemporaryDirectory { base in
            let legacy = base.appendingPathComponent("得古")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try Data("original".utf8).write(to: legacy.appendingPathComponent("library.json"))
            expectEqual(AppPaths.resolveSupportDirectory(in: base, fileManager: FailingCopyFileManager()).path, legacy.path)
            expectEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), ["得古"])
            expectEqual(try Data(contentsOf: legacy.appendingPathComponent("library.json")), Data("original".utf8))
        }
    }
}

private final class FailingCopyFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try createDirectory(at: dstURL, withIntermediateDirectories: true)
        throw CocoaError(.fileWriteNoPermission)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \(expected), received \(actual)")
}

@main
struct AppPathsTestRunner {
    static func main() throws {
        let tests = AppPathsTests()
        try tests.testFreshInstallCreatesNamedDirectory()
        try tests.testMigrationPreservesAllRecordsAndOriginals()
        try tests.testExistingLibraryIsNeverOverwritten()
        try tests.testFailedMigrationUsesOriginalAndRemovesPartialCopy()
        print("Passed 4 app data migration checks")
    }
}
