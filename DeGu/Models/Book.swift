import Foundation

enum BookFileType: String, Codable, CaseIterable, Identifiable {
    case pdf = "PDF"
    case imageSequence = "图片序列"
    case text = "文本"
    case mixedFolder = "混合目录"

    var id: String { rawValue }
}

enum BookStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "待整理"
    case organized = "已整理"
    case needsProofreading = "需校对"
    case proofreading = "校对中"
    case proofread = "已校对"

    var id: String { rawValue }
}

struct Book: Identifiable, Codable, Hashable {
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

struct PageRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    var pageIndex: Int
    var imagePath: String
    var ocrText: String
    var correctedText: String
    var notes: String
    var status: String
}
