import AppKit
import Combine
import UniformTypeIdentifiers

/// A text file from outside the notes (a .txt or .md in Documents, say),
/// listed under Open Files in the sidebar and edited there. It is never
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

/// The Open Files list and the one file shown in the editor. Unlike notes,
/// these files are written only when the person saves (⌘S, Save As…), as in
/// any text editor; until then their changes are kept here, also while
/// another file or a note is shown, and the app asks before they could be lost.
final class OpenedFiles: ObservableObject {
    static let shared = OpenedFiles()

    @Published private(set) var files: [OpenedFile] = []
    /// The file in the editor; nil while a note is shown.
    @Published private(set) var activeID: UUID?
    @Published private(set) var text = "" { didSet { recount() } }
    @Published private(set) var textVersion = 0
    @Published private(set) var counts = TextCounts()
    @Published private(set) var justSaved = false
    /// Files with changes that aren't in the file yet.
    @Published private(set) var unsaved: Set<UUID> = []
    /// The active file couldn't be read (moved, deleted, or no longer allowed).
    @Published private(set) var unreadable = false
    /// Some of its bytes didn't read as text (an unknown encoding): only Save As can write it.
    @Published private(set) var readOnly = false

    private let defaults: UserDefaults
    /// Where messages go (the notes window's toast).
    private weak var notes: NoteStore?
    /// Unsaved text of the files not on screen.
    private var edits: [UUID: String] = [:]
    private var encoding: String.Encoding = .utf8
    /// The file began with a UTF-8 byte-order mark, written back with it.
    private var byteOrderMark = false
    private var diskStamp: Date?
    private var savedBadge: DispatchWorkItem?
    private var countWork: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastSelfWrite = Date.distantPast
    /// Security scopes opened from bookmarks, by file.
    private var scoped: [UUID: URL] = [:]

    static let listKey = "RubbishNotes.openedFiles"

    init(defaults: UserDefaults = .standard, notes: NoteStore? = .shared) {
        self.defaults = defaults
        self.notes = notes
        files = Self.load(from: defaults)
        files = files.map(resolve)
        storeList()
        // Picking a note puts the note back in the editor (the file keeps its changes).
        notes?.willSelectNote = { [weak self] in self?.leave() }
    }

    var active: OpenedFile? { files.first { $0.id == activeID } }

    /// Whether Save has something to write for the file on screen.
    var canSave: Bool { activeID.map { unsaved.contains($0) } ?? false && !readOnly && !unreadable }

    // MARK: List

    /// Adds the file at the top of the list (or finds it there) and shows it.
    @discardableResult
    func open(_ url: URL) -> UUID {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let bookmark = Self.bookmark(for: url)
        var file = files.first { $0.path == path }
            ?? OpenedFile(id: UUID(), path: path, bookmark: nil, openedAt: Date())
        file.bookmark = bookmark ?? file.bookmark
        file.openedAt = Date()
        files = [file] + files.filter { $0.id != file.id }
        storeList()
        // The list is shown with the inbox.
        if let notes, notes.box != .inbox { notes.show(.inbox) }
        if activeID != file.id {
            select(file.id)
        } else if !unsaved.contains(file.id) {
            reload()
        }
        return file.id
    }

    /// Shows a file (or, with nil, the notes again). Changes not saved yet
    /// stay with the file they belong to.
    func select(_ id: UUID?) {
        guard id != activeID else { return }
        if let current = activeID, unsaved.contains(current) { edits[current] = text }
        stopWatching()
        activeID = files.contains { $0.id == id } ? id : nil
        reload()
        if let id, let edit = edits.removeValue(forKey: id) {
            text = edit
            textVersion += 1
        }
        if activeID != nil { NotificationCenter.default.post(name: .focusEditor, object: nil) }
    }

    /// Back to the notes.
    func leave() {
        guard activeID != nil else { return }
        select(nil)
    }

    /// Takes the file off the list (the file itself stays where it is),
    /// asking first when it has changes that aren't saved.
    func close(_ id: UUID) {
        if unsaved.contains(id) {
            if id != activeID { select(id) }
            guard let file = active, askToSave(file) else { return }
        }
        forget(id)
    }

    /// Drops the file from the list without asking.
    func forget(_ id: UUID) {
        discardChanges(id)
        if id == activeID { leave() }
        if let url = scoped.removeValue(forKey: id) { url.stopAccessingSecurityScopedResource() }
        files.removeAll { $0.id == id }
        storeList()
    }

    /// Forgets the changes and shows the file as it is on disk.
    func discardChanges(_ id: UUID) {
        unsaved.remove(id)
        edits[id] = nil
        if id == activeID { reload() }
    }

