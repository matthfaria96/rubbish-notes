import AppKit
import SwiftUI

enum Prefs {
    static let appearance = "RubbishNotes.appearance"
    static let iconStyle = "RubbishNotes.iconStyle"
    static let editorTheme = "RubbishNotes.editorTheme"
    static let focusMode = "RubbishNotes.focusMode"
    static let fontName = "RubbishNotes.editor.fontName"
    static let fontSize = "RubbishNotes.editor.fontSize"
    static let spellCheck = "RubbishNotes.spellCheck"
    static let ruled = "RubbishNotes.ruledLines"
    static let floatOnTop = "RubbishNotes.floatOnTop"
    static let activeNote = "RubbishNotes.activeNoteID"
    /// Note status (dots in the lists, tabs and footer); off by default, so nothing distracts.
    static let statusEnabled = "RubbishNotes.statusEnabled"
    /// See-through glass behind the sidebar (on by default).
    static let sidebarGlass = "RubbishNotes.sidebarGlass"
    /// "sidebar" (vertical list) or "tabs" (horizontal strip above the note).
    static let notesLayout = "RubbishNotes.notesLayout"
    /// Whole-window opacity, on by default at 90 %.
    static let windowTranslucent = "RubbishNotes.windowTranslucent"
    static let windowOpacity = "RubbishNotes.windowOpacity"
    static let defaultWindowOpacity: Double = 0.95
    static let didSeed = "RubbishNotes.didSeedStarters"
    static let defaultFontSize: Double = 15
}

extension Notification.Name {
    static let focusEditor = Notification.Name("RubbishNotes.focusEditor")
    /// The toolbar's (+): put a note block at the cursor.
    static let insertInlineBlock = Notification.Name("RubbishNotes.insertInlineBlock")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        IconStyle.current.applyToDock()
        AppUpdater.shared.start()
    }

    /// Clicking the Dock icon while only separate plain text windows are open brings the notes back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag, FileOpening.notesWindows.isEmpty else { return true }
        FileOpening.showMainWindow?()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Open files with unsaved changes ask, one by one, before the app quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        OpenedFiles.shared.reviewUnsaved() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.flushNow()
        NoteStore.shared.savePendingIndex()
    }

    /// Finder double-click, Open With, a drop on the Dock icon: outside text
    /// files go to Open Files; library notes open as notes.
    func application(_ application: NSApplication, open urls: [URL]) {
        FileOpening.open(urls)
    }
}

