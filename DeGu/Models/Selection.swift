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