    func reveal(_ id: UUID) {
        guard let file = files.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    /// The file's text with its unsaved changes, whether shown or not.
    func currentText(of id: UUID) -> String? {
        if id == activeID { return text }
        if let edit = edits[id] { return edit }
        guard let file = files.first(where: { $0.id == id }), let data = try? Data(contentsOf: file.url) else { return nil }
        return PlainTextDocument.decode(data).text
    }

    // MARK: Editing and saving

    /// Called by the editor on every change; nothing is written until Save.
    func editorChanged(_ newText: String) {
        guard let id = activeID, !unreadable, !readOnly, newText != text else { return }
        text = newText
        unsaved.insert(id)
    }

    /// Save (⌘S): writes the file on screen in place, in the encoding it was
    /// read in. Returns false when the changes are still unsaved.
    @discardableResult
    func save() -> Bool {
        guard let file = active, unsaved.contains(file.id) else { return true }
        guard !readOnly, !unreadable else { return saveAs() }
        // Another app changed the file since it was read: ask before writing over it.
        if let onDisk = NoteStore.modificationDate(file.url), let known = diskStamp, onDisk != known,
           !keepMineOverOutsideChange(file) {
            discardChanges(file.id)
            return true
        }
        guard write(text, to: file.url) else {
            NSSound.beep()
            notes?.notice = L("“%@” couldn’t be saved.", file.name)
            return false
        }
        unsaved.remove(file.id)
        diskStamp = NoteStore.modificationDate(file.url)
        showSavedBadge()
        return true
    }

    /// Save As… (⇧⌘S): a new name, folder and kind (.txt or .md). The list
    /// then follows the new file; the old one stays as it was last saved.
    @discardableResult
    func saveAs() -> Bool {
        guard let file = active else { return false }
        let panel = NSSavePanel()
        panel.title = L("Save As")
        panel.nameFieldStringValue = file.name
        panel.directoryURL = file.url.deletingLastPathComponent()
        panel.allowedContentTypes = [.plainText, FileOpening.markdown]
        panel.showsContentTypes = true
        panel.currentContentType = file.isMarkdown ? FileOpening.markdown : .plainText
        panel.isExtensionHidden = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return false }
        if readOnly { encoding = .utf8 }
        guard write(text, to: dest) else {
            NSSound.beep()
            notes?.notice = L("“%@” couldn’t be saved.", dest.lastPathComponent)
            return false
        }
        // Another entry for the same file gives way to this one.
        let path = dest.standardizedFileURL.resolvingSymlinksInPath().path
        if let other = files.first(where: { $0.path == path && $0.id != file.id }) { forget(other.id) }
        if let url = scoped.removeValue(forKey: file.id) { url.stopAccessingSecurityScopedResource() }
        files = files.map { entry in
            guard entry.id == file.id else { return entry }
            var moved = entry
            moved.path = path
            moved.bookmark = Self.bookmark(for: dest)
            return moved
        }
        storeList()
        unsaved.remove(file.id)
        readOnly = false
        diskStamp = NoteStore.modificationDate(dest)
        watch(dest)
        showSavedBadge()
        return true
    }

    /// Save / Don't Save / Cancel for one file; false means stay (Cancel, or saving failed).
    func askToSave(_ file: OpenedFile) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Save the changes to “%@”?", file.name)
        alert.informativeText = L("If you don’t save, your changes will be lost.")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Don’t Save"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save() || saveAs()
        case .alertSecondButtonReturn:
            discardChanges(file.id)
            return true
        default:
            return false
        }
    }

    /// On quit: goes through each file with unsaved changes, showing it and
    /// asking. False cancels quitting.
    func reviewUnsaved() -> Bool {
        for file in files where unsaved.contains(file.id) {
            FileOpening.showMainWindow?()
            select(file.id)
            guard askToSave(file) else { return false }
        }
        return true
    }

    /// The file changed in another app while there were unsaved changes here.
    private func keepMineOverOutsideChange(_ file: OpenedFile) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("“%@” was changed in another app.", file.name)
        alert.informativeText = L("Keep your version and write it over theirs, or open theirs and drop your changes?")
        alert.addButton(withTitle: L("Keep My Version"))
        alert.addButton(withTitle: L("Use Their Version"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Writes in place (the sandbox grants the file, not its folder).
    private func write(_ text: String, to url: URL) -> Bool {
        if text.data(using: encoding) == nil { encoding = .utf8 }
        var data = text.data(using: encoding) ?? Data(text.utf8)
        if byteOrderMark, encoding == .utf8 { data = Data([0xEF, 0xBB, 0xBF]) + data }
        var coordinationError: NSError?
        var writeError: Error?
        lastSelfWrite = Date()
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
            do { try data.write(to: url) } catch { writeError = error }
        }
        return coordinationError == nil && writeError == nil
    }

    /// Reads the active file again (on showing it, or after another app changed it).
    private func reload() {
        guard let file = active else {
            text = ""
            unreadable = false
            readOnly = false
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
        // Unsaved changes are checked against the file when they are saved.
        if !unsaved.contains(file.id), NoteStore.modificationDate(file.url) != diskStamp {
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

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func storeList() {
        guard let data = try? JSONEncoder().encode(files) else { return }
        defaults.set(data, forKey: Self.listKey)
    }
}
