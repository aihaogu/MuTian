import SwiftUI

/// Collapsible table of contents for the reader; keeps the current entry expanded and in view.
struct ReaderOutlineSidebar: View {
    let entries: [ReaderOutlineEntry]
    let currentID: String?
    let showsTargetNumbers: Bool
    let onSelect: (ReaderOutlineEntry) -> Void

    @State private var expandedIDs: Set<String> = []

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(entries) { entry in
                    ReaderOutlineNode(
                        entry: entry,
                        currentID: currentID,
                        showsTargetNumbers: showsTargetNumbers,
                        expandedIDs: $expandedIDs,
                        onSelect: onSelect
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.bar)
            .onAppear {
                revealCurrent()
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
            .onChange(of: currentID) { _, newValue in
                revealCurrent()
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .frame(width: 230)
    }

    private func revealCurrent() {
        guard let currentID else { return }
        expandedIDs.formUnion(entries.ancestorIDs(of: currentID))
    }
}

private struct ReaderOutlineNode: View {
    let entry: ReaderOutlineEntry
    let currentID: String?
    let showsTargetNumbers: Bool
    @Binding var expandedIDs: Set<String>
    let onSelect: (ReaderOutlineEntry) -> Void

    var body: some View {
        if entry.children.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(entry.children) { child in
                    ReaderOutlineNode(
                        entry: child,
                        currentID: currentID,
                        showsTargetNumbers: showsTargetNumbers,
                        expandedIDs: $expandedIDs,
                        onSelect: onSelect
                    )
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        let isCurrent = entry.id == currentID
        return Button {
            onSelect(entry)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.title)
                    .font(.system(.callout, design: .serif))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? MuTianTheme.accent : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if showsTargetNumbers {
                    Text("\(entry.target + 1)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.title)
        .id(entry.id)
    }

    private var expandedBinding: Binding<Bool> {
        Binding {
            expandedIDs.contains(entry.id)
        } set: { isExpanded in
            if isExpanded { expandedIDs.insert(entry.id) } else { expandedIDs.remove(entry.id) }
        }
    }
}
