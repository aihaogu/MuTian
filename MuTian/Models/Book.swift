import Foundation

enum BookFileType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdf = "PDF"
    case imageSequence = "图片序列"
    case text = "文本"
    case ebook = "电子书"
    case document = "文档"
    case archive = "压缩包"
    case mixedFolder = "混合目录"

    var id: String { rawValue }
}

enum BookStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending = "待整理"
    case organized = "已整理"
    case needsProofreading = "需校对"
    case proofreading = "校对中"
    case proofread = "已校对"

    var id: String { rawValue }
}

struct Book: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var dynasty: String
    var edition: String
    var sourceName: String
    var sourceURL: String
    var localPath: String
    var fileType: BookFileType
    var pageCount: Int
    var classificationID: String
    var tags: [String]
    var isFavorite: Bool
    var status: BookStatus
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var lastReadPage: Int
    var lastReadAt: Date?
    var pageRecords: [PageRecord]
    // Keep annotations for removed/replaced pages available for later recovery.
    var archivedPageRecords: [PageRecord]? = nil
    // Added after v1.0: optional so older library.json files still decode.
    var publisher: String? = nil
    var seriesName: String? = nil
    var volume: String? = nil

    /// 出版社 / 出版者
    var publisherText: String {
        get { publisher ?? "" }
        set { publisher = newValue.nilIfEmpty }
    }

    /// 所属丛书
    var seriesText: String {
        get { seriesName ?? "" }
        set { seriesName = newValue.nilIfEmpty }
    }

    /// 卷册，如“第3册”“卷一至卷七”
    var volumeText: String {
        get { volume ?? "" }
        set { volume = newValue.nilIfEmpty }
    }

    /// 书名加卷册，用于书单和标题栏。
    var displayTitle: String {
        guard let volume = volume?.nilIfEmpty else { return title }
        return "\(title) · \(volume)"
    }

    /// 原文件或文件夹名，书名改过后仍可对照。
    var fileName: String {
        let url = URL(fileURLWithPath: localPath)
        return fileType == .imageSequence ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    static func new(
        title: String,
        localPath: String,
        fileType: BookFileType,
        pageCount: Int,
        sourceName: String = ""
    ) -> Book {
        Book(
            id: UUID(),
            title: title,
            author: "",
            dynasty: "",
            edition: "",
            sourceName: sourceName,
            sourceURL: "",
            localPath: localPath,
            fileType: fileType,
            pageCount: pageCount,
            classificationID: Classification.defaultUnclassifiedID,
            tags: [],
            isFavorite: false,
            status: .pending,
            notes: "",
            createdAt: Date(),
            updatedAt: Date(),
            lastReadPage: 0,
            lastReadAt: nil,
            pageRecords: []
        )
    }
}

struct PageRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var bookID: UUID
    var pageIndex: Int
    var imagePath: String
    var ocrText: String
    var correctedText: String
    var notes: String
    var status: String
    var fileIdentity: String? = nil
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
