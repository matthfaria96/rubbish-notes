import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NoteStore
    let query: String
    @StateObject private var renaming = ViewState<UUID?>(nil)

    var body: some View {
        let pinned = store.pinnedNotes.filter { store.matches($0, query: query) }
        let recents = store.recentNotes.filter { store.matches($0, query: query) }
        List(selection: selection) {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { row($0) }
                }
            }
            Section(query.isEmpty ? "Notes" : "Results") {
                ForEach(recents) { row($0) }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if !query.isEmpty && pinned.isEmpty && recents.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .onDeleteCommand {
            if let id = store.activeID { store.trash(id) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.newNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .help("New Note (⌘N)")
            }
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { store.activeID }, set: { store.select($0) })
    }

    private func row(_ note: NoteEntry) -> some View {
        NoteRow(
            note: note,
            preview: store.previews[note.id] ?? "",
            modified: store.modified[note.id],
            renamingID: $renaming.value
        )
        .tag(note.id)
    }
}

struct NoteRow: View {
    @EnvironmentObject private var store: NoteStore
    let note: NoteEntry
    let preview: String
    let modified: Date?
    @Binding var renamingID: UUID?
    @StateObject private var draftState = ViewState("")
    @FocusState private var nameFocused: Bool

    private var isRenaming: Bool { renamingID == note.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isRenaming {
                TextField("Name", text: $draftState.value)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renamingID = nil }
                    .onAppear {
                        draftState.value = note.title
                        DispatchQueue.main.async { nameFocused = true }
                    }
                    .onChange(of: nameFocused) { if !nameFocused, isRenaming { commitRename() } }
            } else {
                Text(note.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let modified {
                    Text(Self.dateLabel(modified))
                }
                Text(preview.isEmpty ? "No additional text" : preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                store.togglePin(note.id)
            }
            Button("Rename", systemImage: "pencil") {
                store.select(note.id)
                renamingID = note.id
            }
            ShareLink(item: store.url(for: note)) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        }
        .swipeActions(edge: .leading) {
            Button(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin") {
                store.togglePin(note.id)
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        }
        .onDrag {
            NSItemProvider(contentsOf: store.url(for: note)) ?? NSItemProvider()
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        store.rename(note.id, to: draftState.value)
        renamingID = nil
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    /// Notes-style dates: time today, "Yesterday", weekday this week, else a short date.
    static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
