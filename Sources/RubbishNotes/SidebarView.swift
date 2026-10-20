import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NoteStore
    @Binding var query: String
    @StateObject private var renaming = ViewState<UUID?>(nil)
    @StateObject private var confirmEmpty = ViewState(false)
    @StateObject private var confirmClear = ViewState(false)
    @AppStorage(Prefs.focusMode) private var focusMode = false

    var body: some View {
        let pinned = store.pinnedNotes.filter { store.matches($0, query: query) }
        let others = store.listNotes.filter { store.matches($0, query: query) }
        List(selection: selection) {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { row($0) }
                }
            }
            if !others.isEmpty {
                Section(sectionTitle) {
                    ForEach(others) { row($0) }
                        .onMove(perform: canReorder ? { store.reorder(others.map(\.id), from: $0, to: $1) } : nil)
                }
            }
        }
        .listStyle(.sidebar)
        .compatHardBottomEdge()
        .overlay {
            if pinned.isEmpty && others.isEmpty {
                if query.isEmpty { emptyBox } else { ContentUnavailableView.search(text: query) }
            }
        }
        // Stays put at the top while only the notes scroll beneath it.
        .safeAreaInset(edge: .top, spacing: 0) { searchField }
        .safeAreaInset(edge: .bottom, spacing: 0) { boxSwitcher }
        .onDeleteCommand {
            guard let id = store.activeID, store.box != .trash else { return }
            store.trash(id)
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty.value) {
            Button("Empty Trash", role: .destructive) { store.emptyTrash() }
        } message: {
            let count = store.count(in: .trash)
            Text(count == 1 ? L("1 note will be deleted permanently. You can’t undo this.")
                            : L("%ld notes will be deleted permanently. You can’t undo this.", count))
        }
        .confirmationDialog("Delete all notes?", isPresented: $confirmClear.value) {
            Button("Move All to Trash", role: .destructive) { store.trashAllInbox() }
        } message: {
            let count = store.count(in: .inbox)
            Text(count == 1 ? L("1 note goes to the Trash. Archived notes stay.")
                            : L("%ld notes go to the Trash. Archived notes stay.", count))
        }
        .toolbar(removing: focusMode ? .sidebarToggle : nil)
        .toolbar {
            if !focusMode {
                ToolbarItem(placement: .primaryAction) { newNoteButton }
            }
        }
    }

    private var newNoteButton: some View {
                Button {
                    store.newNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .help("New Note (⌘N)")
    }

    /// Dragging sets the order of the whole box, so not while searching or in the Trash.
    private var canReorder: Bool { query.isEmpty && store.box != .trash }

    private var sectionTitle: String {
        if !query.isEmpty { return L("Results") }
        switch store.box {
        case .inbox: return L("Notes")
        case .archive: return L("Archived")
        case .trash: return L("Deleted")
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { store.activeID }, set: { store.select($0) })
    }

    private var boxBinding: Binding<NoteBox> {
        Binding(get: { store.box }, set: { store.show($0) })
    }

    @ViewBuilder
    private var emptyBox: some View {
        switch store.box {
        case .inbox:
            ContentUnavailableView("No Notes", systemImage: "tray", description: Text("Notes you write appear here."))
        case .archive:
            ContentUnavailableView("No Archived Notes", systemImage: "archivebox",
                                   description: Text("Archive notes to keep them out of the way."))
        case .trash:
            ContentUnavailableView("Trash Is Empty", systemImage: "trash",
                                   description: Text("Deleted notes stay here until you empty the Trash."))
        }
    }

    /// Inbox, Archive and Trash at the foot of the sidebar.
    private var boxSwitcher: some View {
        VStack(spacing: 10) {
            if store.box == .trash && store.count(in: .trash) > 0 {
                Button(role: .destructive) {
                    confirmEmpty.value = true
                } label: {
                    Label("Empty Trash", systemImage: "trash.slash")
                        .frame(maxWidth: .infinity)
                }
                .compatGlassButtonStyle()
                .controlSize(.large)
                .help("Delete every note in the Trash permanently")
            }
            if store.box == .inbox && store.count(in: .inbox) > 0 {
                clearInboxButton
            }
            Picker("Show", selection: boxBinding) {
                ForEach(NoteBox.allCases) { box in
                    Label(box.title, systemImage: box.symbol)
                        .help("\(box.title) (⌘\(NoteBox.allCases.firstIndex(of: box)! + 1))" as String)
                        .tag(box)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// Quiet on purpose: a small floating chip, and it always asks first.
    private var clearInboxButton: some View {
        HStack {
            Spacer()
            Button { confirmClear.value = true } label: {
                Label("Delete All", systemImage: "trash")
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .compatGlass(in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Move every note in the Inbox to the Trash (archived notes stay)")
        }
    }

    private func row(_ note: NoteEntry) -> some View {
        NoteRow(
            note: note,
            preview: store.previews[note.id] ?? "",
            modified: note.location == .trash ? note.trashedAt : store.modified[note.id],
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
    @AppStorage(Prefs.sidebarStatus) private var sidebarStatus = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if sidebarStatus { StatusMark(status: note.currentStatus) }
                if renamingID == note.id {
                    RenameField(initial: note.title, onCommit: commitRename, onCancel: { renamingID = nil })
                } else {
                    Text(note.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                if let modified {
                    Text(Self.dateLabel(modified))
                }
                Text(preview.isEmpty ? L("No additional text") : preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu { contextMenu.labelStyle(.titleAndIcon) }
        .swipeActions(edge: .leading) { leadingSwipe }
        .swipeActions(edge: .trailing) { trailingSwipe }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch note.location {
        case .inbox:
            renameItem
            Divider()
            Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                store.togglePin(note.id)
            }
            statusMenu
            ShareLink(item: store.url(for: note)) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .archive:
            renameItem
            Divider()
            Button("Move to Inbox", systemImage: "tray.and.arrow.up") { store.restore(note.id) }
            ShareLink(item: store.url(for: note)) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .trash:
            Button("Restore to Inbox", systemImage: "arrow.uturn.backward") { store.restore(note.id) }
            Divider()
            Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) { store.deletePermanently(note.id) }
        }
    }

    private var renameItem: some View {
        Button("Change Name", systemImage: "pencil") { renamingID = note.id }
    }

    private func commitRename(_ text: String) {
        guard renamingID == note.id else { return }
        renamingID = nil
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != note.title { store.rename(note.id, to: clean) }
    }

    private var statusMenu: some View {
        Menu(L("Status"), systemImage: "circle.fill") {
            ForEach(NoteStatus.allCases) { status in
                Button(status.title) { store.setStatus(note.id, status) }
            }
        }
    }

    @ViewBuilder
    private var leadingSwipe: some View {
        switch note.location {
        case .inbox:
            Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                store.togglePin(note.id)
            }
            .tint(.orange)
        case .archive, .trash:
            Button("Restore", systemImage: "tray.and.arrow.up") { store.restore(note.id) }
                .tint(.blue)
        }
    }

    @ViewBuilder
    private var trailingSwipe: some View {
        switch note.location {
        case .inbox:
            Button("Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
            Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
                .tint(.indigo)
        case .archive:
            Button("Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .trash:
            Button("Delete", systemImage: "trash.slash", role: .destructive) { store.deletePermanently(note.id) }
        }
    }

    /// Notes-style dates: time today, "Yesterday", weekday this week, else a short date.
    static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