@main
struct RubbishNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NoteStore.shared
    @StateObject private var files = OpenedFiles.shared
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @AppStorage(Prefs.focusMode) private var focusMode = false
    @AppStorage(Prefs.ruled) private var ruled = false
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName

    var body: some Scene {
        Window("Rubbish Notes", id: "main") {
            MainView()
                .environmentObject(store)
                .environmentObject(files)
        }
        .defaultSize(width: 960, height: 640)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            TextEditingCommands()

            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }

            CommandGroup(replacing: .newItem) {
                Button("New Note", systemImage: "square.and.pencil") { store.newNote() }
                    .keyboardShortcut("n")
                Button("New Sub-note", systemImage: "note.text.badge.plus") {
                    if let id = store.activeID { store.newSubnote(under: id) }
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(files.active != nil || !store.canAddSubnote(to: store.activeID))
                Button("Open…", systemImage: "doc") { FileOpening.openWithPanel() }
                    .keyboardShortcut("o")
                Divider()
                Button("Export Backup…", systemImage: "archivebox") { store.exportBackupWithPanel() }
                Button("Import Backup…", systemImage: "arrow.down.doc") { store.importBackupWithPanel() }
            }
            // A plain text window (NSDocument) answers these first; then an open
            // file (saved only here), otherwise the open note (saved as you type).
            CommandGroup(replacing: .saveItem) {
                Button("Save", systemImage: "square.and.arrow.down") {
                    guard !NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) else { return }
                    if files.active != nil { files.save() } else { store.flushNow() }
                }
                .keyboardShortcut("s")
                Button(L(files.active != nil ? "Save As…" : "Save a Copy…"), systemImage: "square.and.arrow.down.on.square") {
                    guard !NSApp.sendAction(#selector(NSDocument.saveTo(_:)), to: nil, from: nil) else { return }
                    if files.active != nil { files.saveAs() } else { store.exportActiveWithPanel() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…", systemImage: "printer") {
                    guard !NSApp.sendAction(#selector(NSDocument.printDocument(_:)), to: nil, from: nil) else { return }
                    let font = FontChoice.font(fontName, size: fontSize)
                    if files.active != nil {
                        Printing.print(files.text, font: font)
                    } else if store.activeID != nil {
                        Printing.print(store.text, font: font)
                    }
                }
                .keyboardShortcut("p")
            }
            CommandMenu("Note") {
                NoteCommands(store: store, files: files)
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(NoteBox.allCases.enumerated()), id: \.element) { index, box in
                    Button(box.title, systemImage: box.symbol) { store.show(box) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
                Divider()
            }
            CommandGroup(after: .sidebar) {
                Divider()
                SubnoteCommands(store: store)
                Divider()
                Button(L(focusMode ? "Exit Focus Mode" : "Focus Mode"), systemImage: focusMode ? "bolt.fill" : "bolt") {
                    focusMode.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                Toggle(isOn: $floatOnTop) { Label("Float on Top", systemImage: "macwindow.on.rectangle") }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Toggle(isOn: $ruled) { Label("Ruled Lines", systemImage: "line.3.horizontal") }
                Divider()
                Button("Bigger Text", systemImage: "plus.magnifyingglass") { fontSize = min(fontSize + 1, 32) }
                    .keyboardShortcut("=")
                Button("Smaller Text", systemImage: "minus.magnifyingglass") { fontSize = max(fontSize - 1, 10) }
                    .keyboardShortcut("-")
                Button("Actual Size", systemImage: "1.magnifyingglass") { fontSize = Prefs.defaultFontSize }
                    .keyboardShortcut("0")
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Drives the system find bar of the editor (NSTextFinder).
enum TextFinder {
    /// The magnifier: opens the find bar, or closes it when it is already open.
    static func toggle() {
        let visible = NoteStore.shared.findBarVisible?() ?? false
        perform(visible ? .hideFindInterface : .showFindInterface)
    }

    static func perform(_ action: NSTextFinder.Action) {
        NotificationCenter.default.post(name: .focusEditor, object: nil)
        DispatchQueue.main.async {
            let sender = NSMenuItem()
            sender.tag = action.rawValue
            NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: sender)
        }
    }
}

enum Printing {
    static func print(_ text: String, font: NSFont) {
        let info = NSPrintInfo.shared
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.string = text
        view.font = font
        view.sizeToFit()
        NSPrintOperation(view: view, printInfo: info).run()
    }
}

/// View › Collapse / Expand All Sub-notes, for the box on screen.
private struct SubnoteCommands: View {
    @ObservedObject var store: NoteStore

    var body: some View {
        let expanded = store.anySubnotesExpanded(in: store.box)
        Button(L(expanded ? "Collapse All Sub-notes" : "Expand All Sub-notes"),
               systemImage: expanded ? "chevron.up" : "chevron.down") {
            store.setAllSubnotesCollapsed(expanded, in: store.box)
        }
        .disabled(store.parentIDs(in: store.box).isEmpty)
    }
}

/// The menu-bar Note menu: what can be done to the open note in its box.
private struct NoteCommands: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var files: OpenedFiles

    var body: some View {
        if let file = files.active {
            OpenedFileMenu(file: file)
        } else if let note = store.active {
            switch note.location {
            case .trash:
                Button("Restore to Inbox", systemImage: "arrow.uturn.backward") { store.restore(note.id) }
                Divider()
                Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {
                    store.requestDeletePermanently(note.id)
                }
            case .inbox, .archive:
                if note.location == .inbox {
                    if !store.isNested(note.id) {
                        Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                            store.togglePin(note.id)
                        }
                    }
                    Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
                } else {
                    Button("Unarchive", systemImage: "tray") { store.restore(note.id) }
                }
                ExportMenu(noteID: note.id)
                Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
                Divider()
                Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
            }
        } else {
            Button("No Note Selected") {}.disabled(true)
        }
    }
}
