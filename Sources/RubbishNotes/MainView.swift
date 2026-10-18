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
    @StateObject private var selectionState = ViewState(SelectionStats())
    @StateObject private var toastState = ViewState<String?>(nil)
    @StateObject private var toastTask = ViewState<DispatchWorkItem?>(nil)
    @StateObject private var searchState = ViewState("")
    @StateObject private var columns = ViewState(NavigationSplitViewVisibility.all)

    private var appearance: AppearanceChoice { AppearanceChoice(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns.value) {
            SidebarView(query: searchState.value)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            detail
        }
        .searchable(text: $searchState.value, placement: .sidebar, prompt: "Search")
        .tint(Brand.red)
        .preferredColorScheme(appearance.scheme)
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
                    selection: $selectionState.value,
                    onRichPaste: { showToast("Formatting Removed") }
                )
                .overlay(alignment: .bottom) { statusCapsule }
            }
        }
        .overlay(alignment: .top) { toast }
        .navigationTitle(store.active?.title ?? "Rubbish Notes")
        .navigationSubtitle(subtitle)
        .toolbar { detailToolbar }
        .animation(.smooth(duration: 0.25), value: toastState.value)
    }

    private var subtitle: String {
        guard store.activeID != nil else { return "" }
        return store.justSaved ? "Saved" : "Plain Text"
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if let note = store.active {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.togglePin(note.id)
                } label: {
                    Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
                }
                .help(note.pinned ? "Unpin Note" : "Pin Note")

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

                Menu {
                    Button("Bigger", systemImage: "plus.magnifyingglass") { fontSize = min(fontSize + 1, 32) }
                    Button("Smaller", systemImage: "minus.magnifyingglass") { fontSize = max(fontSize - 1, 10) }
                    Button("Actual Size", systemImage: "1.magnifyingglass") { fontSize = Prefs.defaultFontSize }
                    Divider()
                    Toggle("Ruled Lines", systemImage: "line.3.horizontal", isOn: $ruled)
                } label: {
                    Label("Text Size", systemImage: "textformat.size")
                }
                .help("Text Size")

                Menu {
                    Toggle("Float on Top", systemImage: "macwindow.on.rectangle", isOn: $floatOnTop)
                    Button("Show in Finder", systemImage: "folder") { store.reveal(note.id) }
                    Button("Save a Copy…", systemImage: "square.and.arrow.down") { store.exportActiveWithPanel() }
                    Button("Print…", systemImage: "printer") {
                        Printing.print(store.text, font: FontChoice.font(fontName, size: fontSize))
                    }
                    Divider()
                    Button("Move to Trash", systemImage: "trash", role: .destructive) { store.trash(note.id) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .help("More")
            }
        }
    }

    // MARK: Glass overlays

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
                Text("selected").foregroundStyle(Brand.red)
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
