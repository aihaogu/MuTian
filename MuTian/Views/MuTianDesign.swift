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
        case .failed, .cancelled: return cinnabar
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

struct MetaPill: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct DetailPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(MuTianTheme.accent)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuTianTheme.detailBackground)
    }
}
