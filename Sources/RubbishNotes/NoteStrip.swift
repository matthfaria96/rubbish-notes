import AppKit
import SwiftUI

/// How the notes list is laid out: the sidebar, or tabs across the top.
enum NotesLayout: String, CaseIterable, Identifiable {
    case sidebar, tabs
    var id: String { rawValue }
    var title: String { L(self == .sidebar ? "Sidebar (vertical)" : "Tabs (horizontal)") }
    var symbol: String { self == .sidebar ? "sidebar.left" : "rectangle.split.3x1" }
}

/// The horizontal layout: a strip of note tabs above the open note. Pinned
/// notes come first. With many notes the strip scrolls and keeps the open one
/// in view, and "All Notes" opens the full list (the same one as the sidebar,
/// with sections, reordering, Delete All and Empty Trash).
struct NoteStrip: View {
    @EnvironmentObject private var store: NoteStore
    @Binding var query: String
    @StateObject private var renaming = ViewState<UUID?>(nil)
    @StateObject private var showAll = ViewState(false)
    @StateObject private var dropTarget = ViewState<UUID?>(nil)

    var body: some View {
        let pinned = store.pinnedNotes.filter { store.matches($0, query: query) }
        let others = store.listNotes.filter { store.matches($0, query: query) }
        HStack(spacing: 8) {
            boxMenu
            Divider().frame(height: 18)
            tabs(pinned: pinned, others: others)
            searchField
            allNotesButton
            Button {
                store.newNote()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Note (⌘N)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: store.activeID) { showAll.value = false }
    }

    // MARK: Pieces

    /// Inbox / Archive / Trash, with how many notes each holds.
    private var boxMenu: some View {
        Menu {
            ForEach(NoteBox.allCases) { box in
                Button {
                    store.show(box)
                } label: {
                    Label("\(box.title) (\(store.count(in: box)))", systemImage: box == store.box ? "checkmark" : box.symbol)
                        .labelStyle(.titleAndIcon)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.box.symbol)
                Text(store.box.title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.tint.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show")
    }

    private func tabs(pinned: [NoteEntry], others: [NoteEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pinned) { tab($0, group: pinned) }
                    if !pinned.isEmpty, !others.isEmpty {
                        Divider().frame(height: 16).padding(.horizontal, 4)
                    }
                    ForEach(others) { tab($0, group: others) }
                    if pinned.isEmpty, others.isEmpty {
                        Text(query.isEmpty ? L("No Notes") : L("No Results"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 2)
            }
            // Soft edges hint that more tabs scroll in from either side.
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.025),
                                       .init(color: .black, location: 0.975), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .onChange(of: store.activeID, initial: true) {
                guard let id = store.activeID else { return }
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tab(_ note: NoteEntry, group: [NoteEntry]) -> some View {
        NoteTab(
            note: note,
            selected: note.id == store.activeID,
            dropBefore: dropTarget.value == note.id,
            renamingID: $renaming.value
        )
        .id(note.id)
        .draggable(note.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            return move(dragged, before: note.id, in: group)
        } isTargeted: { inside in
            if inside { dropTarget.value = note.id } else if dropTarget.value == note.id { dropTarget.value = nil }
        }
    }

    /// Dropping one tab on another puts it just before that one (same group only).
    private func move(_ dragged: UUID, before target: UUID, in group: [NoteEntry]) -> Bool {
        dropTarget.value = nil
        let ids = group.map(\.id)
        guard query.isEmpty, store.box != .trash, dragged != target,
              let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target) else { return false }
        if group.first?.pinned == true {
            store.reorderPinned(ids, from: IndexSet(integer: from), to: to)
        } else {
            store.reorder(ids, from: IndexSet(integer: from), to: to)
        }
        return true
    }

    private var searchField: some View {
        HStack(spacing: 5) {
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
        .font(.callout)
        .padding(.horizontal, 9)
        .frame(width: 170, height: 28)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    /// The full list in a panel: everything the sidebar offers.
    private var allNotesButton: some View {
        Button { showAll.value.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text("\(store.count(in: store.box))").monospacedDigit()
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.secondary.opacity(showAll.value ? 0.2 : 0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("All Notes")
        .popover(isPresented: $showAll.value, arrowEdge: .bottom) {
            SidebarView(query: $query)
                .frame(width: 320, height: 520)
        }
    }
}

/// One note in the strip: its status, a pin when pinned, and the name.
struct NoteTab: View {
    @EnvironmentObject private var store: NoteStore
    let note: NoteEntry
    let selected: Bool
    /// A dragged tab would land just before this one.
    let dropBefore: Bool
    @Binding var renamingID: UUID?
    @AppStorage(Prefs.sidebarStatus) private var showStatus = true
    @StateObject private var hovering = ViewState(false)

    var body: some View {
        HStack(spacing: 5) {
            if showStatus { StatusMark(status: note.currentStatus) }
            if note.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if renamingID == note.id {
                RenameField(initial: note.title, onCommit: commitRename, onCancel: { renamingID = nil })
                    .frame(width: 150)
            } else {
                Text(note.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 170)
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(
            Capsule().fill(selected ? AnyShapeStyle(.tint.opacity(0.16))
                                    : AnyShapeStyle(Color.secondary.opacity(hovering.value ? 0.1 : 0)))
        )
        .overlay(alignment: .leading) {
            if dropBefore {
                Capsule().fill(.tint).frame(width: 3).padding(.vertical, 2).offset(x: -3)
            }
        }
        .contentShape(Capsule())
        .onHover { hovering.value = $0 }
        .onTapGesture { store.select(note.id) }
        .contextMenu {
            NoteContextMenu(note: note) { renamingID = note.id }.labelStyle(.titleAndIcon)
        }
        .help(note.title)
        .animation(.easeOut(duration: 0.12), value: hovering.value)
    }

    private func commitRename(_ text: String) {
        guard renamingID == note.id else { return }
        renamingID = nil
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != note.title { store.rename(note.id, to: clean) }
    }
}
