import AppKit
import SwiftUI

/// Three glowing dots; the lit one is the note's status. A click moves it on:
/// Open (red) → In Progress (yellow) → Done (green).
struct StatusDots: View {
    let status: NoteStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ForEach(NoteStatus.allCases) { dot($0) }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Status: %@ — click to change", status.title))
        .accessibilityLabel(L("Status: %@ — click to change", status.title))
        .animation(.easeOut(duration: 0.18), value: status)
    }

    private func dot(_ value: NoteStatus) -> some View {
        let lit = value == status
        return Circle()
            .fill(value.color.gradient)
            .overlay(Circle().fill(.white.opacity(lit ? 0.35 : 0)).padding(2).offset(x: -1, y: -1).blur(radius: 1))
            .frame(width: 9, height: 9)
            .opacity(lit ? 1 : 0.25)
            .shadow(color: lit ? value.color.opacity(0.9) : .clear, radius: 4)
            .scaleEffect(lit ? 1.12 : 1)
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
