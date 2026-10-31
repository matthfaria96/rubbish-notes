import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var files: OpenedFiles
    @Binding var query: String
    /// Set in the tabs layout's panel: the box being looked at there, which
    /// changes only the panel. The window follows when a note is picked.
    var browsing: Binding<NoteBox>?
    @StateObject private var renaming = ViewState<UUID?>(nil)
    @StateObject private var confirmEmpty = ViewState(false)
    @StateObject private var confirmClear = ViewState(false)
    @AppStorage(Prefs.focusMode) private var focusMode = false
    /// In the tabs layout this list lives in a panel; the bar's buttons belong to the strip.
    @AppStorage(Prefs.notesLayout) private var layoutRaw = NotesLayout.sidebar.rawValue
    private var hidesBarButtons: Bool { focusMode || layoutRaw == NotesLayout.tabs.rawValue }
    @AppStorage(Prefs.sidebarGlass) private var sidebarGlass = true
    @AppStorage(Prefs.editorTheme) private var themeID = EditorTheme.standard.id

    var body: some View {
        // Each note followed by its sub-notes (unless hidden); search looks inside sub-notes too.
        let pinned = store.outline(store.pinnedNotes(in: box), query: query)
        let others = store.outline(store.listNotes(in: box), query: query)
        let opened = openedFiles
        // The list ends above the box switcher instead of scrolling under it.
        VStack(spacing: 0) {
        List(selection: selection) {
            if !opened.isEmpty {
                Section {
                    ForEach(opened) { OpenedFileRow(file: $0).tag($0.id) }
                } header: {
                    Text("Open Files")
                        .help("Text files from other folders, edited in place as plain text")
                }
            }
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { row($0) }
                        .onMove(perform: query.isEmpty ? { move(pinned, from: $0, to: $1, pinned: true) } : nil)
                } header: {
                    NotesSectionHeader(title: L("Pinned"), box: box, showsToggle: true)
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { row($0) }
                        .onMove(perform: canReorder ? { move(others, from: $0, to: $1, pinned: false) } : nil)
                } header: {
                    NotesSectionHeader(title: sectionTitle, box: box, showsToggle: pinned.isEmpty)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if pinned.isEmpty && others.isEmpty && opened.isEmpty {
                if query.isEmpty { emptyBox } else { ContentUnavailableView.search(text: query) }
            }
        }
            boxSwitcher
        }
        .background { SidebarBackdrop(theme: EditorTheme.named(themeID), glass: sidebarGlass) }
        // Stays put at the top while only the notes scroll beneath it.
        .safeAreaInset(edge: .top, spacing: 0) {
            searchField.padding(.top, browsing == nil ? 0 : 12)
        }
        .onDeleteCommand {
            guard browsing == nil, files.activeID == nil, let id = store.activeID, store.box != .trash else { return }
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
        .toolbar(removing: hidesBarButtons ? .sidebarToggle : nil)
        .toolbar {
            if !hidesBarButtons {
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

    /// Rows are notes and their sub-notes; only notes move, taking their sub-notes along.
    private func move(_ items: [NoteListItem], from source: IndexSet, to destination: Int, pinned: Bool) {
        guard let step = NoteStore.outlineMove(items, from: source, to: destination) else { return }
        let tops = items.filter { !$0.isSubnote }.map(\.id)
        if pinned {
            store.reorderPinned(tops, from: IndexSet(integer: step.from), to: step.to)
        } else {
            store.reorder(tops, from: IndexSet(integer: step.from), to: step.to)
        }
    }

    /// Dragging sets the order of the whole box, so not while searching or in the Trash.
    private var canReorder: Bool { query.isEmpty && box != .trash }

    /// The box this list shows.
    private var box: NoteBox { browsing?.wrappedValue ?? store.box }

    private var sectionTitle: String {
        if !query.isEmpty { return L("Results") }
        switch box {
        case .inbox: return L("Notes")
        case .archive: return L("Archived")
        case .trash: return L("Deleted")
        }
    }

    /// Outside files sit above the notes in the inbox, like the pinned ones.
    private var openedFiles: [OpenedFile] {
        guard box == .inbox else { return [] }
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return files.files }
        return files.files.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// One selection for notes and outside files (their ids never meet).
    private var selection: Binding<UUID?> {
        Binding(
            get: { files.activeID ?? (store.active?.location == box ? store.activeID : nil) },
            set: { id in
                if let id, files.files.contains(where: { $0.id == id }) {
                    files.select(id)
                } else if browsing != nil, let id {
                    store.openNote(id, in: box)
                } else {
                    store.select(id)
                }
            }
        )
    }

    private var boxBinding: Binding<NoteBox> {
        Binding(get: { box }, set: { newBox in
            if let browsing { browsing.wrappedValue = newBox } else { store.show(newBox) }
        })
    }

    @ViewBuilder
    private var emptyBox: some View {
        switch box {
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
            if box == .trash && store.count(in: .trash) > 0 {
                quietChip("Empty Trash", symbol: "trash.slash", help: "Delete every note in the Trash permanently") {
                    confirmEmpty.value = true
                }
            }
            if box == .inbox && store.count(in: .inbox) > 0 {
                clearInboxButton
            }
            BoxSwitcher(selection: boxBinding)
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
        quietChip("Delete All", symbol: "trash", help: "Move every note in the Inbox to the Trash (archived notes stay)") {
            confirmClear.value = true
        }
    }

    /// The small centred glass chip used by Delete All and Empty Trash.
    private func quietChip(_ title: LocalizedStringKey, symbol: String, help: LocalizedStringKey,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .compatGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .help(help)
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: NoteListItem) -> some View {
        let note = item.note
        return NoteRow(
            note: note,
            preview: store.previews[note.id] ?? "",
            modified: note.location == .trash ? note.trashedAt : store.modified[note.id],
            renamingID: $renaming.value,
            isSubnote: item.isSubnote,
            subnoteCount: item.subnoteCount,
            collapsed: item.collapsed
        )
        .tag(note.id)
        .moveDisabled(item.isSubnote)
    }
}

struct NoteRow: View {
    @EnvironmentObject private var store: NoteStore
    let note: NoteEntry
    let preview: String
    let modified: Date?
    @Binding var renamingID: UUID?
    /// Listed under its parent: indented, a little lighter.
    var isSubnote = false
    /// On a parent: its sub-notes, and whether they are hidden.
    var subnoteCount = 0
    var collapsed = false
    @AppStorage(Prefs.sidebarStatus) private var sidebarStatus = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if sidebarStatus { StatusMark(status: note.currentStatus) }
                if renamingID == note.id {
                    RenameField(initial: note.title, onCommit: commitRename, onCancel: { renamingID = nil })
                } else {
                    Text(note.title)
                        .font(.body.weight(isSubnote ? .medium : .semibold))
                        .lineLimit(1)
                }
                if subnoteCount > 0 {
                    Spacer(minLength: 4)
                    SubnoteToggle(count: subnoteCount, collapsed: collapsed) {
                        withAnimation(.smooth(duration: 0.25)) { store.toggleSubnotes(note.id) }
                    }
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
        .subnoteIndent(isSubnote)
        .contentShape(Rectangle())
        .contextMenu {
            NoteContextMenu(note: note) { renamingID = note.id }.labelStyle(.titleAndIcon)
        }
        .swipeActions(edge: .leading) { leadingSwipe }
        .swipeActions(edge: .trailing) { trailingSwipe }
    }

    private func commitRename(_ text: String) {
        guard renamingID == note.id else { return }
        renamingID = nil
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != note.title { store.rename(note.id, to: clean) }
    }

    @ViewBuilder
    private var leadingSwipe: some View {
        switch note.location {
        case .inbox:
            if !isSubnote {
                Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                    store.togglePin(note.id)
                }
                .tint(.orange)
            }
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
            Button("Delete", systemImage: "trash.slash", role: .destructive) { store.requestDeletePermanently(note.id) }
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

/// Inbox / Archive / Trash. Drawn by hand (not a system segmented control)
/// so it takes the theme's text and accent colors.
struct BoxSwitcher: View {
    @Binding var selection: NoteBox
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NoteBox.allCases) { box in
                let selected = box == selection
                Button { selection = box } label: {
                    Text(box.title)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .background {
                            if selected {
                                Capsule()
                                    .fill(.tint.opacity(0.18))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(box.title) (⌘\(NoteBox.allCases.firstIndex(of: box)! + 1))" as String)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .compatGlass(in: Capsule())
        .animation(.smooth(duration: 0.22), value: selection)
    }
}

/// Everything a note offers on a right click, shared by the sidebar and the tabs.
struct NoteContextMenu: View {
    @EnvironmentObject private var store: NoteStore
    let note: NoteEntry
    let onRename: () -> Void

    var body: some View {
        switch note.location {
        case .inbox:
            renameItem
            subnoteItems
            Divider()
            if !store.isNested(note.id) {
                Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                    store.togglePin(note.id)
                }
            }
            statusMenu
            ExportMenu(noteID: note.id)
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .archive:
            renameItem
            subnoteItems
            Divider()
            Button("Unarchive", systemImage: "tray") { store.restore(note.id) }
            ExportMenu(noteID: note.id)
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .trash:
            Button("Restore to Inbox", systemImage: "arrow.uturn.backward") { store.restore(note.id) }
            Divider()
            Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) { store.requestDeletePermanently(note.id) }
        }
    }

    /// New Sub-note on notes that can take one; Show/Hide on notes that have some.
    @ViewBuilder
    private var subnoteItems: some View {
        if store.canAddSubnote(to: note.id) {
            Button("New Sub-note", systemImage: "note.text.badge.plus") { store.newSubnote(under: note.id) }
        }
        if !store.subnotes(of: note.id).isEmpty {
            let collapsed = store.subnotesCollapsed(note.id)
            Button(L(collapsed ? "Show Sub-notes" : "Hide Sub-notes"), systemImage: collapsed ? "chevron.down" : "chevron.up") {
                withAnimation(.smooth(duration: 0.25)) { store.toggleSubnotes(note.id) }
            }
        }
    }

    private var renameItem: some View {
        Button("Change Name", systemImage: "pencil", action: onRename)
    }

    private var statusMenu: some View {
        Menu(L("Status"), systemImage: "circle.fill") {
            ForEach(NoteStatus.allCases) { status in
                Button(status.title) { store.setStatus(note.id, status) }
            }
        }
    }
}
