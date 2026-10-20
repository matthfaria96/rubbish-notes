import AppKit
import SwiftUI

/// The footer's left corner: a button that opens the note's blocks, long
/// texts kept apart from the scribbles in the note itself.
struct BlocksButton: View {
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID
    @Binding var open: Bool

    var body: some View {
        let count = store.blocks(of: noteID).count
        Button { open.toggle() } label: {
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

    }
}

/// Always the same size, so it never jumps as blocks come and go.
struct BlocksPanel: View {
    static let size = CGSize(width: 440, height: 520)
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID
    let onClose: () -> Void

    var body: some View {
        let blocks = store.blocks(of: noteID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("Blocks", systemImage: "square.stack.3d.up").font(.headline)
                Spacer()
                Button("Paste", systemImage: "doc.on.clipboard", action: pasteBlock)
                    .help("New block from the clipboard")
                Button("New", systemImage: "plus") { store.addBlock(to: noteID) }
                    .help("New empty block")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .help("Close")
            }
            .labelStyle(.titleAndIcon)
            .padding(14)
            Divider()
            if blocks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text("Keep long texts here, apart from your notes. Paste one in, copy it out whenever you need it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(blocks.indices, id: \.self) { index in
                            BlockCard(noteID: noteID, index: index, text: blocks[index])
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func pasteBlock() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return NSSound.beep() }
        store.addBlock(to: noteID, text: text)
    }
}

private struct BlockCard: View {
    @EnvironmentObject private var store: NoteStore
    let noteID: UUID
    let index: Int
    let text: String
    @StateObject private var copied = ViewState(false)
    /// What the editor shows; typing never waits on the store, so no key is lost.
    @StateObject private var draft = ViewState<String?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Block %ld", index + 1)).font(.callout.weight(.semibold))
                Text(L("%ld characters", current.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(action: copy) {
                    Label(L(copied.value ? "Copied" : "Copy"), systemImage: copied.value ? "checkmark" : "doc.on.doc")
                }
                .help("Copy Block")
                Button(role: .destructive) { store.removeBlock(index, of: noteID) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Block")
            }
            .controlSize(.small)
            // A visible text area, so it reads as editable.
            TextEditor(text: binding)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // A change from outside (a block above deleted) replaces the draft.
        .onChange(of: text) { if text != draft.value { draft.value = nil } }
        .onDisappear(perform: save)
    }

    private var current: String { draft.value ?? text }

    private var binding: Binding<String> {
        Binding(get: { current }, set: { newText in
            draft.value = newText
            scheduleSave()
        })
    }

    private func scheduleSave() {
        let state = draft
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [store, noteID, index] in
            guard let pending = state.value else { return }
            store.updateBlock(index, of: noteID, to: pending)
        }
    }

    private func save() {
        if let pending = draft.value { store.updateBlock(index, of: noteID, to: pending) }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current, forType: .string)
        copied.value = true
        let state = copied
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { state.value = false }
    }
}
