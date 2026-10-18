import AppKit
import SwiftUI

enum Prefs {
    static let theme = "RubbishNotes.theme"
    static let fontName = "RubbishNotes.editor.fontName"
    static let fontSize = "RubbishNotes.editor.fontSize"
    static let spellCheck = "RubbishNotes.spellCheck"
    static let ruled = "RubbishNotes.ruledPaper"
    static let sidebarVisible = "RubbishNotes.sidebarVisible"
    static let floatOnTop = "RubbishNotes.floatOnTop"
    static let activeNote = "RubbishNotes.activeNoteID"
    static let didSeed = "RubbishNotes.didSeedStarters"
    static let defaultFontSize: Double = 15
}

extension Notification.Name {
    static let focusEditor = Notification.Name("RubbishNotes.focusEditor")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.flushNow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NoteStore.shared.importFiles(urls)
    }
}

@main
struct RubbishNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NoteStore.shared
    @StateObject private var find = FindState.shared
    @AppStorage(Prefs.sidebarVisible) private var sidebarVisible = true
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName

    var body: some Scene {
        Window("Rubbish Notes", id: "main") {
            MainView()
                .environmentObject(store)
                .environmentObject(find)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n")
                Button("Open…") { store.importWithPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save a Copy…") { store.exportActiveWithPanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.activeID == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    Printing.print(store.text, font: FontChoice.font(fontName, size: fontSize))
                }
                .keyboardShortcut("p")
                .disabled(store.activeID == nil)
            }
            CommandGroup(after: .textEditing) {
                Button("Find & Replace") { find.show() }
                    .keyboardShortcut("f")
            }
            CommandGroup(replacing: .sidebar) {
                Button(sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    withAnimation(.easeOut(duration: 0.2)) { sidebarVisible.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                Button(floatOnTop ? "Stop Floating on Top" : "Float on Top") { floatOnTop.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
                Button("Bigger Text") { fontSize = min(fontSize + 1, 32) }
                    .keyboardShortcut("=")
                Button("Smaller Text") { fontSize = max(fontSize - 1, 10) }
                    .keyboardShortcut("-")
                Button("Reset Text Size") { fontSize = Prefs.defaultFontSize }
                    .keyboardShortcut("0")
            }
        }

        Settings {
            SettingsView()
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
