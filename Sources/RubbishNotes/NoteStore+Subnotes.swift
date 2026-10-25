import Foundation

/// Sub-notes: notes that sit under another note, one level deep. Each one is
/// still a plain .txt file in the same folder as its parent; `NoteEntry.parent`
/// links it by id. A sub-note is listed under its parent while both are in the
/// same box, and travels with it to the Archive or the Trash and back. On its
/// own in another box it is listed like any note, and nests again once it is
/// back beside its parent.
extension NoteStore {
    /// Sub-notes listed under their parent right now (parent present, same box).
    var nestedIDs: Set<UUID> {
        let boxes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.location) })
        return Set(notes.filter { note in note.parent.flatMap { boxes[$0] } == note.location }.map(\.id))
    }

    /// The sub-notes listed under `id`, oldest first.
    func subnotes(of id: UUID) -> [NoteEntry] {
        guard let parent = notes.first(where: { $0.id == id }) else { return [] }
        return notes.filter { $0.parent == id && $0.location == parent.location }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Whether the note is listed under a parent.
    func isNested(_ id: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == id }), let parentID = note.parent else { return false }
        return notes.contains { $0.id == parentID && $0.location == note.location }
    }

    /// Only a note outside the Trash that isn't a sub-note itself takes sub-notes
    /// (one level deep, even while a sub-note sits apart from its parent).
    func canAddSubnote(to id: UUID?) -> Bool {
        guard let id, let note = notes.first(where: { $0.id == id }) else { return false }
        return note.location != .trash && note.parent == nil
    }

    /// Creates a sub-note in the parent's box, shows the parent's sub-notes and opens it.
    @discardableResult
    func newSubnote(under parentID: UUID, content: String = "", name: String? = nil) -> UUID? {
        guard canAddSubnote(to: parentID), let parent = notes.first(where: { $0.id == parentID }) else { return nil }
        updateNote(parentID) { $0.subnotesCollapsed = nil }
        return newNote(content: content, name: name, in: parent.location, parent: parentID)
    }

    /// Deletes a trashed note for good; a parent asks first, since its sub-notes go too.
    func requestDeletePermanently(_ id: UUID) {
        if subnotes(of: id).isEmpty { deletePermanently(id) } else { pendingPermanentDelete = id }
    }

    /// Shows the sub-notes around `id` when it is a sub-note, so it can be seen in the list.
    func expandParent(of id: UUID) {
        guard isNested(id), let parent = notes.first(where: { $0.id == id })?.parent else { return }
        updateNote(parent) { $0.subnotesCollapsed = nil }
    }

    func subnotesCollapsed(_ id: UUID) -> Bool {
        notes.first { $0.id == id }?.subnotesCollapsed == true
    }

    func toggleSubnotes(_ id: UUID) {
        let collapse = !subnotesCollapsed(id)
        updateNote(id) { $0.subnotesCollapsed = collapse ? true : nil }
    }

    /// Parents in `box` that have sub-notes listed under them.
    func parentIDs(in box: NoteBox) -> [UUID] {
        let nestedIDs = nestedIDs
        let nested = notes.filter { nestedIDs.contains($0.id) && $0.location == box }
        return Array(Set(nested.compactMap(\.parent)))
    }

    /// True while some parent in the box shows its sub-notes.
    func anySubnotesExpanded(in box: NoteBox) -> Bool {
        parentIDs(in: box).contains { !subnotesCollapsed($0) }
    }

    /// Hides (or shows) every parent's sub-notes in the box at once.
    func setAllSubnotesCollapsed(_ collapsed: Bool, in box: NoteBox) {
        let parents = Set(parentIDs(in: box))
        let changed = notes.filter { parents.contains($0.id) && ($0.subnotesCollapsed == true) != collapsed }
            .map { entry -> NoteEntry in
                var entry = entry
                entry.subnotesCollapsed = collapsed ? true : nil
                return entry
            }
        guard !changed.isEmpty else { return }
        updateNotes(Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) }))
    }

    /// The list as shown: each top-level note followed by its sub-notes, unless
    /// they are hidden. While searching, a parent shows when it or one of its
    /// sub-notes matches, with the matching sub-notes always visible. `keep`
    /// (the open note) stays visible even under a collapsed parent.
    func outline(_ tops: [NoteEntry], query: String, keep: UUID? = nil) -> [NoteListItem] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return tops.flatMap { top -> [NoteListItem] in
            let children = subnotes(of: top.id)
            let collapsed = subnotesCollapsed(top.id)
            let shown: [NoteEntry]
            if searching {
                shown = children.filter { matches($0, query: query) }
                guard matches(top, query: query) || !shown.isEmpty else { return [] }
            } else {
                shown = collapsed ? children.filter { $0.id == keep } : children
            }
            let head = NoteListItem(note: top, isSubnote: false, subnoteCount: children.count,
                                    collapsed: collapsed && !searching)
            return [head] + shown.map { NoteListItem(note: $0, isSubnote: true, subnoteCount: 0, collapsed: false) }
        }
    }

    /// Dragging a row of the outline: only top-level rows move, taking their
    /// sub-notes along. Returns the move in terms of the top-level list, or nil.
    static func outlineMove(_ items: [NoteListItem], from source: IndexSet, to destination: Int) -> (from: Int, to: Int)? {
        guard source.count == 1, let index = source.first, items.indices.contains(index), !items[index].isSubnote else {
            return nil
        }
        let tops = items.filter { !$0.isSubnote }.map(\.id)
        guard let from = tops.firstIndex(of: items[index].id) else { return nil }
        let to = items.prefix(min(destination, items.count)).filter { !$0.isSubnote }.count
        return (from, to)
    }
}

/// One row of a notes list: a note, or a sub-note under the row above.
struct NoteListItem: Identifiable, Equatable {
    let note: NoteEntry
    let isSubnote: Bool
    /// On a parent row: how many sub-notes it has (shown or not).
    let subnoteCount: Int
    /// On a parent row: its sub-notes are hidden.
    let collapsed: Bool

    var id: UUID { note.id }
}
