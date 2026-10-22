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
    @Test func newNotesStartInProgress() throws {
        let (store, root, _) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(name: "a"))
        #expect(store.active?.currentStatus == .inProgress)
        store.setStatus(id, .done)
        #expect(store.active?.currentStatus == .done)
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

@Suite("Clear inbox")
struct ClearInboxTests {
    @Test func inboxGoesToTrashArchiveStays() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(store.newNote(content: "a", name: "a"))
        let b = try #require(store.newNote(content: "b", name: "b"))
        let kept = try #require(store.newNote(content: "k", name: "kept"))
        store.togglePin(b)
        store.archive(kept)
        store.trashAllInbox()
        let boxes = Dictionary(uniqueKeysWithValues: store.notes.map { ($0.id, $0.location) })
        #expect(boxes[a] == .trash && boxes[b] == .trash && boxes[kept] == .archive)
        #expect(store.notes.first { $0.id == b }?.pinned == false)
        #expect(store.count(in: .inbox) == 0)
        let reopened = NoteStore(rootDir: root, defaults: defaults)
        #expect(reopened.count(in: .trash) == 2 && reopened.count(in: .archive) == 1)
    }
}

@Suite("Blocks")
struct BlockTests {
    @Test func addEditRemoveAndPersist() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.newNote(name: "a"))
        #expect(store.addBlock(to: id, text: "first") == 0)
        #expect(store.addBlock(to: id) == 1)
        store.updateBlock(1, of: id, to: "second")
        store.updateBlock(7, of: id, to: "ignored")
        #expect(store.blocks(of: id) == ["first", "second"])
        #expect(NoteStore(rootDir: root, defaults: defaults).blocks(of: id) == ["first", "second"])
        store.removeBlock(0, of: id)
        #expect(store.blocks(of: id) == ["second"])
        store.removeBlock(0, of: id)
        #expect(store.notes.first { $0.id == id }?.blocks == nil)
    }

    @Test func selectingWritesTheIndexLater() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(store.newNote(name: "a"))
        _ = try #require(store.newNote(name: "b"))
        store.select(a)
        store.savePendingIndex()
        #expect(NoteStore(rootDir: root, defaults: defaults).notes.count == 2)
    }
}

@Suite("Blocks panel")
struct BlocksPanelTests {
    @Test func heightGrowsFromMinimumToMaximum() {
        #expect(BlocksPanel.height(for: 0) == BlocksPanel.minHeight)
        #expect(BlocksPanel.height(for: 1) > BlocksPanel.minHeight)
        #expect(BlocksPanel.height(for: 1) < BlocksPanel.maxHeight)
        #expect(BlocksPanel.height(for: 9) == BlocksPanel.maxHeight)
    }
}

@Suite("Pinned order and export")
struct PinnedExportTests {
    @Test func pinnedNotesReorder() throws {
        let (store, root, defaults) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(store.newNote(name: "a"))
        let b = try #require(store.newNote(name: "b"))
        let c = try #require(store.newNote(name: "c"))
        [a, b, c].forEach(store.togglePin)
        let shown = store.pinnedNotes.map(\.id)
        store.reorderPinned(shown, from: IndexSet(integer: 0), to: 3)
        let moved = Array(shown.dropFirst()) + [shown[0]]
        #expect(store.pinnedNotes.map(\.id) == moved)
        #expect(NoteStore(rootDir: root, defaults: defaults).pinnedNotes.map(\.id) == moved)
    }

    @Test func plainTextHasTitleTextThenBlocks() {
        let out = NoteExporter.plainText(title: "Trip", text: "body\n", blocks: ["one", "two"])
        let order = ["Trip", "body", "one", "two"].map { out.range(of: $0)!.lowerBound }
        #expect(order == order.sorted())
    }
}

@Suite("Inline blocks")
struct InlineBlockTests {
    @Test func roundTripsThroughTheEditorAndExportsOpen() {
        let text = "Intro\n⟦bloco recolhido⟧\nline 1\nline 2\n⟦/bloco⟧\nEnd ⟦bloco⟧\n\n⟦/bloco⟧"
        #expect(InlineBlocks.segments(of: text) == [
            .text("Intro\n"), .block(content: "line 1\nline 2", expanded: false),
            .text("\nEnd "), .block(content: "", expanded: true),
        ])
        let attributed = InlineBlocks.attributed(text, attributes: [:])
        #expect(attributed.length == "Intro\n".count + 1 + "\nEnd ".count + 1)
        #expect(InlineBlocks.serialize(attributed) == text)
        let readable = InlineBlocks.readable(text)
        #expect(readable.contains("line 1\nline 2") && !readable.contains("⟦"))
        #expect(!NoteExporter.plainText(title: "t", text: text, blocks: []).contains("⟦"))
    }
}

@Suite("Inline blocks keep emoji")
struct InlineBlockEmojiTests {
    @Test func emojiSurvivesTheEditor() {
        let text = "Oi 👋🏽 tchau\n⟦bloco⟧\n🎉\n⟦/bloco⟧\n"
        #expect(InlineBlocks.serialize(InlineBlocks.attributed(text, attributes: [:])) == text)
    }
}

@Suite("Named inline blocks")
struct NamedInlineBlockTests {
    @Test func titleRoundTripsAndOldBlocksStillRead() {
        let text = "a\n⟦bloco: Endereço⟧\nRua 1\n⟦/bloco⟧\n⟦bloco recolhido: Hotel⟧\nx\n⟦/bloco⟧\n⟦bloco⟧\nsem nome\n⟦/bloco⟧"
        #expect(InlineBlocks.segments(of: text) == [
            .text("a\n"), .block(content: "Rua 1", expanded: true, title: "Endereço"), .text("\n"),
            .block(content: "x", expanded: false, title: "Hotel"), .text("\n"),
            .block(content: "sem nome", expanded: true, title: nil),
        ])
        #expect(InlineBlocks.serialize(InlineBlocks.attributed(text, attributes: [:])) == text)
        #expect(InlineBlocks.readable(text).contains("Endereço:\nRua 1"))
    }
}
