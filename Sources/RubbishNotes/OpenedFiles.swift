import AppKit
import Combine
import UniformTypeIdentifiers

/// A text file from outside the notes (a .txt or .md in Documents, say),
/// listed under Open Files in the sidebar and edited in place. It is never
/// copied into the notes, so it gets plain editing only: no note blocks,
/// images, status or sub-notes, which a .txt or .md file can't hold.
struct OpenedFile: Codable, Identifiable, Equatable {
    let id: UUID
    var path: String
    /// Security-scoped bookmark, so the sandbox lets the app back in after a relaunch.
    var bookmark: Data?
    var openedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    /// The folder it was opened from, as the Finder names it.
    var folderName: String { FileManager.default.displayName(atPath: url.deletingLastPathComponent().path) }
    var isMarkdown: Bool { ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased()) }
    var kindName: String { isMarkdown ? "Markdown" : L("Plain text") }
}

/// The Open Files list and the one file shown in the editor. Typing is saved
/// 0.6 s after it stops, in the encoding the file was read in; changes made
/// in other apps come back in while nothing is waiting to be saved.
final class OpenedFiles: ObservableObject {
    static let shared = OpenedFiles()

    @Published private(set) var files: [OpenedFile] = []
    /// The file in the editor; nil while a note is shown.
    @Published private(set) var activeID: UUID?
    @Published private(set) var text = "" { didSet { recount() } }
    @Published private(set) var textVersion = 0
    @Published private(set) var counts = TextCounts()
    @Published private(set) var justSaved = false
    /// The active file couldn't be read (moved, deleted, or no longer allowed).
    @Published private(set) var unreadable = false
    /// Some of its bytes didn't read as text (an unknown encoding): shown, never rewritten.
    @Published private(set) var readOnly = false

    private let defaults: UserDefaults
    /// Where messages go (the notes window's toast).
    private weak var notes: NoteStore?
    private var encoding: String.Encoding = .utf8
    /// The file began with a UTF-8 byte-order mark, written back with it.
    private var byteOrderMark = false
    private var dirty = false
    private var diskStamp: Date?
    private var pendingSave: DispatchWorkItem?
    private var savedBadge: DispatchWorkItem?
    private var countWork: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastSelfWrite = Date.distantPast
    /// Security scopes opened from bookmarks, by file.
    private var scoped: [UUID: URL] = [:]

    static let listKey = "RubbishNotes.openedFiles"
    private static let saveDelay = 0.6

    init(defaults: UserDefaults = .standard, notes: NoteStore? = .shared) {
        self.defaults = defaults
        self.notes = notes
        files = Self.load(from: defaults)
        files = files.map(resolve)
        save()
        // Picking a note puts the note back in the editor.
        notes?.willSelectNote = { [weak self] in self?.leave() }
    }

    var active: OpenedFile? { files.first { $0.id == activeID } }

    // MARK: List

    /// Adds the file at the top of the list (or finds it there) and shows it.
    @discardableResult
    func open(_ url: URL) -> UUID {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        var file = files.first { $0.path == path }
            ?? OpenedFile(id: UUID(), path: path, bookmark: nil, openedAt: Date())
        file.bookmark = bookmark ?? file.bookmark
        file.openedAt = Date()
        files = [file] + files.filter { $0.id != file.id }
        save()
        // The list is shown with the inbox.
        if let notes, notes.box != .inbox { notes.show(.inbox) }
        if activeID == file.id {
            reload()
        } else {
            select(file.id)
        }
        return file.id
    }

    func select(_ id: UUID?) {
        guard id != activeID else { return }
        guard resolveUnsaved() else { return }
        stopWatching()
        activeID = files.contains { $0.id == id } ? id : nil
        reload()
        if activeID != nil { NotificationCenter.default.post(name: .focusEditor, object: nil) }
    }

    /// Back to the notes: saves the file and lets the editor show the open note.
    func leave() {
        guard activeID != nil else { return }
        select(nil)
    }

    /// Takes the file off the list; the file itself stays where it is.
    func close(_ id: UUID) {
        if id == activeID { leave() }
        if let url = scoped.removeValue(forKey: id) { url.stopAccessingSecurityScopedResource() }
        files.removeAll { $0.id == id }
        save()
    }

    /// File › Save a Copy while a file is shown.
    func saveCopyWithPanel() {
        guard let file = active else { return }
        flushNow()
        saveCopy(of: file)
    }

