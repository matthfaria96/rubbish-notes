import AppKit
import UniformTypeIdentifiers

/// Files the system hands the app: a Finder double-click, Open With, a drop
/// on the Dock icon, File › Open. A note's own .txt opens as that note; any
/// other text file (.txt, .md) goes to Open Files in the sidebar and is edited
/// in place, never imported. Other kinds of file (RTF, HTML) are imported as before.
enum FileOpening {
    /// Set by the main window: shows it, reopening it if it was closed.
    static var showMainWindow: (() -> Void)?

    /// Returns true when the notes window was needed (a note, or an import).
    @discardableResult
    static func open(_ urls: [URL]) -> Bool {
        let store = NoteStore.shared
        var imports: [URL] = []
        var needsNotes = false
        for url in urls {
            switch route(url, in: store) {
            case .note(let note):
                needsNotes = true
                showMainWindow?()
                store.expandParent(of: note.id)
                store.openNote(note.id, in: note.location)
            case .library:
                // The index or an attachment: shown in its notes, never opened on its own.
                needsNotes = true
                showMainWindow?()
            case .outsideFile:
                needsNotes = true
                showMainWindow?()
                OpenedFiles.shared.open(url)
            case .importFile:
                imports.append(url)
            }
        }
        if !imports.isEmpty {
            needsNotes = true
            showMainWindow?()
            store.importFiles(imports)
        }
        return needsNotes
    }

    /// Visible windows other than the plain text ones and panels: the notes window.
    static var notesWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible && !(window is NSPanel) && !(window.windowController is PlainTextWindowController)
                && window.canBecomeMain
        }
    }

    static var hasPlainWindows: Bool {
        NSApp.windows.contains { $0.isVisible && $0.windowController is PlainTextWindowController }
    }

    enum Route: Equatable {
        case note(NoteEntry), library, outsideFile, importFile
    }

    static func route(_ url: URL, in store: NoteStore) -> Route {
        if let note = store.libraryNote(at: url) { return .note(note) }
        if store.isInLibrary(url) { return .library }
        return isPlainText(url) ? .outsideFile : .importFile
    }

    /// File › Open: text files open in place, RTF and HTML become notes.
    static func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .rtf, .rtfd, .html, markdown]
        if panel.runModal() == .OK { open(panel.urls) }
    }

    static let markdown = UTType("net.daringfireball.markdown") ?? .plainText

    /// .txt and other plain text (Markdown, source code); not RTF or HTML.
    static func isPlainText(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .plainText) ?? false
    }
}

/// Rubbish Notes as the Mac's default app for .txt and .md files (Settings › General).
enum DefaultTextApp {
    /// The app that opens .txt files now, if any.
    static var currentHandler: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: .plainText)
    }

    static var isDefault: Bool {
        guard let handler = currentHandler else { return false }
        let bundleID = Bundle(url: handler)?.bundleIdentifier
        return bundleID == Bundle.main.bundleIdentifier
            || handler.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    /// The current handler's name, as the Finder shows it.
    static var currentName: String? {
        currentHandler.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    /// Asks macOS to open .txt (then .md) files with this app; the system may ask the person to confirm.
    static func makeDefault(completion: @escaping (Bool) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .plainText) { error in
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: FileOpening.markdown) { _ in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }
}
