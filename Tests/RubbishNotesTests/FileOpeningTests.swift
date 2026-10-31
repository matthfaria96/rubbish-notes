import Foundation
import Testing
@testable import RubbishNotes

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("RubbishNotesOpen-\(UUID().uuidString)", isDirectory: true)
}

@Suite("Opening files from the Finder")
struct FileOpeningTests {
    @Test func libraryNotesOpenAsNotesAndOtherTextGoesToOpenFiles() throws {
        let root = temporaryFolder()
        let defaults = UserDefaults(suiteName: "RubbishNotesOpen-\(UUID().uuidString)")!
        defaults.set(true, forKey: Prefs.didSeed)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(rootDir: root, defaults: defaults)
        let id = try #require(store.newNote(content: "x", name: "Mine"))
        let note = try #require(store.notes.first { $0.id == id })

        #expect(FileOpening.route(store.url(for: note), in: store) == .note(note))
        #expect(FileOpening.route(root.appendingPathComponent("notes-index.json"), in: store) == .library)
        let outside = FileManager.default.temporaryDirectory
        #expect(FileOpening.route(outside.appendingPathComponent("letter.txt"), in: store) == .outsideFile)
        #expect(FileOpening.route(outside.appendingPathComponent("readme.md"), in: store) == .outsideFile)
        #expect(FileOpening.route(outside.appendingPathComponent("page.rtf"), in: store) == .importFile)
        // Nothing was imported along the way.
        #expect(store.notes.count == 1)
    }

    @Test func textIsReadInItsOwnEncoding() {
        #expect(PlainTextDocument.decode(Data("olá".utf8)) == ("olá", .utf8))
        #expect(PlainTextDocument.decode(Data([0xEF, 0xBB, 0xBF] + Array("bom".utf8))).text == "bom")
        let latin = PlainTextDocument.decode(Data([0x63, 0x61, 0x66, 0xE9]))
        #expect(latin == ("café", .windowsCP1252))
        let utf16 = PlainTextDocument.decode("ünï".data(using: .utf16)!)
        #expect(utf16.text == "ünï")
    }
}
