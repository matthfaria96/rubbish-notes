import AppKit
import UniformTypeIdentifiers

/// The whole library in one .zip, to move it to another Mac or keep it safe:
/// the .txt files of the three boxes (note blocks live in the text), the index
/// (pins, status, order, footer blocks, sub-notes), the images, and the app's
/// settings. Importing it into a fresh copy of the app gives back the same notes.
enum LibraryBackup {
    static let manifestName = "Rubbish Notes Backup.json"
    static let settingsName = "Settings.plist"
    static let indexName = "notes-index.json"
    static let attachmentsName = "Attachments"
    /// Next to the notes folder: where "Replace All" leaves the notes it replaced,
    /// one dated folder per import.
    static let previousFolderName = "Rubbish Notes (before import …)"
    static let format = 1

    struct Manifest: Codable {
        var format: Int
        var version: String
        var created: Date
        var notes: Int
    }

    enum Failure: LocalizedError {
        case notABackup, newerFormat

        var errorDescription: String? {
            switch self {
            case .notABackup: L("This .zip isn’t a Rubbish Notes backup.")
            case .newerFormat: L("This backup comes from a newer Rubbish Notes. Update the app, then import it again.")
            }
        }
    }

    /// An unpacked backup, checked: entries whose names could reach outside
    /// their folder are dropped, the rest are kept as they were.
    struct Contents {
        let folder: URL
        let notes: [NoteEntry]
        let settings: [String: Any]
    }

    /// Settings that travel with a backup. Window places, update checks and
    /// opened outside files stay with each Mac.
    static let settingKeys = [
        Prefs.appearance, Prefs.iconStyle, Prefs.editorTheme, Prefs.focusMode, Prefs.fontName, Prefs.fontSize,
        Prefs.spellCheck, Prefs.ruled, Prefs.floatOnTop, Prefs.activeNote, Prefs.statusEnabled,
        Prefs.sidebarGlass, Prefs.notesLayout, Prefs.windowTranslucent, Prefs.windowOpacity,
    ]

    static func settings(from defaults: UserDefaults) -> [String: Any] {
        settingKeys.reduce(into: [:]) { result, key in
            if let value = defaults.object(forKey: key) { result[key] = value }
        }
    }

    /// Only known keys with plist values are applied.
    static func apply(_ settings: [String: Any], to defaults: UserDefaults) {
        for key in settingKeys {
            guard let value = settings[key],
                  value is String || value is NSNumber else { continue }
            defaults.set(value, forKey: key)
        }
    }

    /// Copies the library at `root` into `folder`, with the manifest and settings.
    static func writeFolder(root: URL, settings: [String: Any], noteCount: Int, into folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in NoteBox.allCases.map(\.folderName) + [attachmentsName, indexName] {
            let source = root.appendingPathComponent(name)
            guard files.fileExists(atPath: source.path) else { continue }
            try files.copyItem(at: source, to: folder.appendingPathComponent(name))
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let manifest = Manifest(format: format, version: version, created: Date(), notes: noteCount)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(manifestName))
        let plist = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        try plist.write(to: folder.appendingPathComponent(settingsName))
    }

    /// The folder holding the index: the top of the zip, or the one folder
    /// the zip wraps everything in (as the app and the Finder write it).
    static func libraryFolder(in extracted: URL) -> URL? {
        let files = FileManager.default
        if files.fileExists(atPath: extracted.appendingPathComponent(indexName).path) { return extracted }
        let children = (try? files.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.first { files.fileExists(atPath: $0.appendingPathComponent(indexName).path) }
    }

    static func read(extracted: URL) throws -> Contents {
        guard let folder = libraryFolder(in: extracted),
              let data = try? Data(contentsOf: folder.appendingPathComponent(indexName)),
              let entries = try? JSONDecoder().decode([NoteEntry].self, from: data) else {
            throw Failure.notABackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let manifestData = try? Data(contentsOf: folder.appendingPathComponent(manifestName)),
           let manifest = try? decoder.decode(Manifest.self, from: manifestData), manifest.format > format {
            throw Failure.newerFormat
        }
        let settingsData = try? Data(contentsOf: folder.appendingPathComponent(settingsName))
        let settings = settingsData.flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        } ?? [:]
        let notes = entries.compactMap { entry -> NoteEntry? in
            guard isSafeName(entry.fileName), entry.fileName.lowercased().hasSuffix(".txt") else { return nil }
            var clean = entry
            clean.attachments = entry.attachments?.filter(isSafeName)
            return clean
        }
        return Contents(folder: folder, notes: cleaned(notes), settings: settings)
    }

    /// A new folder next to `root` for the notes an import replaces; never one already there.
    static func previousFolder(next root: URL, on date: Date = Date()) -> URL {
        let parent = root.deletingLastPathComponent()
        let stamp = date.formatted(.iso8601.year().month().day()) + " "
            + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)).replacingOccurrences(of: ":", with: ".")
        var candidate = parent.appendingPathComponent("Rubbish Notes (before import \(stamp))", isDirectory: true)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            candidate = parent.appendingPathComponent("Rubbish Notes (before import \(stamp)) \(n)", isDirectory: true)
        }
        return candidate
    }

    /// One entry per id and per file; a parent link only to a note that is
    /// itself on top (a note can't hang under itself or under a sub-note).
    static func cleaned(_ entries: [NoteEntry]) -> [NoteEntry] {
        var ids = Set<UUID>()
        var names = Set<String>()
        let unique = entries.filter { entry in
            let file = "\(entry.location.rawValue)/\(entry.fileName.lowercased())"
            guard !ids.contains(entry.id), !names.contains(file) else { return false }
            ids.insert(entry.id)
            names.insert(file)
            return true
        }
        let tops = Set(unique.filter { $0.parent == nil }.map(\.id))
        return unique.map { entry in
            var entry = entry
            if let parent = entry.parent, parent == entry.id || !tops.contains(parent) { entry.parent = nil }
            return entry
        }
    }

    /// A plain file name inside its folder: no separators, no leading dot.
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }

    static func defaultFileName(on date: Date = Date()) -> String {
        "Rubbish Notes Backup \(date.formatted(.iso8601.year().month().day())).zip"
    }
}

