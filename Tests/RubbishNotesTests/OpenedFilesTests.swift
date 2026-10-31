import Foundation
import Testing
@testable import RubbishNotes

/// A notes library, an Open Files list and a folder of outside files, all temporary.
private final class Desk {
    let folder: URL
    let defaults: UserDefaults
    let store: NoteStore
    private let suite: String

    init() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RubbishNotesOpened-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "RubbishNotesOpened-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Prefs.didSeed)
        store = NoteStore(rootDir: folder.appendingPathComponent("Library", isDirectory: true), defaults: defaults)
    }

    func makeFiles() -> OpenedFiles { OpenedFiles(defaults: defaults, notes: store) }

    func write(_ text: String, to name: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: encoding)
        return url
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }
}

@Suite("Open Files")
struct OpenedFilesTests {
    @Test func openingShowsTheFileAndPutsItOnTop() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let readme = try desk.write("# Título\n", to: "README.md")
        let todo = try desk.write("comprar pão", to: "todo.txt")
        files.open(readme)
        let id = files.open(todo)
        #expect(files.activeID == id)
        #expect(files.text == "comprar pão")
        #expect(files.files.map(\.name) == ["todo.txt", "README.md"])
        #expect(files.files.last?.isMarkdown == true)
        // Opening one again moves it up instead of listing it twice.
        files.open(readme)
        #expect(files.files.map(\.name) == ["README.md", "todo.txt"])
        #expect(files.text == "# Título\n")
        // Nothing went into the notes.
        #expect(desk.store.notes.isEmpty)
    }

    @Test func editsAreSavedInPlaceInTheirEncoding() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let url = try desk.write("café", to: "latin.txt", encoding: .windowsCP1252)
        files.open(url)
        #expect(files.text == "café")
        files.editorChanged("café com leite")
        files.flushNow()
        let data = try Data(contentsOf: url)
        #expect(String(data: data, encoding: .windowsCP1252) == "café com leite")
        #expect(String(data: data, encoding: .utf8) == nil)
    }

    @Test func pickingANoteLeavesTheFileAndSavesIt() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let note = try #require(desk.store.newNote(content: "nota", name: "Nota"))
        let url = try desk.write("antes", to: "a.txt")
        files.open(url)
        files.editorChanged("depois")
        // The open note itself, picked again, also brings the notes back.
        desk.store.select(note)
        #expect(files.activeID == nil)
        #expect(desk.store.activeID == note)
        #expect(try String(contentsOf: url, encoding: .utf8) == "depois")
    }

    @Test func theListOutlivesTheAppAndRemovingLeavesTheFile() throws {
        let desk = Desk()
        let url = try desk.write("x", to: "keep.txt")
        let first = desk.makeFiles()
        let id = first.open(url)
        let second = desk.makeFiles()
        #expect(second.files.map(\.id) == [id])
        #expect(second.activeID == nil)
        second.close(id)
        #expect(second.files.isEmpty)
        #expect(desk.makeFiles().files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aFailedSaveKeepsTheTyping() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let url = try desk.write("antes", to: "locked.txt")
        files.open(url)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: url.path)
        files.editorChanged("depois")
        #expect(!files.flushNow())
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
        #expect(files.flushNow())
        #expect(try String(contentsOf: url, encoding: .utf8) == "depois")
    }

    @Test func textThatDidNotReadCleanlyIsNeverWritten() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let url = desk.folder.appendingPathComponent("odd.txt")
        let bytes = Data([0x61, 0x81, 0x62])  // 0x81 is neither UTF-8 nor Windows Latin 1
        try bytes.write(to: url)
        files.open(url)
        #expect(files.readOnly)
        files.editorChanged("changed")
        files.flushNow()
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func aByteOrderMarkIsKept() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let url = desk.folder.appendingPathComponent("bom.txt")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("olá".utf8)).write(to: url)
        files.open(url)
        #expect(!files.readOnly)
        files.editorChanged("olá!")
        files.flushNow()
        #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF]) + Data("olá!".utf8))
    }

    @Test func aMissingFileIsShownAsUnreadable() throws {
        let desk = Desk()
        let files = desk.makeFiles()
        let url = try desk.write("x", to: "gone.txt")
        let id = files.open(url)
        files.leave()
        try FileManager.default.removeItem(at: url)
        files.select(id)
        #expect(files.unreadable)
        files.editorChanged("typed into nothing")
        files.flushNow()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
