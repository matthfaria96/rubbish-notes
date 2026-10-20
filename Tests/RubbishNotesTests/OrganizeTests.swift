import AppKit
import Foundation
import Testing
@testable import RubbishNotes

private func makeTempStore() -> (NoteStore, URL, UserDefaults) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RubbishNotesOrganize-\(UUID().uuidString)", isDirectory: true)
    let defaults = UserDefaults(suiteName: "RubbishNotesOrganize-\(UUID().uuidString)")!
    defaults.set(true, forKey: Prefs.didSeed)
    return (NoteStore(rootDir: root, defaults: defaults), root, defaults)
}

@Suite("Status")
struct StatusTests {
    @Test func newNotesStartInProgressAndCycleInOrder() throws {
        let (store, root, _) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(name: "a"))
        #expect(store.active?.currentStatus == .inProgress)
        store.cycleStatus(id)
        #expect(store.active?.currentStatus == .done)
        store.cycleStatus(id)
        #expect(store.active?.currentStatus == .open)
        store.cycleStatus(id)
        #expect(store.active?.currentStatus == .inProgress)
    }

    @Test func statusSurvivesRelaunch() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(name: "a"))
        store.setStatus(id, .done)
        let reopened = NoteStore(rootDir: root, defaults: defaults)
        #expect(reopened.notes.first { $0.id == id }?.currentStatus == .done)
    }
}

@Suite("Order")
struct OrderTests {
    @Test func dragOrderOverridesCreationDate() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(store.newNote(name: "a"))
        let b = try #require(store.newNote(name: "b"))
        let c = try #require(store.newNote(name: "c"))
        let shown = store.listNotes.map(\.id)
        #expect(shown == [c, b, a])
        // Drag "c" (top) to the bottom.
        store.reorder(shown, from: IndexSet(integer: 0), to: 3)
        #expect(store.listNotes.map(\.id) == [b, a, c])
        let d = try #require(store.newNote(name: "d"))
        #expect(store.listNotes.map(\.id) == [d, b, a, c])
        #expect(NoteStore(rootDir: root, defaults: defaults).listNotes.map(\.id) == [d, b, a, c])
    }

    @Test func ownFilesAreNotReimported() throws {
        let (store, root, _) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(content: "x", name: "question"))
        let note = try #require(store.notes.first { $0.id == id })
        store.importFiles([store.url(for: note)])
        #expect(store.notes.count == 1)
    }
}

@Suite("Attachments")
struct AttachmentTests {
    @Test func pastedImageIsKeptOutOfTheText() throws {
        let (store, root, _) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(content: "words", name: "a"))
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let tiff = try #require(image.tiffRepresentation)
        #expect(store.attachImageData(tiff))
        let urls = store.attachmentURLs(of: id)
        #expect(urls.count == 1)
        #expect(FileManager.default.fileExists(atPath: urls[0].path))
        #expect(store.text == "words")
        store.removeAttachment(urls[0].lastPathComponent, from: id)
        #expect(store.attachmentURLs(of: id).isEmpty)
        #expect(store.attachImageData(tiff) && store.attachImageData(tiff))
        #expect(store.attachmentURLs(of: id).count == 2)
        store.removeAllAttachments(of: id)
        #expect(store.attachmentURLs(of: id).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentFolder(of: id).path))
    }
}
