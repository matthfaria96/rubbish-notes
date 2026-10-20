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
    static let sidebarStatus = "RubbishNotes.sidebarStatus"
    static let didSeed = "RubbishNotes.didSeedStarters"
    static let defaultFontSize: Double = 15
}

extension Notification.Name {
    static let focusEditor = Notification.Name("RubbishNotes.focusEditor")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        IconStyle.current.applyToDock()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.flushNow()
        NoteStore.shared.savePendingIndex()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NoteStore.shared.importFiles(urls)
    }
}

@main
struct RubbishNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NoteStore.shared
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @AppStorage(Prefs.focusMode) private var focusMode = false
    @AppStorage(Prefs.ruled) private var ruled = false
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName

    var body: some Scene {
        Window("Rubbish Notes", id: "main") {
            MainView()
                .environmentObject(store)
        }
        .defaultSize(width: 960, height: 640)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            TextEditingCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Note", systemImage: "square.and.pencil") { store.newNote() }
                    .keyboardShortcut("n")
                Button("Open…", systemImage: "doc") { store.importWithPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save a Copy…", systemImage: "square.and.arrow.down") { store.exportActiveWithPanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.activeID == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…", systemImage: "printer") {
                    Printing.print(store.text, font: FontChoice.font(fontName, size: fontSize))
                }
                .keyboardShortcut("p")
                .disabled(store.activeID == nil)
            }
            CommandMenu("Note") {
                NoteCommands(store: store)
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

/// The menu-bar Note menu: what can be done to the open note in its box.
private struct NoteCommands: View {
    @ObservedObject var store: NoteStore

    var body: some View {
        if let note = store.active {
            switch note.location {
            case .trash:
                Button("Restore to Inbox", systemImage: "arrow.uturn.backward") { store.restore(note.id) }
                Divider()
                Button("Delete Permanently", systemImage: "trash.slash", role: .destructive) {
                    store.deletePermanently(note.id)
                }
            case .inbox, .archive:
                if note.location == .inbox {
                    Button(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin") {
                        store.togglePin(note.id)
                    }
                    Button("Archive", systemImage: "archivebox") { store.archive(note.id) }
                } else {
                    Button("Move to Inbox", systemImage: "tray.and.arrow.up") { store.restore(note.id) }
                }
                ShareLink(item: store.url(for: note)) { Label("Share…", systemImage: "square.and.arrow.up") }
                Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
                Divider()
                Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
            }
        } else {
            Button("No Note Selected") {}.disabled(true)
        }
    }
}
