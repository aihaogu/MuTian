import Foundation

enum SidebarSelection: Hashable, Codable {
    case all
    case favorites
    case downloads
    case statistics
    case status(BookStatus)
    case classification(String)
    case source(String)
}

extension SidebarSelection {
    var usesBookDetail: Bool {
        switch self {
        case .downloads, .statistics:
            return false
        case .all, .favorites, .status, .classification, .source:
            return true
        }
    }
}
