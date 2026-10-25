import AppKit
import UniformTypeIdentifiers

/// One note's content for a Markdown export.
struct MarkdownNote: Equatable {
    let title: String
    let text: String
    let blocks: [String]
}

/// Markdown export of a note with its sub-notes: one .zip holding the note's
/// .md and one .md per sub-note. The note's file ends with links to them.
extension NoteExporter {
    /// Asks whether the sub-notes go too. nil means the person cancelled.
    static func askIncludeSubnotes(title: String, count: Int) -> Bool? {
        let alert = NSAlert()
        alert.messageText = L("Export the sub-notes too?")
        alert.informativeText = count == 1
            ? L("“%@” has 1 sub-note. With it, you get a .zip with one Markdown file per note.", title)
            : L("“%@” has %ld sub-notes. With them, you get a .zip with one Markdown file per note.", title, count)
        alert.addButton(withTitle: L("Include Sub-notes"))
        alert.addButton(withTitle: L("This Note Only"))
        alert.addButton(withTitle: L("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    /// Asks where to save "<title>.zip" and writes it. Returns false on failure.
    @discardableResult
    static func exportMarkdown(_ parent: MarkdownNote, subnotes: [MarkdownNote]) -> Bool {
        let base = NoteStore.sanitize(parent.title)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return true }
        do {
            try writeMarkdownZip(parent, subnotes: subnotes, to: dest)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    /// Builds the folder in a temporary place and zips it to `dest`.
    static func writeMarkdownZip(_ parent: MarkdownNote, subnotes: [MarkdownNote], to dest: URL) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let folder = work.appendingPathComponent(NoteStore.sanitize(parent.title), isDirectory: true)
        try writeMarkdownFolder(parent, subnotes: subnotes, into: folder)
        try zip(folder, to: dest)
    }

    /// Writes the note's .md and one .md per sub-note into `folder`. Returns the file names, note first.
    @discardableResult
    static func writeMarkdownFolder(_ parent: MarkdownNote, subnotes: [MarkdownNote], into folder: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = markdownFileNames(for: [parent.title] + subnotes.map(\.title))
        let links = Swift.zip(subnotes, names.dropFirst()).map { note, name in "- [\(note.title)](<\(name)>)" }
        var main = markdown(title: parent.title, text: parent.text, blocks: parent.blocks)
        if !links.isEmpty {
            main += "\n## \(L("Sub-notes"))\n\n" + links.joined(separator: "\n") + "\n"
        }
        try main.write(to: folder.appendingPathComponent(names[0]), atomically: true, encoding: .utf8)
        for (note, name) in Swift.zip(subnotes, names.dropFirst()) {
            let content = markdown(title: note.title, text: note.text, blocks: note.blocks)
            try content.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return names
    }

    /// Safe file names, one per title, never two alike (the disk ignores case):
    /// a repeat gets " 2", " 3"… before ".md".
    static func markdownFileNames(for titles: [String]) -> [String] {
        var taken: Set<String> = []
        return titles.map { title in
            let base = NoteStore.sanitize(title)
            var name = "\(base).md"
            var n = 1
            while taken.contains(name.lowercased()) {
                n += 1
                name = "\(base) \(n).md"
            }
            taken.insert(name.lowercased())
            return name
        }
    }
}
