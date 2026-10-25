import SwiftUI

/// On a parent row: how many sub-notes it has, and a chevron that shows or
/// hides them. A small glass capsule at the row's trailing edge.
struct SubnoteToggle: View {
    let count: Int
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("\(count)").monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .compatGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L(collapsed ? "Show Sub-notes" : "Hide Sub-notes"))
        .accessibilityLabel(Text(L(collapsed ? "Show Sub-notes" : "Hide Sub-notes")))
        .animation(.smooth(duration: 0.2), value: collapsed)
    }
}

/// A section title with, when the box has sub-notes, one chip that hides or
/// shows all of them at once.
struct NotesSectionHeader: View {
    @EnvironmentObject private var store: NoteStore
    let title: String
    let box: NoteBox
    let showsToggle: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 4)
            if showsToggle, !store.parentIDs(in: box).isEmpty {
                CollapseAllSubnotesButton(box: box)
            }
        }
        // The list's header has no trailing inset; keep the chip off the edge.
        .padding(.trailing, 8)
    }
}

/// "Collapse all / expand all" for the sub-notes of a box.
struct CollapseAllSubnotesButton: View {
    @EnvironmentObject private var store: NoteStore
    let box: NoteBox

    var body: some View {
        let expanded = store.anySubnotesExpanded(in: box)
        Button {
            withAnimation(.smooth(duration: 0.25)) { store.setAllSubnotesCollapsed(expanded, in: box) }
        } label: {
            Label(L(expanded ? "Collapse" : "Expand"), systemImage: expanded ? "chevron.up" : "chevron.down")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.medium))
                .textCase(nil)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .compatGlass(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(L(expanded ? "Collapse All Sub-notes" : "Expand All Sub-notes"))
    }
}

extension View {
    /// A sub-note row: indented under its parent, with a thin guide line.
    func subnoteIndent(_ isSubnote: Bool) -> some View {
        padding(.leading, isSubnote ? 16 : 0)
            .overlay(alignment: .leading) {
                if isSubnote {
                    Capsule()
                        .fill(.tint.opacity(0.4))
                        .frame(width: 2)
                        .padding(.vertical, 1)
                        .padding(.leading, 4)
                }
            }
    }
}
