import AppKit
import UniformTypeIdentifiers

/// Exports a note: its title and text, then its blocks in order. As PDF or
/// plain text; with images, a .zip holding that file plus the images.
enum NoteExportFormat: String, CaseIterable, Identifiable {
    case pdf, txt
    var id: String { rawValue }
    var title: String { self == .pdf ? "PDF" : L("Plain Text") }
}

enum NoteExporter {
    /// Asks where to save and writes the export. Returns false on failure.
    @discardableResult
    static func export(title: String, text: String, blocks: [String], images: [URL], as format: NoteExportFormat) -> Bool {
        let base = NoteStore.sanitize(title).isEmpty ? "Note" : NoteStore.sanitize(title)
        let zipped = !images.isEmpty
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).\(zipped ? "zip" : format.rawValue)"
        panel.allowedContentTypes = [zipped ? .zip : (format == .pdf ? .pdf : .plainText)]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return true }
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let folder = work.appendingPathComponent(base, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let document = folder.appendingPathComponent("\(base).\(format.rawValue)")
            switch format {
            case .txt: try plainText(title: title, text: text, blocks: blocks).write(to: document, atomically: true, encoding: .utf8)
            case .pdf: try writePDF(attributed(title: title, text: text, blocks: blocks), to: document)
            }
            if zipped {
                let imageFolder = folder.appendingPathComponent(L("Images"), isDirectory: true)
                try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
                for (index, url) in images.enumerated() {
                    try FileManager.default.copyItem(at: url, to: imageFolder.appendingPathComponent("\(index + 1).\(url.pathExtension)"))
                }
                try zip(folder, to: dest)
            } else {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: document, to: dest)
            }
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    static func plainText(title: String, text: String, blocks: [String]) -> String {
        var parts = [title, "", text.trimmingCharacters(in: .newlines)]
        for (index, block) in blocks.enumerated() {
            parts += ["", "", "— \(L("Block %ld", index + 1)) —", "", block]
        }
        return parts.joined(separator: "\n") + "\n"
    }

    private static func attributed(title: String, text: String, blocks: [String]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black]
        let sub: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.darkGray]
        let mono: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.black]
        out.append(NSAttributedString(string: title + "\n\n", attributes: heading))
        out.append(NSAttributedString(string: text.trimmingCharacters(in: .newlines) + "\n", attributes: body))
        for (index, block) in blocks.enumerated() {
            out.append(NSAttributedString(string: "\n\(L("Block %ld", index + 1))\n", attributes: sub))
            out.append(NSAttributedString(string: block + "\n", attributes: mono))
        }
        return out
    }

    /// A4 pages through the print system, saved straight to a file.
    private static func writePDF(_ content: NSAttributedString, to url: URL) throws {
        let info = NSPrintInfo(dictionary: [.jobSavingURL: url])
        info.jobDisposition = .save
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 56; info.rightMargin = 56
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.textStorage?.setAttributedString(content)
        view.backgroundColor = .white
        view.sizeToFit()
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// The system zips a folder when it is read "for uploading".
    private static func zip(_ folder: URL, to dest: URL) throws {
        var failure: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: zipURL, to: dest)
            } catch { failure = error }
        }
        if let error = coordinatorError ?? failure { throw error }
    }
}
