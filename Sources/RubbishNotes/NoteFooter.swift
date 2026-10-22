import AppKit
import SwiftUI

/// The note's status: three dots, one per state. Each is a button that sets
/// it; the current one is lit and ringed, and its name sits beside them.
struct StatusDots: View {
    let status: NoteStatus
    let onSelect: (NoteStatus) -> Void

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 3) {
                ForEach(NoteStatus.allCases) { dot($0) }
            }
            Text(status.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(status.color)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.opacity)
        }
        .animation(.easeOut(duration: 0.18), value: status)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Status: %@ — click to change", status.title))
    }

    private func dot(_ value: NoteStatus) -> some View {
        let lit = value == status
        return Button { onSelect(value) } label: {
            Circle()
                .fill(value.color.gradient)
                .frame(width: 8, height: 8)
                .opacity(lit ? 1 : 0.3)
                .shadow(color: lit ? value.color.opacity(0.8) : .clear, radius: 3)
                .padding(3)
                .overlay(Circle().strokeBorder(value.color.opacity(lit ? 0.9 : 0), lineWidth: 1.5))
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(value.title)
        .accessibilityLabel(value.title)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// The sidebar's status mark before a title.
struct StatusMark: View {
    let status: NoteStatus

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 5, height: 5)
            .opacity(0.75)
            .accessibilityLabel(status.title)
    }
}
