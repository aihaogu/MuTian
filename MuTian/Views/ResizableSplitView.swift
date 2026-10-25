import AppKit
import SwiftUI

enum SplitPaneSide {
    case leading
    case trailing
}

/// Two-pane split whose panes always fit the available width, unlike `HSplitView`,
/// which lets SwiftUI content overflow and get clipped on both edges when space runs out.
struct ResizableSplitView<Leading: View, Trailing: View>: View {
    let resizableSide: SplitPaneSide
    @Binding var paneWidth: Double
    let minPaneWidth: CGFloat
    let maxPaneWidth: CGFloat
    let minOtherWidth: CGFloat
    var showsTrailing: Bool = true
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var dragStartWidth: CGFloat?
    private let dividerWidth: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.width
            let pane = showsTrailing ? resolvedPaneWidth(total: total) : 0
            let other = showsTrailing ? max(total - pane - dividerWidth, 0) : total

            HStack(spacing: 0) {
                leading
                    .frame(width: resizableSide == .leading && showsTrailing ? pane : other, alignment: .leading)
                    .clipped()

                if showsTrailing {
                    divider(total: total, current: pane)
                    trailing
                        .frame(width: resizableSide == .trailing ? pane : other, alignment: .leading)
                        .clipped()
                }
            }
            .frame(width: total, height: proxy.size.height, alignment: .leading)
        }
    }

    private func resolvedPaneWidth(total: CGFloat) -> CGFloat {
        let available = max(total - dividerWidth, 0)
        let upper = min(maxPaneWidth, available - minOtherWidth)
        if upper >= minPaneWidth {
            return min(max(CGFloat(paneWidth), minPaneWidth), upper)
        }
        return (available * minPaneWidth / (minPaneWidth + minOtherWidth)).rounded()
    }

    private func divider(total: CGFloat, current: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: dividerWidth)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartWidth ?? current
                                if dragStartWidth == nil { dragStartWidth = current }
                                let delta = value.translation.width
                                let proposed = resizableSide == .leading ? start + delta : start - delta
                                let available = max(total - dividerWidth, 0)
                                let upper = max(min(maxPaneWidth, available - minOtherWidth), minPaneWidth)
                                paneWidth = Double(min(max(proposed, minPaneWidth), upper))
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            }
            .zIndex(1)
    }
}
