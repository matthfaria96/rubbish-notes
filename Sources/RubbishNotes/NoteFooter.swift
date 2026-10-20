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
            .fill(status.color.gradient)
            .frame(width: 8, height: 8)
            .shadow(color: status.color.opacity(0.7), radius: 2.5)
            .accessibilityLabel(status.title)
    }
}

/// Images kept with the note as reminders, small in the footer, out of the text.
struct AttachmentStrip: View {
    let noteID: UUID
    let urls: [URL]
    let onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(urls, id: \.self) { url in
                AttachmentThumb(url: url) { onRemove(url.lastPathComponent) }
            }
        }
        .padding(5)
        .compatGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AttachmentThumb: View {
    static let side: CGFloat = 40
    let url: URL
    let onRemove: () -> Void
    @StateObject private var image = ViewState<NSImage?>(nil)
    @StateObject private var hovering = ViewState(false)

    var body: some View {
        Group {
            if let picture = image.value {
                Image(nsImage: picture).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering.value {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Remove Image")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onHover { hovering.value = $0 }
        .help(L("Open Image"))
        .onAppear {
            let state = image
            ThumbnailCache.shared.thumbnail(for: url, size: Self.side) { state.value = $0 }
        }
    }
}
