import AppKit
import Foundation
import Testing
@testable import RubbishNotes

/// A notes folder and preferences of its own, removed afterwards.
private final class Library {
    let root: URL
    let defaults: UserDefaults
    let store: NoteStore
    private let suite: String

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RubbishNotesBackup-\(UUID().uuidString)/Rubbish Notes", isDirectory: true)
        suite = "RubbishNotesBackup-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Prefs.didSeed)
        store = NoteStore(rootDir: root, defaults: defaults)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        defaults.removePersistentDomain(forName: suite)
    }
}

private func temporaryFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("RubbishNotesZip-\(UUID().uuidString)-\(name)")
}

private let pixel: Data = {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}()

/// A library with a bit of everything a backup has to carry.
private func fill(_ library: Library) throws -> (parent: UUID, child: UUID, archived: UUID) {
    let store = library.store
    let parent = try #require(store.newNote(content: "Plano\n⟦bloco: Roteiro⟧\nDia 1 — praia 🏖️\n⟦/bloco⟧\n", name: "Viagem"))
    store.setStatus(parent, .done)
    store.togglePin(parent)
    _ = store.addBlock(to: parent, text: "rodapé")
    #expect(store.attachImageData(pixel))
    let child = try #require(store.newSubnote(under: parent, content: "Check-in às 14h", name: "Hotel"))
    let archived = try #require(store.newNote(content: "velha", name: "Antiga"))
    store.archive(archived)
    let trashed = try #require(store.newNote(content: "lixo", name: "Rascunho"))
    store.trash(trashed)
    library.defaults.set("paper", forKey: Prefs.editorTheme)
    library.defaults.set(18.0, forKey: Prefs.fontSize)
    return (parent, child, archived)
}

@Suite("Zip reader")
struct ZipReaderTests {
    @Test func readsWhatTheSystemZips() throws {
        let folder = temporaryFile("folder")
        let zip = temporaryFile("test.zip")
        let out = temporaryFile("out")
        defer { [folder, zip, out].forEach { try? FileManager.default.removeItem(at: $0) } }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        let long = String(repeating: "texto que se repete ", count: 500)
        try "olá 🌍".write(to: folder.appendingPathComponent("Notes/a.txt"), atomically: true, encoding: .utf8)
        try long.write(to: folder.appendingPathComponent("long.txt"), atomically: true, encoding: .utf8)
        try pixel.write(to: folder.appendingPathComponent("p.png"))
        try NoteExporter.zip(folder, to: zip)

        let written = try ZipReader.extract(zip, to: out)
        let top = folder.lastPathComponent
        #expect(Set(written) == ["\(top)/Notes/a.txt", "\(top)/long.txt", "\(top)/p.png"])
        #expect(try String(contentsOf: out.appendingPathComponent("\(top)/Notes/a.txt"), encoding: .utf8) == "olá 🌍")
        #expect(try String(contentsOf: out.appendingPathComponent("\(top)/long.txt"), encoding: .utf8) == long)
        #expect(try Data(contentsOf: out.appendingPathComponent("\(top)/p.png")) == pixel)
    }

