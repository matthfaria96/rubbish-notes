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
            Tab("Themes", systemImage: "paintpalette") {
                ThemeSettings()
            }
            Tab {
                AboutSettings()
            } label: {
                Label { Text("About", tableName: "About") } icon: { Image(systemName: "info.circle") }
            }
        }
        .frame(width: 500)
        .preferredColorScheme((AppearanceChoice(rawValue: appearanceRaw) ?? .system).scheme)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @AppStorage(Prefs.iconStyle) private var iconStyleRaw = IconStyle.blue.rawValue
    @StateObject private var language = ViewState(AppLanguage.current)
    @StateObject private var askRestart = ViewState(false)

    var body: some View {
        Form {
            Section("App Icon") {
                HStack(spacing: 24) {
                    ForEach(IconStyle.allCases) { style in
                        IconChoice(style: style, selected: style.rawValue == iconStyleRaw) {
                            iconStyleRaw = style.rawValue
                            style.applyToDock()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Label(choice.title, systemImage: choice.symbol).tag(choice.rawValue)
                    }
                }
                Picker("Language", selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.nativeName).tag(choice)
                    }
                }
                Toggle("Keep window on top of other apps", isOn: $floatOnTop)
            }
            Section("Storage") {
                LabeledContent {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([NoteStore.shared.rootDir])
                    }
                } label: {
                    Text("Notes Folder")
                    Text(NoteStore.shared.rootDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
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
        .alert("Restart Rubbish Notes to use the new language?", isPresented: $askRestart.value) {
            Button("Restart Now") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        }
    }

    /// Saving the choice is immediate; macOS applies it when the app next opens.
    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { language.value }, set: { choice in
            guard choice != language.value else { return }
            language.value = choice
            choice.apply()
            askRestart.value = true
        })
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
                        Text(name == "System" ? L("System") : name).font(Font(FontChoice.font(name, size: 13))).tag(name)
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

/// One selectable app icon, drawn like the system's icon pickers.
private struct IconChoice: View {
    let style: IconStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image = style.image {
                        Image(nsImage: image).resizable()
                    } else {
                        Image(systemName: "app").resizable()
                    }
                }
                .frame(width: 64, height: 64)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(selected ? style.accent : .clear, lineWidth: 3)
                )
                Text(style == .blue ? L("%@ (Default)", style.title) : style.title)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Theme gallery. Hovering a theme previews it at the top; clicking applies it.
private struct ThemeSettings: View {
    @AppStorage(Prefs.editorTheme) private var themeID = EditorTheme.standard.id
    @AppStorage(Prefs.iconStyle) private var iconStyleRaw = IconStyle.blue.rawValue
    @StateObject private var hovered = ViewState<EditorTheme?>(nil)

    private var accent: NSColor { (IconStyle(rawValue: iconStyleRaw) ?? .blue).accentNS }
    private var selected: EditorTheme { EditorTheme.named(themeID) }

    var body: some View {
        let previewing = hovered.value ?? selected
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSample(theme: previewing, fallbackAccent: accent, large: true)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
                    .animation(.easeOut(duration: 0.15), value: previewing.id)
                HStack {
                    Text(previewing.displayName).font(.headline)
                    Spacer()
                    Text(L(previewing == selected ? "Current theme" : "Click to apply"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(EditorTheme.all) { theme in
                        ThemeCard(theme: theme, selected: theme == selected, accent: accent) {
                            themeID = theme.id
                        }
                        .onHover { inside in
                            if inside { hovered.value = theme } else if hovered.value == theme { hovered.value = nil }
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 300)
            Text("Dark and light themes also set the window's look while Appearance is Automatic.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct ThemeCard: View {
    let theme: EditorTheme
    let selected: Bool
    let accent: NSColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ThemeSample(theme: theme, fallbackAccent: accent)
                    .frame(height: 66, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Color(nsColor: accent) : Color(nsColor: .separatorColor),
                                          lineWidth: selected ? 2.5 : 1)
                    )
                HStack(spacing: 4) {
                    Text(theme.displayName).lineLimit(1)
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: accent))
                    }
                }
                .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
