import Foundation
import Testing
@testable import RubbishNotes

/// Each test gets its own temporary notes folder and preferences, so the
/// real notes and settings are never touched.
private final class Sandbox {
    let root: URL
    let defaults: UserDefaults
    private let suite: String

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RubbishNotesTests-\(UUID().uuidString)", isDirectory: true)
        suite = "RubbishNotesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Prefs.didSeed)
    }

    func makeStore() -> NoteStore { NoteStore(rootDir: root, defaults: defaults) }

    func folder(_ box: NoteBox) -> URL { root.appendingPathComponent(box.folderName, isDirectory: true) }

    func files(in box: NoteBox) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder(box).path)) ?? [])
            .filter { $0.hasSuffix(".txt") }
            .sorted()
    }

    func read(_ name: String, in box: NoteBox = .inbox) -> String? {
        try? String(contentsOf: folder(box).appendingPathComponent(name), encoding: .utf8)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite("File names")
struct FileNameTests {
    @Test func pathSeparatorsBecomeDashes() {
        #expect(NoteStore.sanitize("a/b:c") == "a-b-c")
    }

    @Test func traversalStaysInsideTheFolder() {
        let name = NoteStore.sanitize("../../etc/passwd")
        #expect(!name.contains("/"))
        #expect(!name.hasPrefix("."))
    }

    @Test func leadingDotsAreRemovedSoFilesAreNotHidden() {
        #expect(NoteStore.sanitize("...secret") == "secret")
    }

    @Test func controlAndBidiCharactersAreRemoved() {
        #expect(NoteStore.sanitize("evil\u{202E}txt.exe\u{0007}") == "eviltxt.exe")
    }

    @Test func emptyNamesFallBackToUntitled() {
        #expect(NoteStore.sanitize("   ") == "untitled")
        #expect(NoteStore.sanitize("..") == "untitled")
    }

    @Test func longMultibyteNamesFitTheFileSystemLimit() {
        let name = NoteStore.sanitize(String(repeating: "👩‍👩‍👧‍👦", count: 120))
        #expect(name.utf8.count <= 200)
        #expect(!name.isEmpty)
    }
}

@Suite("Notes on disk", .serialized)
struct NoteStoreTests {
    @Test func newNoteIsWrittenAsTextFile() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let id = try #require(store.newNote())
        #expect(store.activeID == id)
        #expect(box.files(in: .inbox) == ["untitled.txt"])
    }

    @Test func typingIsSavedToTheFile() throws {
        let box = Sandbox()
        let store = box.makeStore()
        try #require(store.newNote(content: "", name: "Draft") != nil)
        store.editorChanged("hello world")
        store.flushNow()
        #expect(box.read("Draft.txt") == "hello world")
    }

    @Test func untitledNotesTakeTheirFirstLineAsTitle() throws {
        let box = Sandbox()
        let store = box.makeStore()
        try #require(store.newNote() != nil)
        store.editorChanged("Groceries\nmilk, bread")
        store.flushNow()
        #expect(box.files(in: .inbox) == ["Groceries.txt"])
        #expect(store.active?.title == "Groceries")
    }

    @Test func manualRenameStopsAutomaticTitles() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let id = try #require(store.newNote())
        store.rename(id, to: "Fixed name")
        store.editorChanged("Something else\nbody")
        store.flushNow()
        #expect(box.files(in: .inbox) == ["Fixed name.txt"])
    }

    @Test func caseOnlyRenameWorks() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let id = try #require(store.newNote(content: "x", name: "shopping"))
        store.rename(id, to: "Shopping")
        #expect(box.files(in: .inbox) == ["Shopping.txt"])
    }

    @Test func duplicateNamesGetANumber() throws {
        let box = Sandbox()
        let store = box.makeStore()
        try #require(store.newNote(content: "a", name: "Idea") != nil)
        try #require(store.newNote(content: "b", name: "Idea") != nil)
        #expect(box.files(in: .inbox) == ["Idea 2.txt", "Idea.txt"])
    }

    @Test func archiveTrashAndRestoreMoveTheFile() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let id = try #require(store.newNote(content: "keep", name: "Note"))
        store.archive(id)
        #expect(box.files(in: .archive) == ["Note.txt"])
        store.trash(id)
        #expect(box.files(in: .trash) == ["Note.txt"])
        #expect(box.files(in: .archive).isEmpty)
        store.restore(id)
        #expect(box.files(in: .inbox) == ["Note.txt"])
        #expect(box.read("Note.txt") == "keep")
    }

    @Test func movingToTrashCanBeUndone() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        let id = try #require(store.newNote(content: "keep", name: "Pinned one"))
        store.togglePin(id)

        undo.beginUndoGrouping()
        store.trash(id)
        undo.endUndoGrouping()
        #expect(box.files(in: .trash) == ["Pinned one.txt"])

        undo.undo()
        #expect(box.files(in: .inbox) == ["Pinned one.txt"])
        #expect(store.notes.first { $0.id == id }?.pinned == true)
    }

    @Test func emptyTrashDeletesOnlyTrashedNotes() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let keep = try #require(store.newNote(content: "a", name: "Keep"))
        let gone = try #require(store.newNote(content: "b", name: "Gone"))
        store.trash(gone)
        store.emptyTrash()
        #expect(box.files(in: .trash).isEmpty)
        #expect(box.files(in: .inbox) == ["Keep.txt"])
        #expect(store.notes.map(\.id) == [keep])
    }

    @Test func outsideEditIsNeverOverwritten() throws {
        let box = Sandbox()
        let store = box.makeStore()
        try #require(store.newNote(content: "original", name: "Shared") != nil)
        store.editorChanged("typed in the app")
        // Another app saves the same file before the autosave fires.
        Thread.sleep(forTimeInterval: 0.01)
        try "edited elsewhere".write(to: box.folder(.inbox).appendingPathComponent("Shared.txt"), atomically: true, encoding: .utf8)
        store.flushNow()
        #expect(box.read("Shared.txt") == "edited elsewhere")
        #expect(box.read("Shared (conflict).txt") == "typed in the app")
    }

    @Test func noteDeletedElsewhereWhileTypingIsWrittenBack() throws {
        let box = Sandbox()
        let store = box.makeStore()
        try #require(store.newNote(content: "x", name: "Fragile") != nil)
        store.editorChanged("work that must survive")
        try FileManager.default.removeItem(at: box.folder(.inbox).appendingPathComponent("Fragile.txt"))
        store.flushNow()
        #expect(box.read("Fragile.txt") == "work that must survive")
    }

    @Test func notesKeepCreationOrderWhenOpened() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let first = try #require(store.newNote(content: "1", name: "First"))
        Thread.sleep(forTimeInterval: 0.01)
        let second = try #require(store.newNote(content: "2", name: "Second"))
        #expect(store.listNotes.map(\.id) == [second, first])
        store.select(first)
        #expect(store.listNotes.map(\.id) == [second, first])
    }

    @Test func notesSurviveARestart() throws {
        let box = Sandbox()
        let id: UUID
        do {
            let store = box.makeStore()
            id = try #require(store.newNote(content: "persist", name: "Kept"))
            store.togglePin(id)
        }
        let reopened = box.makeStore()
        let note = try #require(reopened.notes.first { $0.id == id })
        #expect(note.pinned)
        #expect(note.title == "Kept")
    }

    @Test func indexWithUnknownBoxFallsBackToInbox() throws {
        let box = Sandbox()
        do {
            let store = box.makeStore()
            try #require(store.newNote(content: "x", name: "Old") != nil)
        }
        let indexURL = box.root.appendingPathComponent("notes-index.json")
        var json = try String(contentsOf: indexURL, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"inbox\"", with: "\"someFutureBox\"")
        try json.write(to: indexURL, atomically: true, encoding: .utf8)
        let reopened = box.makeStore()
        #expect(reopened.notes.map(\.title) == ["Old"])
        #expect(reopened.notes.first?.location == .inbox)
    }
}

