import AppKit
import Combine
import UniformTypeIdentifiers

/// Where a note lives. Each box is a real folder, so moving a note between
/// boxes moves its .txt file, and a trashed note stays recoverable until the
/// Trash is emptied.
enum NoteBox: String, Codable, CaseIterable, Identifiable {
    case inbox, archive, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .archive: "Archive"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .archive: "archivebox"
        case .trash: "trash"
        }
    }

    var folderName: String {
        switch self {
        case .inbox: "Notes"
        case .archive: "Archive"
        case .trash: "Trash"
        }
    }
}

struct NoteEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var fileName: String
    var pinned: Bool
    var pinnedAt: Date?
    var lastOpened: Date
    /// Fixes the note's place in the list; older indexes may lack it.
    var createdAt: Date?
    /// nil in indexes written before boxes existed, meaning the inbox.
    var box: NoteBox?
    var trashedAt: Date?

    var title: String { (fileName as NSString).deletingPathExtension }
    var location: NoteBox { box ?? .inbox }
}

/// Every note is a real .txt file; the index only keeps what a file can't
/// (box, pinning, dates). Text is written 0.6 s after the last keystroke,
/// and the folders are watched so edits made elsewhere show up.
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [NoteEntry] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var text = ""
    /// Bumps whenever `text` is replaced from outside the editor.
    @Published private(set) var textVersion = 0
    @Published private(set) var previews: [UUID: String] = [:]
    @Published private(set) var modified: [UUID: Date] = [:]
    @Published private(set) var justSaved = false
    /// The box the sidebar is showing.
    @Published private(set) var box: NoteBox = .inbox
    /// Full text of every note, for sidebar search.
    private var contents: [UUID: String] = [:]

    let rootDir: URL
    private let dirs: [NoteBox: URL]
    private let indexURL: URL
    private var dirty = false
    private var pendingFlush: DispatchWorkItem?
    private var savedBadge: DispatchWorkItem?
    private var watchers: [DispatchSourceFileSystemObject] = []
    /// Watches the open note's file: folder events miss in-place edits.
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchDebounce: DispatchWorkItem?
    private var lastSelfWrite = Date.distantPast

    private static let autosaveDelay = 0.6
    private static let savedBadgeDuration = 1.5

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDir = support.appendingPathComponent("Rubbish Notes", isDirectory: true)
        var dirs: [NoteBox: URL] = [:]
        for box in NoteBox.allCases {
            let dir = rootDir.appendingPathComponent(box.folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dirs[box] = dir
        }
        self.dirs = dirs
        indexURL = rootDir.appendingPathComponent("notes-index.json")

        loadIndex()
        reconcile()
        let defaults = UserDefaults.standard
        if notes.isEmpty && !defaults.bool(forKey: Prefs.didSeed) { seedStarters() }
        defaults.set(true, forKey: Prefs.didSeed)

        let saved = defaults.string(forKey: Prefs.activeNote).flatMap(UUID.init(uuidString:))
        let start = notes.first(where: { $0.id == saved && $0.location == .inbox })?.id ?? visible.first?.id
        select(start)
        startWatching()
    }

    // MARK: Lists

    /// Pinned notes, shown above the rest in the inbox only.
    var pinnedNotes: [NoteEntry] {
        guard box == .inbox else { return [] }
        return notes.filter { $0.location == .inbox && $0.pinned }
            .sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
    }

    /// The rest of the current box. Order never depends on opening a note:
    /// creation date, newest first; the Trash shows the latest deletions first.
    var listNotes: [NoteEntry] {
        let inBox = notes.filter { $0.location == box && !(box == .inbox && $0.pinned) }
        if box == .trash {
            return inBox.sorted { ($0.trashedAt ?? .distantPast) > ($1.trashedAt ?? .distantPast) }
        }
        return inBox.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    var visible: [NoteEntry] { pinnedNotes + listNotes }

    var active: NoteEntry? { notes.first { $0.id == activeID } }

    func count(in box: NoteBox) -> Int { notes.filter { $0.location == box }.count }

    func url(for note: NoteEntry) -> URL { dirs[note.location]!.appendingPathComponent(note.fileName) }

    func matches(_ note: NoteEntry, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let body = note.id == activeID ? text : (contents[note.id] ?? "")
        return note.title.range(of: query, options: options) != nil || body.range(of: query, options: options) != nil
    }

    func show(_ newBox: NoteBox) {
        guard newBox != box else { return }
        box = newBox
        select(visible.first?.id)
    }

    // MARK: Editing

    func select(_ id: UUID?) {
        if let id, id == activeID { return }
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
        watchActiveFile()
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    /// Called by the editor on every keystroke.
    func editorChanged(_ newText: String) {
        guard let note = active, note.location != .trash, newText != text else { return }
        text = newText
        dirty = true
        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushNow() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: work)
    }

    func flushNow() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard dirty, let note = active else { return }
        dirty = false
        lastSelfWrite = Date()
        do {
            try text.write(to: url(for: note), atomically: true, encoding: .utf8)
            // An atomic write replaces the file, so watch the new one.
            watchActiveFile()
            previews[note.id] = Self.preview(of: text)
            contents[note.id] = text
            modified[note.id] = Date()
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

    /// New notes always go to the inbox, which the sidebar switches to.
    @discardableResult
    func newNote(content: String = "", name: String? = nil) -> UUID {
        flushNow()
        box = .inbox
        let fileName = uniqueFileName(base: name ?? "untitled", in: .inbox)
        lastSelfWrite = Date()
        try? content.write(to: dirs[.inbox]!.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        let entry = NoteEntry(id: UUID(), fileName: fileName, pinned: false, pinnedAt: nil,
                              lastOpened: Date(), createdAt: Date(), box: .inbox)
        notes.append(entry)
        previews[entry.id] = Self.preview(of: content)
        contents[entry.id] = content
        modified[entry.id] = Date()
        saveIndex()
        select(entry.id)
        return entry.id
    }

    func rename(_ id: UUID, to newTitle: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let clean = Self.sanitize(newTitle)
        guard clean != notes[i].title else { return }
        if id == activeID { flushNow() }
        let target = uniqueFileName(base: clean, in: notes[i].location)
        lastSelfWrite = Date()
        do {
            try FileManager.default.moveItem(at: url(for: notes[i]), to: dirs[notes[i].location]!.appendingPathComponent(target))
            notes[i].fileName = target
            saveIndex()
            if id == activeID { watchActiveFile() }
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

    func archive(_ id: UUID) { move(id, to: .archive) }

    /// Back to the inbox from the Archive or the Trash.
    func restore(_ id: UUID) { move(id, to: .inbox) }

    func trash(_ id: UUID) { move(id, to: .trash) }

    /// Removes a trashed note for good.
    func deletePermanently(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].location == .trash else { return }
        lastSelfWrite = Date()
        try? FileManager.default.removeItem(at: url(for: notes[i]))
        forget(id)
    }

    func emptyTrash() {
        for note in notes where note.location == .trash {
            lastSelfWrite = Date()
            try? FileManager.default.removeItem(at: url(for: note))
            forget(note.id)
        }
    }

    func reveal(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url(for: note)])
    }

    private func move(_ id: UUID, to destination: NoteBox) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].location != destination else { return }
        let listBefore = visible.map(\.id)
        if id == activeID { flushNow() }
        let target = uniqueFileName(base: notes[i].title, in: destination)
        lastSelfWrite = Date()
        do {
            try FileManager.default.moveItem(at: url(for: notes[i]), to: dirs[destination]!.appendingPathComponent(target))
        } catch {
            NSSound.beep()
            return
        }
        notes[i].fileName = target
        notes[i].box = destination
        notes[i].trashedAt = destination == .trash ? Date() : nil
        if destination != .inbox {
            notes[i].pinned = false
            notes[i].pinnedAt = nil
        }
        saveIndex()
        if id == activeID { selectNeighbour(of: id, in: listBefore) }
    }

    private func forget(_ id: UUID) {
        let wasActive = id == activeID
        let listBefore = visible.map(\.id)
        notes.removeAll { $0.id == id }
        previews[id] = nil
        contents[id] = nil
        modified[id] = nil
        saveIndex()
        if wasActive { selectNeighbour(of: id, in: listBefore) }
    }

    /// After the open note leaves the list, open the one that took its place.
    private func selectNeighbour(of id: UUID, in listBefore: [UUID]) {
        activeID = nil
        let rest = listBefore.filter { $0 != id && visible.map(\.id).contains($0) }
        guard let index = listBefore.firstIndex(of: id), !rest.isEmpty else {
            select(visible.first?.id)
            return
        }
        select(rest[min(index, rest.count - 1)])
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

    // MARK: Index and folders

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([NoteEntry].self, from: data) else { return }
        notes = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Brings the index in line with the .txt files actually in each folder.
    private func reconcile() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        var onDisk: [NoteBox: [URL]] = [:]
        for box in NoteBox.allCases {
            onDisk[box] = (try? FileManager.default.contentsOfDirectory(at: dirs[box]!, includingPropertiesForKeys: keys))?
                .filter { $0.pathExtension.lowercased() == "txt" } ?? []
        }
        notes.removeAll { note in !(onDisk[note.location] ?? []).contains { $0.lastPathComponent == note.fileName } }
        for (box, files) in onDisk {
            let known = Set(notes.filter { $0.location == box }.map(\.fileName))
            for file in files where !known.contains(file.lastPathComponent) {
                let values = try? file.resourceValues(forKeys: Set(keys))
                notes.append(NoteEntry(id: UUID(), fileName: file.lastPathComponent, pinned: false, pinnedAt: nil,
                                       lastOpened: values?.contentModificationDate ?? Date(),
                                       createdAt: values?.creationDate ?? Date(), box: box,
                                       trashedAt: box == .trash ? Date() : nil))
            }
        }
        var freshPreviews: [UUID: String] = [:]
        var freshContents: [UUID: String] = [:]
        var freshModified: [UUID: Date] = [:]
        for i in notes.indices {
            let file = url(for: notes[i])
            let values = try? file.resourceValues(forKeys: Set(keys))
            // Entries saved before creation dates were tracked take the file's.
            if notes[i].createdAt == nil { notes[i].createdAt = values?.creationDate ?? notes[i].lastOpened }
            let body = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            freshPreviews[notes[i].id] = Self.preview(of: body)
            freshContents[notes[i].id] = body
            freshModified[notes[i].id] = values?.contentModificationDate
        }
        previews = freshPreviews
        contents = freshContents
        modified = freshModified
        saveIndex()
    }

    private func startWatching() {
        for dir in dirs.values {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in self?.folderChanged() }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    private func watchActiveFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        guard let note = active else { return }
        let fd = open(url(for: note).path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
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
        // Editors that save atomically replace the file we were watching.
        watchActiveFile()
        if active == nil {
            select(visible.first?.id)
        } else if let note = active, !dirty,
                  let disk = try? String(contentsOf: url(for: note), encoding: .utf8), disk != text {
            text = disk
            textVersion += 1
        }
    }

    // MARK: Helpers

    private func uniqueFileName(base: String, in box: NoteBox) -> String {
        let clean = Self.sanitize(base)
        let dir = dirs[box]!
        var candidate = "\(clean).txt"
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
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

    Hover a note in the sidebar and click the pencil to rename it. Right-click to pin, archive or move it to the Trash; trashed notes wait in the Trash until you empty it. Drop a file on the window and it becomes a note.

    Crumple this one up whenever you like.
    """

    static let shortcuts = """
    ⌘N  new note
    ⌘O  open a file as a note
    ⇧⌘S  save a copy somewhere else
    ⌘F  find in the note
    ⌥⌘F  find and replace
    ⌘G  ⇧⌘G  next and previous match
    ⌘1  ⌘2  ⌘3  Inbox, Archive, Trash
    ⇧⌘F  focus mode: just you and the text
    ⌃⌘S  show or hide the sidebar
    ⌥⌘T  float on top of other windows
    ⌘=  ⌘-  ⌘0  text size
    ⌘P  print
    ⌘,  settings

    That's all of them.
    """
}
