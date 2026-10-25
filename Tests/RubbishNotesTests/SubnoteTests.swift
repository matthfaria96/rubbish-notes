import Foundation
import Testing
@testable import RubbishNotes

/// A store on a temporary folder, removed when the test ends.
private final class SubnoteSandbox {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RubbishNotesSubnotes-\(UUID().uuidString)", isDirectory: true)
    let suite = "RubbishNotesSubnotes-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Prefs.didSeed)
    }

    func makeStore() -> NoteStore { NoteStore(rootDir: root, defaults: defaults) }

    func files(in box: NoteBox) -> [String] {
        let folder = root.appendingPathComponent(box.folderName, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".txt") }.sorted()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite("Sub-notes", .serialized)
struct SubnoteTests {
    @Test func subnoteIsATextFileListedUnderItsParent() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(content: "trip", name: "Trip"))
        let child = try #require(store.newSubnote(under: parent, content: "hotel", name: "Hotel"))
        #expect(sandbox.files(in: .inbox) == ["Hotel.txt", "Trip.txt"])
        #expect(store.activeID == child)
        // Only the parent is a top-level row; the sub-note follows it.
        #expect(store.listNotes.map(\.id) == [parent])
        #expect(store.subnotes(of: parent).map(\.id) == [child])
        #expect(store.visible.map(\.id) == [parent, child])
    }

    @Test func linkSurvivesRestartAndRenamingTheParent() throws {
        let sandbox = SubnoteSandbox()
        let parent: UUID, child: UUID
        do {
            let store = sandbox.makeStore()
            parent = try #require(store.newNote(content: "a", name: "Parent"))
            child = try #require(store.newSubnote(under: parent, name: "Child"))
            store.rename(parent, to: "Renamed parent")
        }
        let reopened = sandbox.makeStore()
        #expect(reopened.notes.first { $0.id == parent }?.title == "Renamed parent")
        #expect(reopened.subnotes(of: parent).map(\.id) == [child])
    }

    @Test func onlyOneLevelAndNotInTheTrash() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(name: "P"))
        let child = try #require(store.newSubnote(under: parent, name: "C"))
        #expect(store.newSubnote(under: child) == nil)
        store.trash(parent)
        #expect(store.newSubnote(under: parent) == nil)
    }

    @Test func trashAndRestoreTakeTheSubnotesAlong() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(content: "p", name: "Parent"))
        let child = try #require(store.newSubnote(under: parent, content: "c", name: "Child"))
        store.trash(parent)
        #expect(sandbox.files(in: .trash) == ["Child.txt", "Parent.txt"])
        #expect(sandbox.files(in: .inbox).isEmpty)
        #expect(store.listNotes(in: .trash).map(\.id) == [parent])
        #expect(store.subnotes(of: parent).map(\.id) == [child])

        store.restore(parent)
        #expect(sandbox.files(in: .inbox) == ["Child.txt", "Parent.txt"])
        #expect(store.subnotes(of: parent).map(\.id) == [child])
    }

    @Test func undoingTheTrashBringsTheSubnotesBack() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let parent = try #require(store.newNote(name: "Parent"))
        try #require(store.newSubnote(under: parent, name: "Child") != nil)
        undo.beginUndoGrouping()
        store.trash(parent)
        undo.endUndoGrouping()
        #expect(store.undoNotice == L("Moved to Trash with %ld sub-notes", 1))
        undo.undo()
        #expect(sandbox.files(in: .inbox) == ["Child.txt", "Parent.txt"])
    }

    @Test func aSubnoteMovedAloneListsOnItsOwnAndNestsAgainWhenBack() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(name: "Parent"))
        let child = try #require(store.newSubnote(under: parent, name: "Child"))
        store.archive(child)
        #expect(store.listNotes(in: .archive).map(\.id) == [child])
        #expect(store.subnotes(of: parent).isEmpty)
        store.restore(child)
        #expect(store.subnotes(of: parent).map(\.id) == [child])
        #expect(store.listNotes(in: .inbox).map(\.id) == [parent])
    }

    @Test func deletingTheParentForGoodDeletesItsTrashedSubnotes() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(name: "Parent"))
        try #require(store.newSubnote(under: parent, name: "Gone") != nil)
        let kept = try #require(store.newSubnote(under: parent, name: "Kept"))
        store.archive(kept)
        store.trash(parent)
        store.deletePermanently(parent)
        #expect(sandbox.files(in: .trash).isEmpty)
        #expect(sandbox.files(in: .archive) == ["Kept.txt"])
        // Its parent is gone: the archived sub-note is now an ordinary note.
        #expect(store.notes.first { $0.id == kept }?.parent == nil)
    }

    @Test func parentFileRemovedElsewhereReleasesTheSubnotes() throws {
        let sandbox = SubnoteSandbox()
        let child: UUID
        do {
            let store = sandbox.makeStore()
            let parent = try #require(store.newNote(name: "Parent"))
            child = try #require(store.newSubnote(under: parent, name: "Child"))
        }
        try FileManager.default.removeItem(at: sandbox.root.appendingPathComponent("Notes/Parent.txt"))
        let reopened = sandbox.makeStore()
        #expect(reopened.notes.first { $0.id == child }?.parent == nil)
        #expect(reopened.listNotes.map(\.id) == [child])
    }

    @Test func collapsingHidesSubnotesAndPersists() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let a = try #require(store.newNote(name: "A"))
        let a1 = try #require(store.newSubnote(under: a, name: "A1"))
        let b = try #require(store.newNote(name: "B"))
        let b1 = try #require(store.newSubnote(under: b, name: "B1"))
        let tops = store.listNotes
        #expect(store.outline(tops, query: "").map(\.id) == [b, b1, a, a1])

        store.toggleSubnotes(a)
        #expect(store.outline(tops, query: "").map(\.id) == [b, b1, a])
        #expect(store.outline(tops, query: "").last?.collapsed == true)
        // The open note stays visible under its collapsed parent.
        #expect(store.outline(tops, query: "", keep: a1).map(\.id) == [b, b1, a, a1])

        store.setAllSubnotesCollapsed(true, in: .inbox)
        #expect(store.outline(tops, query: "").map(\.id) == [b, a])
        #expect(!store.anySubnotesExpanded(in: .inbox))
        #expect(sandbox.makeStore().subnotesCollapsed(b))

        store.setAllSubnotesCollapsed(false, in: .inbox)
        #expect(store.outline(tops, query: "").map(\.id) == [b, b1, a, a1])
    }

    @Test func searchFindsSubnotesUnderTheirParent() throws {
        let sandbox = SubnoteSandbox()
        let store = sandbox.makeStore()
        let parent = try #require(store.newNote(content: "plans", name: "Trip"))
        try #require(store.newSubnote(under: parent, content: "flights", name: "Flights") != nil)
        let hotel = try #require(store.newSubnote(under: parent, content: "check-in at noon", name: "Hotel"))
        store.toggleSubnotes(parent)
        // Collapsed, yet a match inside a sub-note shows the parent and that sub-note.
        let found = store.outline(store.listNotes, query: "noon")
        #expect(found.map(\.id) == [parent, hotel])
        #expect(found.first?.collapsed == false)
        #expect(store.outline(store.listNotes, query: "nothing like this").isEmpty)
    }

    @Test func draggingMovesTopLevelRowsOnly() {
        func item(_ sub: Bool) -> NoteListItem {
            NoteListItem(note: NoteEntry(id: UUID(), fileName: "x.txt", pinned: false, pinnedAt: nil, lastOpened: Date()),
                         isSubnote: sub, subnoteCount: 0, collapsed: false)
        }
        // A, A1, A2, B, C
        let items = [item(false), item(true), item(true), item(false), item(false)]
        #expect(NoteStore.outlineMove(items, from: IndexSet(integer: 1), to: 5) == nil)
        // A to the very end: after B and C.
        #expect(NoteStore.outlineMove(items, from: IndexSet(integer: 0), to: 5).map { [$0.from, $0.to] } == [0, 3])
        // C dropped between A1 and A2 lands right after A.
        #expect(NoteStore.outlineMove(items, from: IndexSet(integer: 4), to: 2).map { [$0.from, $0.to] } == [2, 1])
    }
}