@Suite("Importing files", .serialized)
struct ImportTests {
    @Test func plainTextImportUsesTheFileName() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let source = box.root.appendingPathComponent("Meeting notes.txt")
        try "agenda".write(to: source, atomically: true, encoding: .utf8)
        store.importFiles([source])
        #expect(box.read("Meeting notes.txt") == "agenda")
    }

    @Test func hiddenAndBidiFileNamesAreCleaned() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let source = box.root.appendingPathComponent(".hidden\u{202E}txt.exe.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        store.importFiles([source])
        #expect(box.files(in: .inbox) == ["hiddentxt.exe.txt"])
    }

    @Test func legacyWordFilesAreRefused() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let source = box.root.appendingPathComponent("old.doc")
        try "binary".write(to: source, atomically: true, encoding: .utf8)
        store.importFiles([source])
        #expect(box.files(in: .inbox).isEmpty)
    }

    @Test func filesOverTwentyMegabytesAreRefused() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let source = box.root.appendingPathComponent("huge.txt")
        try Data(count: NoteStore.maxFileBytes + 1).write(to: source)
        store.importFiles([source])
        #expect(box.files(in: .inbox).isEmpty)
        #expect(store.notice != nil)
    }

    @Test func htmlImportKeepsOnlyTheText() throws {
        let box = Sandbox()
        let store = box.makeStore()
        let source = box.root.appendingPathComponent("page.html")
        try "<html><body><b>Bold</b> words<img src=\"x.png\"></body></html>".write(to: source, atomically: true, encoding: .utf8)
        store.importFiles([source])
        let text = try #require(box.read("page.txt"))
        #expect(text.contains("Bold words"))
        #expect(!text.contains("<"))
        #expect(!text.contains("\u{FFFC}"))
    }
}

@Suite("Counting")
struct CountingTests {
    @Test func countsWords() {
        #expect(Counting.words("") == 0)
        #expect(Counting.words("one two  three\nfour") == 4)
        #expect(Counting.words("leite, pão e café") == 4)
    }
}
