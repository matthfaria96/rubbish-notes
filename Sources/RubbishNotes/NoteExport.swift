import AppKit
import UniformTypeIdentifiers

/// Exports a note: its title and text, then its blocks in order. As PDF or
/// plain text (with images, a .zip holding that file plus the images), or as
/// Markdown (always the .md alone).
enum NoteExportFormat: String, CaseIterable, Identifiable {
    case pdf, txt, md
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: "PDF"
        case .txt: L("Plain Text")
        case .md: "Markdown"
        }
    }
    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .txt: "doc.plaintext"
        case .md: "number"
        }
    }
    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .txt: .plainText
        case .md: UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

enum BlockExportFormat: String, CaseIterable, Identifiable {
    case txt, pdf, md
    var id: String { rawValue }
    var title: String {
        switch self {
        case .txt: L("Plain Text")
        case .pdf: "PDF"
        case .md: "Markdown"
        }
    }
    var symbol: String {
        switch self {
        case .txt: "doc.plaintext"
        case .pdf: "doc.richtext"
        case .md: "number"
        }
    }
    var contentType: UTType {
        switch self {
        case .txt: .plainText
        case .pdf: .pdf
        case .md: UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

enum NoteExporter {
    /// Asks where to save and writes the export. Returns false on failure.
    @discardableResult
    static func export(title: String, text: String, blocks: [String], images: [URL], as format: NoteExportFormat) -> Bool {
        let base = NoteStore.sanitize(title).isEmpty ? "Note" : NoteStore.sanitize(title)
        // Markdown is the text alone; the other formats carry the images in a .zip.
        let zipped = !images.isEmpty && format != .md
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).\(zipped ? "zip" : format.rawValue)"
        panel.allowedContentTypes = [zipped ? .zip : format.contentType]
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
            case .md: try markdown(title: title, text: text, blocks: blocks).write(to: document, atomically: true, encoding: .utf8)
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

    /// One note block on its own, as plain text, PDF or Markdown.
    static func exportBlock(_ content: String, title: String? = nil, as format: BlockExportFormat) {
        let base = title.map(NoteStore.sanitize).flatMap { $0.isEmpty ? nil : $0 } ?? L("Note block")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).\(format.rawValue)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            switch format {
            case .txt, .md:
                try (content + "\n").write(to: dest, atomically: true, encoding: .utf8)
            case .pdf:
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: work) }
                let body = NSMutableAttributedString(string: base + "\n\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.black])
                body.append(NSAttributedString(string: content + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
                try writePDF(body, to: work)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: work, to: dest)
            }
        } catch {
            NSSound.beep()
        }
    }

    static func plainText(title: String, text: String, blocks: [String]) -> String {
        var parts = [title, "", InlineBlocks.readable(text).trimmingCharacters(in: .newlines)]
        for (index, block) in blocks.enumerated() {
            parts += ["", "", "— \(L("Block %ld", index + 1)) —", "", block]
        }
        return parts.joined(separator: "\n") + "\n"
    }

    /// The note's own text first (its note blocks taken out), then each note
    /// block and each footer block as a section of its own.
    static func markdown(title: String, text: String, blocks: [String]) -> String {
        let segments = InlineBlocks.segments(of: text)
        // A block sat on its own line: the break after it goes with it.
        let body = segments.enumerated().compactMap { index, segment -> String? in
            guard case .text(let string) = segment else { return nil }
            let afterBlock: Bool
            if index > 0, case .block = segments[index - 1] { afterBlock = true } else { afterBlock = false }
            return afterBlock && string.hasPrefix("\n") ? String(string.dropFirst()) : string
        }.joined()
        var parts = ["# \(title)", "", body.trimmingCharacters(in: .newlines)]
        for segment in segments {
            if case .block(let content, _, let name) = segment {
                parts += ["", "## \(name ?? L("Note block"))", "", content]
            }
        }
        for (index, block) in blocks.enumerated() {
            parts += ["", "## \(L("Block %ld", index + 1))", "", block]
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
        out.append(NSAttributedString(string: InlineBlocks.readable(text).trimmingCharacters(in: .newlines) + "\n", attributes: body))
        for (index, block) in blocks.enumerated() {
            out.append(NSAttributedString(string: "\n\(L("Block %ld", index + 1))\n", attributes: sub))
            out.append(NSAttributedString(string: block + "\n", attributes: mono))
        }
        return out
    }

    /// A4 pages through the print system, saved straight to a file.
    static func writePDF(_ content: NSAttributedString, to url: URL) throws {
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

import SwiftUI

/// "Export Note" with its two formats; used in context menus and the toolbar.
struct ExportMenu: View {
    let noteID: UUID

    var body: some View {
        Menu {
            ForEach(NoteExportFormat.allCases) { format in
                Button(L("Export as %@…", format.title), systemImage: format.symbol) {
                    NoteStore.shared.exportNote(noteID, as: format)
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Label("Export Note", systemImage: "square.and.arrow.up")
        }
    }
}
