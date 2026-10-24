import SwiftUI

enum MuTianTheme {
    static let accent = Color(red: 0.62, green: 0.26, blue: 0.13)
    static let jade = Color(red: 0.20, green: 0.45, blue: 0.37)
    static let indigo = Color(red: 0.24, green: 0.30, blue: 0.52)
    static let cinnabar = Color(red: 0.72, green: 0.18, blue: 0.14)
    static let paper = Color(nsColor: .textBackgroundColor)
    static let detailBackground = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)

    static func statusColor(_ status: BookStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .organized: return jade
        case .needsProofreading: return cinnabar
        case .proofreading: return indigo
        case .proofread: return accent
        }
    }

    static func downloadColor(_ status: DownloadStatus) -> Color {
        switch status {
        case .waiting: return .secondary
        case .running: return indigo
        case .completed, .imported: return jade
        case .failed, .cancelled, .interrupted: return cinnabar
        }
    }

    static func fileTypeIcon(_ type: BookFileType) -> String {
        switch type {
        case .pdf: "doc.richtext"
        case .imageSequence: "photo.on.rectangle"
        case .text: "text.page"
        case .ebook: "book"
        case .document: "doc"
        case .archive: "archivebox"
        case .mixedFolder: "folder"
        }
    }
}

struct MuTianPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MuTianTheme.hairline, lineWidth: 1)
            }
    }
}

extension View {
    func muTianPanel() -> some View {
        modifier(MuTianPanelModifier())
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct DetailPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
    }
}
