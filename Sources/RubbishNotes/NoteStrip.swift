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
    @EnvironmentObject private var files: OpenedFiles
    @Binding var query: String
    @StateObject private var renaming = ViewState<UUID?>(nil)
    @StateObject private var showAll = ViewState(false)
    @StateObject private var dropTarget = ViewState<UUID?>(nil)
    /// The box shown in the All Notes panel; switching it doesn't move the window.
    @StateObject private var browsing = ViewState(NoteBox.inbox)

    var body: some View {
        // Sub-notes follow their parent's tab; the open one stays even when hidden.
        let pinned = store.outline(store.pinnedNotes, query: query, keep: store.activeID)
        let others = store.outline(store.listNotes, query: query, keep: store.activeID)
        HStack(spacing: 8) {
            boxMenu
            Divider().frame(height: 18)
            tabs(pinned: pinned, others: others)
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
        .onChange(of: files.activeID) { showAll.value = false }
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

    private func tabs(pinned: [NoteListItem], others: [NoteListItem]) -> some View {
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

    @ViewBuilder
    private func tab(_ item: NoteListItem, group: [NoteListItem]) -> some View {
        let note = item.note
        let tab = NoteTab(
            note: note,
            selected: note.id == store.activeID && files.activeID == nil,
            dropBefore: dropTarget.value == note.id,
            renamingID: $renaming.value,
            item: item
        )
        .id(note.id)
        // Sub-notes keep their place after the parent; only notes are dragged.
        if item.isSubnote {
            tab
        } else {
            tab
                .draggable(note.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    return move(dragged, before: note.id, in: group)
                } isTargeted: { inside in
                    if inside { dropTarget.value = note.id } else if dropTarget.value == note.id { dropTarget.value = nil }
                }
        }
    }

    /// Dropping one tab on another puts it just before that one (same group only).
    private func move(_ dragged: UUID, before target: UUID, in group: [NoteListItem]) -> Bool {
        dropTarget.value = nil
        let ids = group.filter { !$0.isSubnote }.map(\.id)
        guard query.isEmpty, store.box != .trash, dragged != target,
              let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target) else { return false }
        if group.first?.note.pinned == true {
            store.reorderPinned(ids, from: IndexSet(integer: from), to: to)
        } else {
            store.reorder(ids, from: IndexSet(integer: from), to: to)
        }
        return true
    }

    /// The full list in a panel: everything the sidebar offers.
    private var allNotesButton: some View {
        Button {
            if !showAll.value { browsing.value = store.box }
            showAll.value.toggle()
        } label: {
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
            SidebarView(query: $query, browsing: $browsing.value)
                .frame(width: 320, height: 540)
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
    /// Its place in the outline: a sub-note, or a parent with sub-notes.
    var item: NoteListItem?
    @AppStorage(Prefs.sidebarStatus) private var showStatus = true
    @StateObject private var hovering = ViewState(false)

    private var isSubnote: Bool { item?.isSubnote ?? false }

    var body: some View {
        HStack(spacing: 5) {
            if isSubnote {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tint.opacity(0.7))
            }
            if showStatus { StatusMark(status: note.currentStatus) }
            if note.pinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if renamingID == note.id {
                RenameField(initial: note.title, onCommit: commitRename, onCancel: { renamingID = nil })
                    .frame(width: 150)
            } else {
                // Long names end in "…" so more tabs fit, above all in small windows.
                Text(note.title)
                    .font((isSubnote ? Font.footnote : .callout).weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: isSubnote ? 100 : 120)
            }
            if let item, item.subnoteCount > 0 {
                SubnoteToggle(count: item.subnoteCount, collapsed: item.collapsed) {
                    withAnimation(.smooth(duration: 0.25)) { store.toggleSubnotes(note.id) }
                }
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
