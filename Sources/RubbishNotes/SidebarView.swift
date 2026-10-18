import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NoteStore
    let palette: Palette
    @StateObject private var renaming = ViewState<UUID?>(nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !store.pinnedNotes.isEmpty {
                    header("PINNED", showsAdd: false)
                    ForEach(store.pinnedNotes) { row($0) }
                    Spacer().frame(height: 14)
                }
                header("RECENTS", showsAdd: true)
                ForEach(store.recentNotes) { row($0) }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private func header(_ title: String, showsAdd: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(palette.faintC)
            Spacer()
            if showsAdd {
                Button {
                    store.newNote()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.mutedC)
                .help("New note (⌘N)")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 26)
    }

    private func row(_ note: NoteEntry) -> some View {
        NoteRow(
            note: note,
            preview: store.previews[note.id] ?? "",
            isActive: note.id == store.activeID,
            palette: palette,
            renamingID: $renaming.value
        )
    }
}

struct NoteRow: View {
    @EnvironmentObject private var store: NoteStore
    let note: NoteEntry
    let preview: String
    let isActive: Bool
    let palette: Palette
    @Binding var renamingID: UUID?
    @StateObject private var hoverState = ViewState(false)
    @StateObject private var draftState = ViewState("")

    private var hovering: Bool { hoverState.value }
    @FocusState private var nameFocused: Bool

    private var isRenaming: Bool { renamingID == note.id }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Name", text: $draftState.value)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.fgC)
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { renamingID = nil }
                        .onAppear {
                            draftState.value = note.title
                            nameFocused = true
                        }
                        .onChange(of: nameFocused) { if !nameFocused, isRenaming { commitRename() } }
                } else {
                    Text(note.title)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? palette.fgC : palette.fg2C)
                        .lineLimit(1)
                }
                Text(preview.isEmpty ? " " : preview)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.mutedC)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if note.pinned {
                Button {
                    store.togglePin(note.id)
                } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(30))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accentC)
                .help("Unpin")
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? palette.panel2C : (hovering ? palette.panel2C.opacity(0.45) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hoverState.value = $0 }
        .onTapGesture {
            // A click on the open note renames it.
            if isActive { renamingID = note.id } else { store.select(note.id) }
        }
        .contextMenu {
            Button(note.pinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
            Button("Rename") {
                store.select(note.id)
                renamingID = note.id
            }
            ShareLink(item: store.url(for: note)) { Text("Share…") }
            Button("Reveal in Finder") { store.reveal(note.id) }
            Divider()
            Button("Move to Trash") { store.trash(note.id) }
        }
        .onDrag {
            NSItemProvider(contentsOf: store.url(for: note)) ?? NSItemProvider()
        }
        .help(note.fileName)
    }

    private func commitRename() {
        guard isRenaming else { return }
        store.rename(note.id, to: draftState.value)
        renamingID = nil
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }
}
