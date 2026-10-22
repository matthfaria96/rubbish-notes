import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Where a note stands: open (red), in progress (yellow), done (green).
enum NoteStatus: String, Codable, CaseIterable, Identifiable {
    case open, inProgress, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: L("Open")
        case .inProgress: L("In Progress")
        case .done: L("Done")
        }
    }

    var color: Color {
        switch self {
        case .open: Color(red: 1.0, green: 0.27, blue: 0.23)
        case .inProgress: Color(red: 1.0, green: 0.78, blue: 0.1)
        case .done: Color(red: 0.2, green: 0.84, blue: 0.35)
        }
    }

    /// Open → In Progress → Done → Open.
    var next: NoteStatus {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// An unknown value reads as open instead of failing the whole index.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoteStatus(rawValue: raw) ?? .open
    }
}

extension NoteEntry {
    var currentStatus: NoteStatus { status ?? .open }
}

// MARK: Status and order

extension NoteStore {
    func setStatus(_ id: UUID, _ status: NoteStatus) {
        updateNote(id) { $0.status = status }
    }

    func cycleStatus(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        setStatus(id, note.currentStatus.next)
    }

    /// Dragging among the pinned notes: their pin dates are rewritten in the new order.
    func reorderPinned(_ ids: [UUID], from source: IndexSet, to destination: Int) {
        var order = ids
        order.move(fromOffsets: source, toOffset: destination)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let dated = order.enumerated().compactMap { index, id -> (UUID, NoteEntry)? in
            guard var entry = byID[id] else { return nil }
            entry.pinnedAt = start.addingTimeInterval(Double(index))
            return (id, entry)
        }
        updateNotes(Dictionary(uniqueKeysWithValues: dated))
    }

    /// Dragging in the sidebar: `ids` is the list as shown, rows at `source` go to `destination`.
    func reorder(_ ids: [UUID], from source: IndexSet, to destination: Int) {
        var order = ids
        order.move(fromOffsets: source, toOffset: destination)
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let ranked = order.enumerated().compactMap { index, id -> (UUID, NoteEntry)? in
            guard var entry = byID[id] else { return nil }
            entry.rank = Double(index)
            return (id, entry)
        }
        updateNotes(Dictionary(uniqueKeysWithValues: ranked))
    }
}

// MARK: Export

extension NoteStore {
    /// Exports any note (open or not) with its blocks and images.
    func exportNote(_ id: UUID, as format: NoteExportFormat) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        if id == activeID { flushNow() }
        let body = id == activeID ? text : ((try? String(contentsOf: url(for: note), encoding: .utf8)) ?? "")
        NoteExporter.export(title: note.title, text: body, blocks: blocks(of: id),
                            images: attachmentURLs(of: id), as: format)
    }
}

// MARK: Blocks

extension NoteStore {
    func blocks(of id: UUID) -> [String] {
        notes.first { $0.id == id }?.blocks ?? []
    }

    /// Adds a block (empty, or pasted text) at the end. Returns its position.
    @discardableResult
    func addBlock(to id: UUID, text: String = "") -> Int? {
        guard notes.contains(where: { $0.id == id }) else { return nil }
        let rest = blocks(of: id)
        updateNote(id) { $0.blocks = rest + [text] }
        return rest.count
    }

    func updateBlock(_ index: Int, of id: UUID, to text: String) {
        let current = blocks(of: id)
        guard current.indices.contains(index), current[index] != text else { return }
        updateNote(id) { entry in
            entry.blocks = current.enumerated().map { $0.offset == index ? text : $0.element }
        }
    }

    func removeBlock(_ index: Int, of id: UUID) {
        let current = blocks(of: id)
        guard current.indices.contains(index) else { return }
        let rest = current.enumerated().filter { $0.offset != index }.map(\.element)
        updateNote(id) { $0.blocks = rest.isEmpty ? nil : rest }
    }
}

// MARK: Image attachments

extension NoteStore {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"]
    private static let maxImageBytes = 30 * 1024 * 1024

    var attachmentsDir: URL { rootDir.appendingPathComponent("Attachments", isDirectory: true) }

    func attachmentFolder(of id: UUID) -> URL {
        attachmentsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func attachmentURLs(of id: UUID) -> [URL] {
        guard let note = notes.first(where: { $0.id == id }) else { return [] }
        let folder = attachmentFolder(of: id)
        return (note.attachments ?? []).map { folder.appendingPathComponent($0) }
    }

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Copies image files next to the open note. Returns false when none could be attached.
    @discardableResult
    func attachImageFiles(_ urls: [URL]) -> Bool {
        let added = urls.filter(Self.isImageFile).compactMap { url -> String? in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= Self.maxImageBytes, let data = try? Data(contentsOf: url) else { return nil }
            return storeAttachment(data, ext: url.pathExtension.lowercased())
        }
        return finishAttaching(added)
    }

    /// Pasted image data (TIFF, PNG…) is saved as PNG.
    @discardableResult
    func attachImageData(_ data: Data) -> Bool {
        guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return finishAttaching([storeAttachment(png, ext: "png")].compactMap { $0 })
    }

    func removeAttachment(_ fileName: String, from id: UUID) {
        try? FileManager.default.removeItem(at: attachmentFolder(of: id).appendingPathComponent(fileName))
        updateNote(id) { entry in
            let rest = (entry.attachments ?? []).filter { $0 != fileName }
            entry.attachments = rest.isEmpty ? nil : rest
        }
    }

    func removeAllAttachments(of id: UUID) {
        removeAttachmentFolder(of: id)
        updateNote(id) { $0.attachments = nil }
    }

    static func copyImage(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Saves one image where the user picks.
    static func exportImage(_ url: URL, named title: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(sanitize(title)).\(url.pathExtension)"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            NSSound.beep()
        }
    }

    /// Copies every image into a folder the user picks, numbered after the note.
    static func exportImages(_ urls: [URL], named title: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Export")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let base = sanitize(title)
        for (index, url) in urls.enumerated() {
            var dest = folder.appendingPathComponent("\(base) \(index + 1).\(url.pathExtension)")
            var n = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                n += 1
                dest = folder.appendingPathComponent("\(base) \(index + 1)-\(n).\(url.pathExtension)")
            }
            do { try FileManager.default.copyItem(at: url, to: dest) } catch { NSSound.beep() }
        }
    }

    func removeAttachmentFolder(of id: UUID) {
        try? FileManager.default.removeItem(at: attachmentFolder(of: id))
    }

    private func storeAttachment(_ data: Data, ext: String) -> String? {
        guard let id = activeID else { return nil }
        let folder = attachmentFolder(of: id)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).\(ext)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            NSSound.beep()
            return nil
        }
    }

    private func finishAttaching(_ names: [String]) -> Bool {
        guard let id = activeID, !names.isEmpty else { return false }
        updateNote(id) { $0.attachments = ($0.attachments ?? []) + names }
        return true
    }
}

/// Small, cached thumbnails decoded off the main thread (ImageIO, never the full image).
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "RubbishNotes.thumbnails", qos: .userInitiated)

    func thumbnail(for url: URL, size: CGFloat, completion: @escaping (NSImage?) -> Void) {
        let key = "\(url.path)|\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return completion(hit) }
        queue.async { [cache] in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size * 2,
            ]
            let image = CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
                .map { NSImage(cgImage: $0, size: .zero) }
            if let image { cache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
