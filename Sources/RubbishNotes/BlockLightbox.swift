import AppKit
import SwiftUI

extension Notification.Name {
    /// A note block asks to be shown large; the object is an `OpenBlock`, or nil to close.
    static let showBlockLarge = Notification.Name("RubbishNotes.showBlockLarge")
}

/// A note block while it is shown large. Edits, renames and deletes go straight
/// to the block in the note, through the editor that opened it.
final class OpenBlock: ObservableObject {
    @Published var content: String
    @Published var title: String?
    let editable: Bool
    let style: InlineBlockStyle
    var onEdit: (String) -> Void = { _ in }
    var onRename: () -> Void = {}
    var onRemove: () -> Void = {}

    init(content: String, title: String?, editable: Bool, style: InlineBlockStyle) {
        self.content = content
        self.title = title
        self.editable = editable
        self.style = style
    }
}

/// The block over the whole note, with room to read and write. Esc, the
/// shrink button or a click outside closes it.
struct BlockLightbox: View {
    @ObservedObject var block: OpenBlock
    let close: () -> Void
    @State private var copied = false

    private var chrome: Color { Color(nsColor: block.style.background) }
    private var ink: Color { Color(nsColor: block.style.text) }
    private var secondary: Color { Color(nsColor: block.style.secondary) }

    var body: some View {
        ZStack {
            chrome.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            card
                .frame(maxWidth: 820)
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
        }
        .onExitCommand(perform: close)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ink.opacity(0.12))
            BlockTextArea(text: block.content, color: block.style.text, accent: block.style.accent,
                          editable: block.editable, focusOnAppear: block.editable,
                          fontSize: 15, onEscape: close) {
                block.content = $0
                block.onEdit($0)
            }
            .overlay(alignment: .topLeading) {
                if block.content.isEmpty {
                    Text("Write or paste here…")
                        .font(.system(size: 15))
                        .foregroundStyle(secondary.opacity(0.8))
                        .padding(.leading, 4)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(chrome, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ink.opacity(0.14)))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(block.title ?? L("Note block"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Menu {
                BlockMenuItems(content: block.content, title: block.title, editable: block.editable,
                               onRename: block.onRename, onCopy: copy, onRemove: block.onRemove)
            } label: {
                Image(systemName: copied ? "checkmark" : "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            Button(action: close) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondary)
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel(Text("Close"))
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block.content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}

/// The block's ··· menu, the same in the note and in the lightbox: Change Name,
/// Copy and Export above, Delete apart below them.
struct BlockMenuItems: View {
    let content: String
    let title: String?
    let editable: Bool
    let onRename: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if editable {
            Button(action: onRename) {
                Label { Text("Change Name") } icon: { Image(systemName: "pencil") }.labelStyle(.titleAndIcon)
            }
        }
        Button(action: onCopy) {
            Label { Text("Copy Block") } icon: { Image(systemName: "doc.on.doc") }.labelStyle(.titleAndIcon)
        }
        Menu {
            ForEach(BlockExportFormat.allCases) { format in
                Button { NoteExporter.exportBlock(content, title: title, as: format) } label: {
                    Label { Text(format.title) } icon: { Image(systemName: format.symbol) }.labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Label { Text("Export") } icon: { Image(systemName: "square.and.arrow.up") }.labelStyle(.titleAndIcon)
        }
        if editable {
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label { Text("Delete Block") } icon: { Image(systemName: "trash") }.labelStyle(.titleAndIcon)
            }
        }
    }
}
