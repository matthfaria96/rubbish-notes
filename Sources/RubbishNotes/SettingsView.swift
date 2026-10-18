import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab("Editor", systemImage: "textformat") {
                EditorSettings()
            }
        }
        .frame(width: 500)
        .preferredColorScheme((AppearanceChoice(rawValue: appearanceRaw) ?? .system).scheme)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Label(choice.title, systemImage: choice.symbol).tag(choice.rawValue)
                    }
                }
                Toggle("Keep window on top of other apps", isOn: $floatOnTop)
            }
            Section("Storage") {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([NoteStore.shared.notesDir])
                    }
                } label: {
                    Text("Notes Folder")
                    Text(NoteStore.shared.notesDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("Every note is a plain .txt file, saved automatically as you type. Deleted notes go to the Trash.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EditorSettings: View {
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.spellCheck) private var spellCheck = false
    @AppStorage(Prefs.ruled) private var ruled = false

    var body: some View {
        Form {
            Section("Font") {
                Picker("Typeface", selection: $fontName) {
                    ForEach(FontChoice.all, id: \.self) { name in
                        Text(name).font(Font(FontChoice.font(name, size: 13))).tag(name)
                    }
                }
                LabeledContent("Size") {
                    Stepper(value: $fontSize, in: 10...32, step: 1) {
                        Text("\(Int(fontSize)) pt").monospacedDigit()
                    }
                }
            }
            Section("Writing") {
                Toggle("Check spelling while typing", isOn: $spellCheck)
                Toggle("Ruled lines", isOn: $ruled)
            }
            Section("Preview") {
                Text("Written on rubbish, kept like treasure.")
                    .font(Font(FontChoice.font(fontName, size: fontSize)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}