    @Test func filesKeepTheirDates() throws {
        let folder = temporaryFile("dated")
        let zip = temporaryFile("dated.zip")
        let out = temporaryFile("out")
        defer { [folder, zip, out].forEach { try? FileManager.default.removeItem(at: $0) } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("old.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let then = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
        try NoteExporter.zip(folder, to: zip)
        try ZipReader.extract(zip, to: out)
        let copy = out.appendingPathComponent("\(folder.lastPathComponent)/old.txt")
        let date = try #require(NoteStore.modificationDate(copy))
        #expect(abs(date.timeIntervalSince(then)) <= 2)
    }

    @Test func namesThatEscapeTheFolderAreSkipped() {
        #expect(ZipReader.safePath("Notes/a.txt") == "Notes/a.txt")
        #expect(ZipReader.safePath("../evil.txt") == nil)
        #expect(ZipReader.safePath("a/../../evil.txt") == nil)
        #expect(ZipReader.safePath("/etc/passwd") == nil)
        #expect(ZipReader.safePath("__MACOSX/Notes/._a.txt") == nil)
        #expect(ZipReader.safePath("Notes/._a.txt") == nil)
    }

    @Test func otherFilesAreNotZips() throws {
        let file = temporaryFile("plain.zip")
        defer { try? FileManager.default.removeItem(at: file) }
        try "not a zip at all, just some text".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: ZipReader.Failure.notAZip) { try ZipReader.extract(file, to: temporaryFile("x")) }
    }

    @Test func crcMatchesTheKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

@Suite("Library backup")
struct BackupTests {
    @Test func aFreshAppGetsEverythingBack() throws {
        let source = Library()
        let ids = try fill(source)
        let zip = temporaryFile(LibraryBackup.defaultFileName())
        defer { try? FileManager.default.removeItem(at: zip) }
        try source.store.exportBackup(to: zip)

        let target = Library()
        _ = target.store.newNote(content: "a note that will be replaced", name: "Old")
        let opened = try target.store.openBackup(zip)
        defer { opened.cleanup() }
        try target.store.replaceLibrary(with: opened.contents)

        let store = target.store
        // Same notes, same ids, same boxes, pins, status, footer blocks and sub-note link.
        #expect(Set(store.notes.map(\.id)) == Set(source.store.notes.map(\.id)))
        for note in source.store.notes {
            let copy = try #require(store.notes.first { $0.id == note.id })
            #expect(copy.fileName == note.fileName)
            #expect(copy.location == note.location)
            #expect(copy.pinned == note.pinned)
            #expect(copy.status == note.status)
            #expect(copy.blocks == note.blocks)
            #expect(copy.parent == note.parent)
            #expect(copy.attachments == note.attachments)
            #expect(store.body(of: copy) == source.store.body(of: note))
        }
        #expect(store.notes.first { $0.id == ids.child }?.parent == ids.parent)
        #expect(store.body(of: store.notes.first { $0.id == ids.parent }!).contains("⟦bloco: Roteiro⟧"))
        let image = try #require(store.attachmentURLs(of: ids.parent).first)
        let original = try #require(source.store.attachmentURLs(of: ids.parent).first)
        #expect(try Data(contentsOf: image) == Data(contentsOf: original))
        #expect(!store.notes.contains { $0.title == "Old" })
        // Settings came along.
        #expect(target.defaults.string(forKey: Prefs.editorTheme) == "paper")
        #expect(target.defaults.double(forKey: Prefs.fontSize) == 18)
        // The replaced notes were kept next to the notes folder, index and all.
        let kept = try keptFolders(next: target.root)
        #expect(kept.count == 1)
        #expect(FileManager.default.fileExists(atPath: kept[0].appendingPathComponent("Notes/Old.txt").path))
        #expect(FileManager.default.fileExists(atPath: kept[0].appendingPathComponent(LibraryBackup.indexName).path))

        // A second import keeps the first one's safety copy.
        try target.store.replaceLibrary(with: opened.contents)
        #expect(try keptFolders(next: target.root).count == 2)
    }

    private func keptFolders(next root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Rubbish Notes (before import") }
    }

    @Test func repeatedIdsAndParentLoopsAreCleanedUp() {
        let a = UUID(), b = UUID(), c = UUID()
        func entry(_ id: UUID, _ name: String, parent: UUID? = nil) -> NoteEntry {
            var entry = NoteEntry(id: id, fileName: name, pinned: false, pinnedAt: nil, lastOpened: Date())
            entry.parent = parent
            return entry
        }
        let cleaned = LibraryBackup.cleaned([
            entry(a, "A.txt", parent: b), entry(b, "B.txt", parent: a), entry(a, "again.txt"),
            entry(c, "a.txt"), entry(UUID(), "Self.txt"),
        ])
        #expect(cleaned.map(\.fileName) == ["A.txt", "B.txt", "Self.txt"])
        #expect(cleaned.allSatisfy { $0.parent == nil })
    }

    @Test func addingKeepsBothAndRenumbersWhatClashes() throws {
        let source = Library()
        let ids = try fill(source)
        let zip = temporaryFile("backup.zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        try source.store.exportBackup(to: zip)

        // Importing into the same library: every note comes in again as a copy.
        let store = source.store
        let before = store.notes.count
        let opened = try store.openBackup(zip)
        defer { opened.cleanup() }
        #expect(try store.mergeLibrary(opened.contents) == before)
        #expect(store.notes.count == before * 2)
        #expect(Set(store.notes.map(\.id)).count == before * 2)
        #expect(store.notes.contains { $0.fileName == "Viagem 2.txt" })
        // The copied sub-note hangs under the copied parent, not the original.
        let parentCopy = try #require(store.notes.first { $0.fileName == "Viagem 2.txt" })
        let childCopy = try #require(store.notes.first { $0.fileName == "Hotel 2.txt" })
        #expect(childCopy.parent == parentCopy.id)
        #expect(parentCopy.id != ids.parent)
        let original = try #require(store.attachmentURLs(of: ids.parent).first)
        let copied = try #require(store.attachmentURLs(of: parentCopy.id).first)
        #expect(copied != original)
        #expect(try Data(contentsOf: copied) == Data(contentsOf: original))
        #expect(store.notes.first { $0.id == ids.archived }?.location == .archive)
    }

    @Test func otherZipsAreRefused() throws {
        let folder = temporaryFile("notes")
        let zip = temporaryFile("other.zip")
        defer { [folder, zip].forEach { try? FileManager.default.removeItem(at: $0) } }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hi".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try NoteExporter.zip(folder, to: zip)
        let library = Library()
        #expect(throws: LibraryBackup.Failure.self) { try library.store.openBackup(zip) }
    }

    @Test func indexNamesThatLeaveTheirFolderAreDropped() throws {
        let folder = temporaryFile("backup")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func entry(_ name: String, attachments: [String]? = nil) -> NoteEntry {
            var entry = NoteEntry(id: UUID(), fileName: name, pinned: false, pinnedAt: nil, lastOpened: Date())
            entry.attachments = attachments
            return entry
        }
        let index = [entry("ok.txt", attachments: ["a.png", "../../x.png"]), entry("../escape.txt"), entry(".hidden.txt"), entry("x.json")]
        try JSONEncoder().encode(index).write(to: folder.appendingPathComponent(LibraryBackup.indexName))
        let contents = try LibraryBackup.read(extracted: folder)
        #expect(contents.notes.map(\.fileName) == ["ok.txt"])
        #expect(contents.notes.first?.attachments == ["a.png"])
    }

    @Test func onlyKnownSettingsAreApplied() {
        let suite = "RubbishNotesSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        LibraryBackup.apply([Prefs.editorTheme: "ocean", "SUFeedURL": "https://evil", Prefs.ruled: true], to: defaults)
        #expect(defaults.string(forKey: Prefs.editorTheme) == "ocean")
        #expect(defaults.bool(forKey: Prefs.ruled))
        #expect(defaults.object(forKey: "SUFeedURL") == nil)
    }
}