// MARK: Export and import

extension NoteStore {
    /// Writes the backup .zip to `dest`.
    func exportBackup(to dest: URL) throws {
        flushNow()
        savePendingIndex()
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("RubbishNotesBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let folder = staging.appendingPathComponent(dest.deletingPathExtension().lastPathComponent, isDirectory: true)
        try LibraryBackup.writeFolder(root: rootDir, settings: LibraryBackup.settings(from: defaults),
                                      noteCount: notes.count, into: folder)
        try NoteExporter.zip(folder, to: dest)
    }

    /// Unpacks and checks a backup; `cleanup` removes the unpacked copy.
    func openBackup(_ zip: URL) throws -> (contents: LibraryBackup.Contents, cleanup: () -> Void) {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("RubbishNotesImport-\(UUID().uuidString)", isDirectory: true)
        let cleanup = { try? FileManager.default.removeItem(at: staging) }
        do {
            try ZipReader.extract(zip, to: staging)
            return (try LibraryBackup.read(extracted: staging), { cleanup() })
        } catch let failure as ZipReader.Failure {
            cleanup()
            throw failure == .notAZip ? LibraryBackup.Failure.notABackup : CocoaError(.fileReadCorruptFile)
        } catch {
            cleanup()
            throw error
        }
    }

    /// The backup's notes and settings take the place of the current ones,
    /// which are moved next to the notes folder first, into a folder of their
    /// own (`previousFolder`), so no earlier import is ever overwritten. If
    /// anything fails, everything is put back as it was.
    @discardableResult
    func replaceLibrary(with backup: LibraryBackup.Contents) throws -> Int {
        flushNow()
        savePendingIndex()
        let files = FileManager.default
        let previous = LibraryBackup.previousFolder(next: rootDir)
        let index = rootDir.appendingPathComponent(LibraryBackup.indexName)
        var moved: [(from: URL, to: URL)] = []
        var copied: [URL] = []
        lastSelfWrite = Date()
        do {
            try files.createDirectory(at: previous, withIntermediateDirectories: true)
            // The index first: it is what holds pins, status, blocks and sub-notes.
            if files.fileExists(atPath: index.path) {
                try files.copyItem(at: index, to: previous.appendingPathComponent(LibraryBackup.indexName))
            }
            // The box folders stay (they are being watched); only what is inside them moves.
            for box in NoteBox.allCases {
                let keep = previous.appendingPathComponent(box.folderName, isDirectory: true)
                try files.createDirectory(at: keep, withIntermediateDirectories: true)
                for item in try files.contentsOfDirectory(at: dirs[box]!, includingPropertiesForKeys: nil) {
                    let target = keep.appendingPathComponent(item.lastPathComponent)
                    try files.moveItem(at: item, to: target)
                    moved.append((item, target))
                }
            }
            if files.fileExists(atPath: attachmentsDir.path) {
                let target = previous.appendingPathComponent(LibraryBackup.attachmentsName)
                try files.moveItem(at: attachmentsDir, to: target)
                moved.append((attachmentsDir, target))
            }
            for box in NoteBox.allCases {
                let source = backup.folder.appendingPathComponent(box.folderName, isDirectory: true)
                let items = (try? files.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
                for item in items where item.pathExtension.lowercased() == "txt" && LibraryBackup.isSafeName(item.lastPathComponent) {
                    let target = dirs[box]!.appendingPathComponent(item.lastPathComponent)
                    try files.copyItem(at: item, to: target)
                    copied.append(target)
                }
            }
            let images = backup.folder.appendingPathComponent(LibraryBackup.attachmentsName, isDirectory: true)
            if files.fileExists(atPath: images.path) {
                try files.copyItem(at: images, to: attachmentsDir)
                copied.append(attachmentsDir)
            }
            try JSONEncoder().encode(backup.notes).write(to: index, options: .atomic)
        } catch {
            // Back as it was: the backup's files out, the moved ones home, the old index back.
            copied.forEach { try? files.removeItem(at: $0) }
            for step in moved.reversed() { try? files.moveItem(at: step.to, to: step.from) }
            let savedIndex = previous.appendingPathComponent(LibraryBackup.indexName)
            if let data = try? Data(contentsOf: savedIndex) { try? data.write(to: index, options: .atomic) }
            try? files.removeItem(at: previous)
            reloadFromDisk()
            throw error
        }
        LibraryBackup.apply(backup.settings, to: defaults)
        // Undoing an earlier move would now act on the backup's notes.
        undoManager?.removeAllActions()
        reloadFromDisk()
        return notes.count
    }

    /// Adds the backup's notes to the current ones. Names that are taken get
    /// a number, and notes already here (same id) come in as copies. A failure
    /// removes what was copied, so trying again doesn't bring in doubles.
    @discardableResult
    func mergeLibrary(_ backup: LibraryBackup.Contents) throws -> Int {
        flushNow()
        let files = FileManager.default
        var taken = Set(notes.map(\.id))
        var newIDs: [UUID: UUID] = [:]
        var added: [NoteEntry] = []
        var copied: [URL] = []
        lastSelfWrite = Date()
        do {
            for entry in backup.notes {
                let source = backup.folder.appendingPathComponent(entry.location.folderName, isDirectory: true)
                    .appendingPathComponent(entry.fileName)
                guard files.fileExists(atPath: source.path) else { continue }
                var copy = entry
                copy.id = taken.contains(entry.id) ? UUID() : entry.id
                taken.insert(copy.id)
                newIDs[entry.id] = copy.id
                copy.fileName = uniqueFileName(base: entry.title, in: entry.location)
                let target = dirs[entry.location]!.appendingPathComponent(copy.fileName)
                try files.copyItem(at: source, to: target)
                copied.append(target)
                let images = backup.folder.appendingPathComponent(LibraryBackup.attachmentsName, isDirectory: true)
                    .appendingPathComponent(entry.id.uuidString, isDirectory: true)
                if files.fileExists(atPath: images.path) {
                    try files.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
                    try? files.removeItem(at: attachmentFolder(of: copy.id))
                    try files.copyItem(at: images, to: attachmentFolder(of: copy.id))
                    copied.append(attachmentFolder(of: copy.id))
                }
                added.append(copy)
            }
        } catch {
            copied.forEach { try? files.removeItem(at: $0) }
            throw error
        }
        // Sub-notes follow their parent's new id; a parent left behind lets them go.
        let linked = added.map { entry -> NoteEntry in
            var linked = entry
            linked.parent = entry.parent.flatMap { newIDs[$0] }
            return linked
        }
        absorb(linked)
        return linked.count
    }

    // MARK: Panels

    func exportBackupWithPanel() {
        let panel = NSSavePanel()
        panel.title = L("Export Backup")
        panel.message = L("All notes, sub-notes, blocks, images and settings, in one .zip.")
        panel.nameFieldStringValue = LibraryBackup.defaultFileName()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try exportBackup(to: dest)
        } catch {
            showBackupError(error, title: L("The backup couldn’t be saved."))
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Backup saved")
        alert.informativeText = L("“%@” is in the folder “%@”. Import it in Rubbish Notes on any Mac to get these notes back exactly as they are.",
                                  dest.lastPathComponent,
                                  FileManager.default.displayName(atPath: dest.deletingLastPathComponent().path))
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Show in Finder"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }

    func importBackupWithPanel() {
        let panel = NSOpenPanel()
        panel.title = L("Import Backup")
        panel.message = L("Choose a backup .zip made by Rubbish Notes.")
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let zip = panel.url else { return }
        let opened: (contents: LibraryBackup.Contents, cleanup: () -> Void)
        do {
            opened = try openBackup(zip)
        } catch {
            showBackupError(error, title: L("This backup couldn’t be read."))
            return
        }
        defer { opened.cleanup() }

        let count = opened.contents.notes.count
        let alert = NSAlert()
        alert.messageText = count == 1 ? L("Import 1 note from “%@”?", zip.lastPathComponent)
                                       : L("Import %ld notes from “%@”?", count, zip.lastPathComponent)
        alert.informativeText = L("Replace All puts the backup’s notes and settings in place of yours; your current notes are kept in the folder “%@”, next to the notes folder. Add to My Notes keeps yours and adds the backup’s.",
                                  LibraryBackup.previousFolderName)
        alert.addButton(withTitle: L("Replace All"))
        alert.addButton(withTitle: L("Add to My Notes"))
        alert.addButton(withTitle: L("Cancel"))
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }
        do {
            let imported = choice == .alertFirstButtonReturn
                ? try replaceLibrary(with: opened.contents)
                : try mergeLibrary(opened.contents)
            if choice == .alertFirstButtonReturn { IconStyle.current.applyToDock() }
            notice = imported == 1 ? L("1 note imported") : L("%ld notes imported", imported)
        } catch {
            reloadFromDisk()
            showBackupError(error, title: L("The backup couldn’t be imported."))
        }
    }

    private func showBackupError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
