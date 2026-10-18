import AppKit
import Combine
import UniformTypeIdentifiers

struct NoteEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var pinned: Bool
    var pinnedAt: Date?
    var lastOpened: Date

    var title: String { (fileName as NSString).deletingPathExtension }
}

/// Every note is a real .txt file in the notes folder; the index only keeps
/// what a file can't (pinning and recency). Text is written 0.6 s after the
/// last keystroke, and the folder is watched so edits made elsewhere show up.
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [NoteEntry] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var text = ""
    /// Bumps whenever `text` is replaced from outside the editor.
    @Published private(set) var textVersion = 0
    @Published private(set) var previews: [UUID: String] = [:]
    @Published private(set) var justSaved = false

    let notesDir: URL
    private let indexURL: URL
    private var dirty = false
    private var pendingFlush: DispatchWorkItem?
    private var savedBadge: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchDebounce: DispatchWorkItem?
    private var lastSelfWrite = Date.distantPast

    private static let autosaveDelay = 0.6
    private static let savedBadgeDuration = 1.5

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = support.appendingPathComponent("Rubbish Notes", isDirectory: true)
        notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        indexURL = root.appendingPathComponent("notes-index.json")
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        loadIndex()
        reconcile()
        let defaults = UserDefaults.standard
        if notes.isEmpty && !defaults.bool(forKey: Prefs.didSeed) { seedStarters() }
        defaults.set(true, forKey: Prefs.didSeed)

        let saved = defaults.string(forKey: Prefs.activeNote).flatMap(UUID.init(uuidString:))
        let start = notes.first(where: { $0.id == saved })?.id ?? ordered.first?.id
        select(start)
        startWatching()
    }

    // MARK: Lists

    var pinnedNotes: [NoteEntry] {
        notes.filter(\.pinned).sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
    }

    var recentNotes: [NoteEntry] {
        notes.filter { !$0.pinned }.sorted { $0.lastOpened > $1.lastOpened }
    }

    var ordered: [NoteEntry] { pinnedNotes + recentNotes }

    var active: NoteEntry? { notes.first { $0.id == activeID } }

    func url(for note: NoteEntry) -> URL { notesDir.appendingPathComponent(note.fileName) }

    // MARK: Editing

    func select(_ id: UUID?) {
        flushNow()
        guard let id, let i = notes.firstIndex(where: { $0.id == id }) else {
            activeID = nil
            text = ""
            textVersion += 1
            return
        }
        notes[i].lastOpened = Date()
        activeID = id
        text = (try? String(contentsOf: url(for: notes[i]), encoding: .utf8)) ?? ""
        textVersion += 1
        UserDefaults.standard.set(id.uuidString, forKey: Prefs.activeNote)
        saveIndex()
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    /// Called by the editor on every keystroke.
    func editorChanged(_ newText: String) {
        guard activeID != nil, newText != text else { return }
        text = newText
        dirty = true
        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushNow() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: work)
    }

    /// Replaces the text from outside the editor, e.g. Replace All.
    func replaceText(_ newText: String) {
        editorChanged(newText)
        textVersion += 1
    }

    func flushNow() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard dirty, let note = active else { return }
        dirty = false
        lastSelfWrite = Date()
        do {
            try text.write(to: url(for: note), atomically: true, encoding: .utf8)
            previews[note.id] = Self.preview(of: text)
            showSavedBadge()
        } catch {
            NSSound.beep()
        }
    }

    private func showSavedBadge() {
        justSaved = true
        savedBadge?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.justSaved = false }
        savedBadge = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.savedBadgeDuration, execute: work)
    }

    // MARK: Notes

    @discardableResult
    func newNote(content: String = "", name: String? = nil) -> UUID {
        flushNow()
        let fileName = uniqueFileName(base: name ?? "untitled")
        lastSelfWrite = Date()
        try? content.write(to: notesDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        let entry = NoteEntry(id: UUID(), fileName: fileName, pinned: false, pinnedAt: nil, lastOpened: Date())
        notes.append(entry)
        previews[entry.id] = Self.preview(of: content)
        saveIndex()
        select(entry.id)
        return entry.id
    }

    func rename(_ id: UUID, to newTitle: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let clean = Self.sanitize(newTitle)
        guard clean != notes[i].title else { return }
        if id == activeID { flushNow() }
        let target = uniqueFileName(base: clean)
        lastSelfWrite = Date()
        do {
            try FileManager.default.moveItem(at: url(for: notes[i]), to: notesDir.appendingPathComponent(target))
            notes[i].fileName = target
            saveIndex()
        } catch {
            NSSound.beep()
        }
    }

    func togglePin(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].pinned.toggle()
        notes[i].pinnedAt = notes[i].pinned ? Date() : nil
        saveIndex()
    }

    /// Moves the file to the Finder Trash, so it can still be recovered.
    func trash(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if id == activeID { flushNow() }
        lastSelfWrite = Date()
        do {
            try FileManager.default.trashItem(at: url(for: notes[i]), resultingItemURL: nil)
        } catch {
            NSSound.beep()
            return
        }
        notes.remove(at: i)
        previews[id] = nil
        saveIndex()
        if id == activeID {
            activeID = nil
            select(ordered.first?.id)
        }
    }

    func reveal(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url(for: note)])
    }

    // MARK: Import and export

    /// Files come in as plain text: RTF, HTML and the like lose their formatting.
    func importFiles(_ urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            var content: String?
            if ["rtf", "rtfd", "html", "htm", "webarchive", "doc", "docx"].contains(ext) {
                content = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
            } else {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            guard let content else { NSSound.beep(); continue }
            newNote(content: content, name: url.deletingPathExtension().lastPathComponent)
        }
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .rtf, .rtfd, .html, UTType("net.daringfireball.markdown") ?? .plainText]
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    func exportActiveWithPanel() {
        guard let note = active else { return }
        flushNow()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = note.fileName
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do { try text.write(to: dest, atomically: true, encoding: .utf8) } catch { NSSound.beep() }
    }

    // MARK: Index and folder

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([NoteEntry].self, from: data) else { return }
        notes = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Brings the index in line with the .txt files actually in the folder.
    private func reconcile() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "txt" } ?? []
        let names = Set(files.map(\.lastPathComponent))
        notes.removeAll { !names.contains($0.fileName) }
        let known = Set(notes.map(\.fileName))
        for file in files where !known.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            notes.append(NoteEntry(id: UUID(), fileName: file.lastPathComponent, pinned: false, pinnedAt: nil, lastOpened: modified))
        }
        var fresh: [UUID: String] = [:]
        for note in notes {
            fresh[note.id] = Self.preview(of: (try? String(contentsOf: url(for: note), encoding: .utf8)) ?? "")
        }
        previews = fresh
        saveIndex()
    }

    private func startWatching() {
        let fd = open(notesDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func folderChanged() {
        watchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyDiskChanges() }
        watchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func applyDiskChanges() {
        // Ignore the echo of our own writes.
        guard Date().timeIntervalSince(lastSelfWrite) > 1 else { return }
        reconcile()
        if active == nil {
            select(ordered.first?.id)
        } else if let note = active, !dirty,
                  let disk = try? String(contentsOf: url(for: note), encoding: .utf8), disk != text {
            text = disk
            textVersion += 1
        }
    }

    // MARK: Helpers

    private func uniqueFileName(base: String) -> String {
        let clean = Self.sanitize(base)
        var candidate = "\(clean).txt"
        var n = 1
        while FileManager.default.fileExists(atPath: notesDir.appendingPathComponent(candidate).path) {
            n += 1
            candidate = "\(clean) \(n).txt"
        }
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : String(cleaned.prefix(120))
    }

    static func preview(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(90))
    }

    private func seedStarters() {
        newNote(content: Starters.shortcuts, name: "Every shortcut")
        newNote(content: Starters.welcome, name: "Welcome to Rubbish Notes")
    }
}

enum Starters {
    static let welcome = """
    This note is already saved.

    Everything you type here lands in a plain .txt file on your Mac a moment after you stop typing. No save button, no cloud, no "unsaved changes". Quit mid-sentence; the sentence will be here.

    Paste anything and only the words arrive. Bold, colors and fonts stay behind. That's on purpose: it's a scrap of paper, not a layout tool.

    Right-click a note in the sidebar to pin it, rename it, share it or move it to the Trash. Drop a file on the window and it becomes a note.

    Crumple this one up whenever you like.
    """

    static let shortcuts = """
    ⌘N  new note
    ⌘O  open a file as a note
    ⇧⌘S  save a copy somewhere else
    ⌘F  find & replace (Return next, ⇧Return previous, Esc close)
    ⌥⌘S  show or hide the sidebar
    ⌥⌘T  float on top of other windows
    ⌘=  ⌘-  ⌘0  text size
    ⌘P  print
    ⌘,  settings and themes

    That's all of them.
    """
}