    @discardableResult
    private func saveCopy(of file: OpenedFile) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        do {
            try text.write(to: dest, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    func reveal(_ id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    // MARK: Editing

    /// Called by the editor on every change.
    func editorChanged(_ newText: String) {
        guard activeID != nil, !unreadable, !readOnly, newText != text else { return }
        text = newText
        dirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Writes waiting changes in place (the sandbox allows the file, not its folder).
    /// Returns false when changes are still unsaved (the write failed).
    @discardableResult
    func flushNow() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty, let file = active else { return true }
        // Another app changed the file since it was read: ask before writing over it.
        if let onDisk = NoteStore.modificationDate(file.url), let known = diskStamp, onDisk != known,
           !keepMineOverOutsideChange(file) {
            dirty = false
            reload()
            return true
        }
        if text.data(using: encoding) == nil { encoding = .utf8 }
        var data = text.data(using: encoding) ?? Data(text.utf8)
        if byteOrderMark, encoding == .utf8 { data = Data([0xEF, 0xBB, 0xBF]) + data }
        var coordinationError: NSError?
        var writeError: Error?
        lastSelfWrite = Date()
        NSFileCoordinator().coordinate(writingItemAt: file.url, options: [], error: &coordinationError) { url in
            do { try data.write(to: url) } catch { writeError = error }
        }
        if coordinationError != nil || writeError != nil {
            NSSound.beep()
            notes?.notice = L("“%@” couldn’t be saved.", file.name)
            return false
        }
        dirty = false
        diskStamp = NoteStore.modificationDate(file.url)
        showSavedBadge()
        return true
    }

    /// Before leaving the file (another file, a note, quitting): saves it, and
    /// if that fails asks what to do with the typing. False means stay.
    func resolveUnsaved() -> Bool {
        guard !flushNow(), let file = active else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("“%@” couldn’t be saved.", file.name)
        alert.informativeText = L("The file may have been moved, locked or put on a disk that is gone. Save your text somewhere else, or leave it unsaved.")
        alert.addButton(withTitle: L("Save a Copy…"))
        alert.addButton(withTitle: L("Discard Changes"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard saveCopy(of: file) else { return false }
        case .alertSecondButtonReturn:
            break
        default:
            return false
        }
        dirty = false
        return true
    }

    /// The file changed in another app while there was typing here.
    private func keepMineOverOutsideChange(_ file: OpenedFile) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("“%@” was changed in another app.", file.name)
        alert.informativeText = L("Keep your version and write it over theirs, or open theirs and drop your latest typing?")
        alert.addButton(withTitle: L("Keep My Version"))
        alert.addButton(withTitle: L("Use Their Version"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Reads the active file again (on opening it, or after another app changed it).
    private func reload() {
        guard let file = active else {
            text = ""
            unreadable = false
            textVersion += 1
            return
        }
        let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size <= NoteStore.maxFileBytes, let data = try? Data(contentsOf: file.url) {
            let decoded = PlainTextDocument.decode(data)
            text = decoded.text
            encoding = decoded.encoding
            byteOrderMark = encoding == .utf8 && data.starts(with: [0xEF, 0xBB, 0xBF])
            readOnly = !Self.readsBack(decoded.text, as: decoded.encoding, from: data)
            unreadable = false
        } else {
            text = ""
            unreadable = true
            readOnly = false
        }
        diskStamp = NoteStore.modificationDate(file.url)
        textVersion += 1
        watch(file.url)
    }

    // MARK: Watching

    private func watch(_ url: URL) {
        stopWatching()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.fileChanged() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    private func fileChanged() {
        guard let file = active else { return }
        // Right after our own write, look again a little later: another app may have written too.
        let sinceOwnWrite = Date().timeIntervalSince(lastSelfWrite)
        guard sinceOwnWrite > 1 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (1.05 - sinceOwnWrite)) { [weak self] in self?.fileChanged() }
            return
        }
        // Waiting typing is checked against the file when it is saved (`flushNow`).
        if !dirty, NoteStore.modificationDate(file.url) != diskStamp {
            reload()
        } else {
            // Apps that save by replacing the file leave us watching the old one.
            watch(file.url)
        }
    }

    /// Whether writing `text` back gives the same bytes, so nothing was lost in reading.
    static func readsBack(_ text: String, as encoding: String.Encoding, from data: Data) -> Bool {
        guard var written = text.data(using: encoding) else { return false }
        if encoding == .utf8, data.starts(with: [0xEF, 0xBB, 0xBF]) { written = Data([0xEF, 0xBB, 0xBF]) + written }
        if encoding == .utf16 { return text.data(using: .utf16) != nil && String(data: data, encoding: .utf16) == text }
        return written == data
    }

    // MARK: Helpers

    private func recount() {
        countWork?.cancel()
        let snapshot = text
        let work = DispatchWorkItem { [weak self] in
            let counts = TextCounts(words: Counting.words(snapshot), characters: snapshot.count)
            DispatchQueue.main.async {
                guard let self, self.text == snapshot else { return }
                self.counts = counts
            }
        }
        countWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func showSavedBadge() {
        justSaved = true
        savedBadge?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.justSaved = false }
        savedBadge = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Opens a saved file's bookmark, following it if the file moved.
    private func resolve(_ file: OpenedFile) -> OpenedFile {
        guard let bookmark = file.bookmark else { return file }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return file }
        if url.startAccessingSecurityScopedResource() { scoped[file.id] = url }
        var resolved = file
        resolved.path = url.path
        if stale {
            resolved.bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)) ?? bookmark
        }
        return resolved
    }

    private static func load(from defaults: UserDefaults) -> [OpenedFile] {
        guard let data = defaults.data(forKey: listKey) else { return [] }
        return (try? JSONDecoder().decode([OpenedFile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        defaults.set(data, forKey: Self.listKey)
    }
}
