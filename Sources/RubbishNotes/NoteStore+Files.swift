import AppKit
import UniformTypeIdentifiers

// MARK: Import and export

extension NoteStore {
    /// Files come in as plain text: RTF and HTML lose their formatting. Legacy
    /// Word and web-archive files are not parsed, and files over 20 MB are refused.
    func importFiles(_ urls: [URL]) {
        // The app's own files (a note dragged back onto the window) are never re-imported.
        let ownFolders = dirs.values.map { $0.standardizedFileURL.path + "/" }
        for url in urls where !ownFolders.contains(where: url.standardizedFileURL.path.hasPrefix) {
            let ext = url.pathExtension.lowercased()
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= Self.maxFileBytes else {
                NSSound.beep()
                notice = L("“%@” is larger than 20 MB and wasn’t imported.", url.lastPathComponent)
                continue
            }
            var content: String?
            if ["doc", "docx", "webarchive"].contains(ext) {
                content = nil
            } else if ["rtf", "rtfd", "html", "htm"].contains(ext) {
                content = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
            } else {
                content = try? String(contentsOf: url, encoding: .utf8)
            }
            guard let content else { NSSound.beep(); continue }
            newNote(content: content, name: url.deletingPathExtension().lastPathComponent)
        }
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

    /// The note whose .txt file this is, when the file sits in the notes folders
    /// (Notes, Archive or Trash). Files anywhere else are not notes.
    func libraryNote(at url: URL) -> NoteEntry? {
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        let folder = file.deletingLastPathComponent().path
        guard let box = NoteBox.allCases.first(where: {
            dirs[$0]!.standardizedFileURL.resolvingSymlinksInPath().path == folder
        }) else { return nil }
        return notes.first { $0.location == box && $0.fileName == file.lastPathComponent }
    }

    /// Whether the file lives anywhere inside the app's own notes folder.
    func isInLibrary(_ url: URL) -> Bool {
        let root = rootDir.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
    }
}
