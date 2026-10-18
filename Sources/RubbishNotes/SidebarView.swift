import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: NoteStore
    let query: String
    @StateObject private var renaming = ViewState<UUID?>(nil)
    @StateObject private var confirmEmpty = ViewState(false)
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
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if pinned.isEmpty && others.isEmpty {
                if query.isEmpty { emptyBox } else { ContentUnavailableView.search(text: query) }
            }
        }
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
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("Delete every note in the Trash permanently")
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
    @StateObject private var draftState = ViewState("")
    @StateObject private var hoverState = ViewState(false)
    @FocusState private var nameFocused: Bool

    private var isRenaming: Bool { renamingID == note.id }
    private var canRename: Bool { note.location != .trash }

    var body: some View {
        HStack(spacing: 6) {
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
                    Text(preview.isEmpty ? L("No additional text") : preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
            if hoverState.value && canRename && !isRenaming {
                Button(action: startRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help("Rename Note")
                .accessibilityLabel("Rename")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hoverState.value = hovering }
        }
        .contextMenu { contextMenu.labelStyle(.titleAndIcon) }
        .swipeActions(edge: .leading) { leadingSwipe }
        .swipeActions(edge: .trailing) { trailingSwipe }
        .onDrag {
            NSItemProvider(contentsOf: store.url(for: note)) ?? NSItemProvider()
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        switch note.location {
        case .inbox:
            Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                store.togglePin(note.id)
            }
            Button("Rename", systemImage: "pencil", action: startRename)
            ShareLink(item: store.url(for: note)) { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
            Divider()
            Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
        case .archive:
            Button("Move to Inbox", systemImage: "tray.and.arrow.up") { store.restore(note.id) }
            Button("Rename", systemImage: "pencil", action: startRename)
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

    private func startRename() {
        guard canRename else { return }
        renamingID = note.id
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
        if calendar.isDateInYesterday(date) { return L("Yesterday") }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
