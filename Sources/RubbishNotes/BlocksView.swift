import AppKit
import SwiftUI

/// The footer's left corner: a button that opens the note's blocks, long
/// texts kept apart from the scribbles in the note itself.
struct BlocksButton: View {
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID
    @StateObject private var open = ViewState(false)

    var body: some View {
        let count = store.blocks(of: noteID).count
        Button { open.value.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up")
                if count > 0 { Text("\(count)").monospacedDigit() }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .compatGlass(in: Capsule())
        .help("Blocks: long texts kept apart from the note")
        .popover(isPresented: $open.value, arrowEdge: .top) {
            BlocksPanel(noteID: noteID)
        }
    }
}

struct BlocksPanel: View {
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID

    var body: some View {
        let blocks = store.blocks(of: noteID)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Blocks").font(.headline)
                Spacer()
                Button("Paste", systemImage: "doc.on.clipboard", action: pasteBlock)
                    .help("New block from the clipboard")
                    .disabled(NSPasteboard.general.string(forType: .string) == nil)
                Button("New", systemImage: "plus") { store.addBlock(to: noteID) }
                    .help("New empty block")
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            if blocks.isEmpty {
                Text("Keep long texts here, apart from your notes. Paste one in, copy it out whenever you need it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(blocks.indices, id: \.self) { index in
                            BlockCard(noteID: noteID, index: index, text: blocks[index])
                        }
                    }
                }
                .frame(height: min(420, CGFloat(blocks.count) * 166 - 10))
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private func pasteBlock() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return NSSound.beep() }
        store.addBlock(to: noteID, text: text)
    }
}

private struct BlockCard: View {
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID
    let index: Int
    let text: String
    @StateObject private var copied = ViewState(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(L("Block %ld", index + 1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L("%ld characters", text.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Button(action: copy) {
                    Image(systemName: copied.value ? "checkmark" : "doc.on.doc")
                }
                .help("Copy Block")
                Button { store.removeBlock(index, of: noteID) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Block")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            TextEditor(text: binding)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 110)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var binding: Binding<String> {
        Binding(get: { text }, set: { store.updateBlock(index, of: noteID, to: $0) })
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied.value = true
        let state = copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { state.value = false }
    }
}
