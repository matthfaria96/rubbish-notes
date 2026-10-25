import Foundation
import Testing
@testable import RubbishNotes

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("RubbishNotesExport-\(UUID().uuidString)", isDirectory: true)
}

/// Lists a zip's entries with the system's unzip.
private func zipEntries(_ zip: URL) throws -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-Z1", zip.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return output.split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/") }.sorted()
}

@Suite("Markdown export with sub-notes")
struct SubnoteExportTests {
    @Test func fileNamesAreSafeAndNeverCollide() {
        let names = NoteExporter.markdownFileNames(for: ["Trip", "trip", "Day 1", "a/b", "Trip", ".."])
        #expect(names == ["Trip.md", "trip 2.md", "Day 1.md", "a-b.md", "Trip 3.md", "untitled.md"])
    }

    @Test func folderHoldsTheNoteThenOneFilePerSubnote() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let parent = MarkdownNote(title: "Trip", text: "Plans\n⟦bloco: Roteiro⟧\nDia 1\n⟦/bloco⟧\n", blocks: [])
        let subnotes = [MarkdownNote(title: "Hotel", text: "Check-in", blocks: ["rodapé"]),
                        MarkdownNote(title: "Trip", text: "same name as the parent", blocks: [])]
        let names = try NoteExporter.writeMarkdownFolder(parent, subnotes: subnotes, into: folder)
        #expect(names == ["Trip.md", "Hotel.md", "Trip 2.md"])

        let main = try String(contentsOf: folder.appendingPathComponent("Trip.md"), encoding: .utf8)
        #expect(main.hasPrefix("# Trip\n\nPlans"))
        #expect(main.contains("## Roteiro"))
        #expect(main.contains("## \(L("Sub-notes"))\n\n- [Hotel](<Hotel.md>)\n- [Trip](<Trip 2.md>)\n"))
        let hotel = try String(contentsOf: folder.appendingPathComponent("Hotel.md"), encoding: .utf8)
        #expect(hotel.hasPrefix("# Hotel\n\nCheck-in"))
        #expect(hotel.contains("rodapé"))
    }

    @Test func zipContainsEveryMarkdownFile() throws {
        let work = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dest = work.appendingPathComponent("Trip.zip")
        let parent = MarkdownNote(title: "Trip", text: "Plans", blocks: [])
        try NoteExporter.writeMarkdownZip(parent, subnotes: [MarkdownNote(title: "Hotel", text: "x", blocks: [])], to: dest)
        #expect(try zipEntries(dest) == ["Trip/Hotel.md", "Trip/Trip.md"])
    }

    @Test func storeExportsTheSubnotesItLists() throws {
        let root = temporaryFolder()
        let defaults = UserDefaults(suiteName: "RubbishNotesExport-\(UUID().uuidString)")!
        defaults.set(true, forKey: Prefs.didSeed)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(rootDir: root, defaults: defaults)
        let parent = try #require(store.newNote(content: "plans", name: "Trip"))
        try #require(store.newSubnote(under: parent, content: "check-in", name: "Hotel") != nil)
        store.editorChanged("check-in at noon")
        let note = try #require(store.notes.first { $0.id == parent })
        let subnotes = store.subnotes(of: parent).map(store.markdownNote)
        #expect(store.markdownNote(note).text == "plans")
        // The open sub-note exports what is in the editor, saved or not.
        #expect(subnotes == [MarkdownNote(title: "Hotel", text: "check-in at noon", blocks: [])])
    }
}
