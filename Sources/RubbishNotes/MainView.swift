import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var store: NoteStore
    @AppStorage(Prefs.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.spellCheck) private var spellCheck = false
    @AppStorage(Prefs.ruled) private var ruled = false
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @AppStorage(Prefs.iconStyle) private var iconStyleRaw = IconStyle.blue.rawValue
    @AppStorage(Prefs.editorTheme) private var themeID = EditorTheme.standard.id
    /// Hides everything around the text except the button that ends it.
    @AppStorage(Prefs.focusMode) private var focusMode = false
    @StateObject private var selectionState = ViewState(SelectionStats())
    @StateObject private var toastState = ViewState<String?>(nil)
    @StateObject private var toastTask = ViewState<DispatchWorkItem?>(nil)
    @StateObject private var searchState = ViewState("")
    @StateObject private var columns = ViewState(NavigationSplitViewVisibility.all)

    private var appearance: AppearanceChoice { AppearanceChoice(rawValue: appearanceRaw) ?? .system }
    private var iconStyle: IconStyle { IconStyle(rawValue: iconStyleRaw) ?? .blue }
    private var theme: EditorTheme { EditorTheme.named(themeID) }

    /// An explicit appearance wins; otherwise a light or dark theme sets the window's look.
    private var colorScheme: ColorScheme? {
        if let forced = appearance.scheme { return forced }
        return theme.isDark.map { $0 ? .dark : .light }
    }
    private var isTrashed: Bool { store.active?.location == .trash }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns.value) {
            SidebarView(query: searchState.value)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            detail
        }
        .searchable(text: $searchState.value, placement: .sidebar, prompt: "Search")
        .toolbar(removing: focusMode ? .sidebarToggle : nil)
        .onChange(of: focusMode, initial: true) {
            withAnimation(.smooth(duration: 0.3)) { columns.value = focusMode ? .detailOnly : .all }
        }
        .tint(iconStyle.accent)
        .preferredColorScheme(colorScheme)
        .background(WindowConfigurator(floatOnTop: floatOnTop))
        .onDrop(of: [.fileURL], isTargeted: nil, perform: importDrop)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .focusEditor, object: nil)
            }
        }
    }

    // MARK: Detail

    private var detail: some View {
        Group {
            if store.activeID == nil {
                ContentUnavailableView {
                    Label("No Note", systemImage: "note.text")
                } description: {
                    Text("Create a note or drop a text file here.")
                } actions: {
                    Button("New Note") { store.newNote() }
                        .buttonStyle(.glassProminent)
                }
            } else {
                EditorView(
                    text: store.text,
                    textVersion: store.textVersion,
                    noteID: store.activeID,
                    font: FontChoice.font(fontName, size: fontSize),
                    spellCheck: spellCheck,
                    ruled: ruled,
                    editable: !isTrashed,
                    theme: theme,
                    accent: iconStyle.accentNS,
                    selection: $selectionState.value,
                    onRichPaste: { showToast("Formatting Removed") }
                )
                .overlay(alignment: .bottom) {
                    if !focusMode {
                        if isTrashed { trashBanner } else { statusCapsule }
                    }
                }
            }
        }
        .overlay(alignment: .top) { toast }
        .navigationTitle(store.active?.title ?? "Rubbish Notes")
        .navigationSubtitle(focusMode ? "" : subtitle)
        .toolbar {
            if !focusMode { detailToolbar }
            ToolbarItem(placement: .primaryAction) { focusButton }
        }
        .animation(.smooth(duration: 0.25), value: toastState.value)
    }

    private var subtitle: String {
        guard let note = store.active else { return "" }
        switch note.location {
        case .trash: return "In the Trash"
        case .archive: return store.justSaved ? "Saved" : "Archived"
        case .inbox: return store.justSaved ? "Saved" : "Plain Text"
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if let note = store.active, note.location == .trash {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.restore(note.id)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .help("Restore to Inbox")
                Button(role: .destructive) {
                    store.deletePermanently(note.id)
                } label: {
                    Label("Delete Permanently", systemImage: "trash.slash")
                }
                .help("Delete Permanently")
            }
        } else if let note = store.active {
            ToolbarItemGroup(placement: .primaryAction) {
                if note.location == .inbox {
                    Button {
                        store.togglePin(note.id)
                    } label: {
                        Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
                    }
                    .help(note.pinned ? "Unpin Note" : "Pin Note")
                }

                Button {
                    note.location == .archive ? store.restore(note.id) : store.archive(note.id)
                } label: {
                    Label(note.location == .archive ? "Move to Inbox" : "Archive",
                          systemImage: note.location == .archive ? "tray.and.arrow.up" : "archivebox")
                }
                .help(note.location == .archive ? "Move to Inbox" : "Archive Note")

                ShareLink(item: store.url(for: note)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share Note")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    TextFinder.perform(.showFindInterface)
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Find in Note (⌘F)")

            }
        }
    }

    private var focusButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
        } label: {
            Label(focusMode ? "Exit Focus Mode" : "Focus Mode", systemImage: focusMode ? "bolt.fill" : "bolt")
        }
        .buttonStyle(FocusButtonStyle(active: focusMode))
        .help(focusMode ? "Exit Focus Mode (⇧⌘F)" : "Focus Mode (⇧⌘F)")
    }

    // MARK: Glass overlays

    private var trashBanner: some View {
        HStack(spacing: 12) {
            Label("This note is in the Trash.", systemImage: "trash")
                .foregroundStyle(.secondary)
            Button("Restore") {
                if let id = store.activeID { store.restore(id) }
            }
            .buttonStyle(.glassProminent)
        }
        .font(.callout)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 14)
    }

    private var statusCapsule: some View {
        let selection = selectionState.value
        let hasSelection = selection.characters > 0
        let words = hasSelection ? selection.words : Counting.words(store.text)
        let characters = hasSelection ? selection.characters : store.text.count
        let minutes = max(1, Int((Double(words) / 220).rounded()))
        return HStack(spacing: 6) {
            Text("\(words) \(words == 1 ? "word" : "words")")
            Text("·").foregroundStyle(.tertiary)
            Text("\(characters) \(characters == 1 ? "character" : "characters")")
            if hasSelection {
                Text("selected").foregroundStyle(iconStyle.accent)
            } else if words > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text("\(minutes) min read")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = toastState.value {
            Label(message, systemImage: "textformat")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func showToast(_ message: String) {
        toastTask.value?.cancel()
        toastState.value = message
        let state = toastState
        let work = DispatchWorkItem { state.value = nil }
        toastTask.value = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { store.importFiles([url]) }
            }
        }
        return accepted
    }
}

/// Reaches the hosting NSWindow for the float-on-top level.
struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = floatOnTop ? .floating : .normal
        window.tabbingMode = .disallowed
    }
}

/// The focus toggle shows the accent-filled glass while focus mode is on.
private struct FocusButtonStyle: PrimitiveButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        if active {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(.glassProminent)
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
        }
    }
}
