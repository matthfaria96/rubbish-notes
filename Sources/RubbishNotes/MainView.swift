import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var find: FindState
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.theme) private var themeRaw = AppTheme.auto.rawValue
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.spellCheck) private var spellCheck = false
    @AppStorage(Prefs.ruled) private var ruled = true
    @AppStorage(Prefs.sidebarVisible) private var sidebarVisible = true
    @AppStorage(Prefs.floatOnTop) private var floatOnTop = false
    @StateObject private var selectionState = ViewState(SelectionStats())
    @StateObject private var toastState = ViewState<String?>(nil)
    @StateObject private var widthState = ViewState<CGFloat>(900)
    @StateObject private var toastTask = ViewState<DispatchWorkItem?>(nil)

    private var selection: SelectionStats { selectionState.value }
    private var toast: String? { toastState.value }
    private var editorWidth: CGFloat { widthState.value }

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .auto }
    private var palette: Palette { Palette.resolve(theme, scheme: scheme) }

    /// The sidebar steps aside when the editor gets narrow.
    private var showSidebar: Bool { sidebarVisible && editorWidth >= 420 }

    var body: some View {
        let p = palette
        VStack(spacing: 0) {
            titleBar(p)
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(palette: p)
                        .frame(width: 240)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                editorCard(p)
                    .padding(.leading, showSidebar ? 0 : 8)
                    .padding([.trailing, .bottom], 8)
            }
        }
        .background(p.bgC)
        .ignoresSafeArea()
        .frame(minWidth: 520, minHeight: 360)
        .preferredColorScheme(theme.forcedScheme)
        .tint(p.accentC)
        .background(WindowConfigurator(floatOnTop: floatOnTop))
        .onChange(of: find.query) { find.recompute(in: store.text) }
        .onChange(of: find.isShowing) { find.recompute(in: store.text) }
        .onChange(of: store.text) { if find.isShowing { find.recompute(in: store.text) } }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: importDrop)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .focusEditor, object: nil)
            }
        }
    }

    // MARK: Title bar

    private func titleBar(_ p: Palette) -> some View {
        ZStack {
            Text(store.active?.title ?? "Rubbish Notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.fg2C)
                .lineLimit(1)
                .padding(.horizontal, 120)
            HStack(spacing: 0) {
                Spacer().frame(width: 84)
                iconButton("sidebar.left", tint: p.mutedC, help: "Show or hide the sidebar (⌥⌘S)") {
                    withAnimation(.easeOut(duration: 0.2)) { sidebarVisible.toggle() }
                }
                Spacer()
                iconButton(floatOnTop ? "pin.fill" : "pin", tint: floatOnTop ? p.accentC : p.faintC,
                           help: floatOnTop ? "Stop floating on top (⌥⌘T)" : "Float on top (⌥⌘T)") {
                    floatOnTop.toggle()
                }
                Spacer().frame(width: 12)
            }
        }
        .frame(height: 38)
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(help)
    }

    // MARK: Editor card

    private func editorCard(_ p: Palette) -> some View {
        VStack(spacing: 0) {
            if store.activeID == nil {
                emptyState(p)
            } else {
                EditorView(
                    text: store.text,
                    textVersion: store.textVersion,
                    noteID: store.activeID,
                    palette: p,
                    font: FontChoice.font(fontName, size: fontSize),
                    spellCheck: spellCheck,
                    ruled: ruled,
                    matches: find.matches,
                    activeMatch: find.active,
                    showMatches: find.isShowing,
                    selection: $selectionState.value,
                    onRichPaste: { showToast("Formatting removed") }
                )
            }
            if find.isShowing {
                FindBar(palette: p)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            statusBar(p)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.panelC))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.fgC)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(p.panel2C))
                    .overlay(Capsule().stroke(p.accentC.opacity(0.5), lineWidth: 1))
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { widthState.value = geo.size.width }
                    .onChange(of: geo.size.width) { widthState.value = geo.size.width }
            }
        )
        .animation(.easeOut(duration: 0.18), value: find.isShowing)
        .animation(.easeOut(duration: 0.2), value: toast)
    }

    private func emptyState(_ p: Palette) -> some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Nothing here but rubbish.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.fg2C)
            Button("New Note  ⌘N") { store.newNote() }
                .buttonStyle(PillButtonStyle(palette: p))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusBar(_ p: Palette) -> some View {
        let hasSelection = selection.characters > 0
        let words = hasSelection ? selection.words : Counting.words(store.text)
        let characters = hasSelection ? selection.characters : store.text.count
        return HStack(spacing: 14) {
            stat(words, words == 1 ? "word" : "words", highlight: hasSelection, p)
            stat(characters, characters == 1 ? "character" : "characters", highlight: hasSelection, p)
            if hasSelection {
                Text("selected").foregroundStyle(p.accentTextC)
            } else if words > 0 {
                Text("\(max(1, Int((Double(words) / 220).rounded()))) min read").foregroundStyle(p.mutedC)
            }
            if store.justSaved {
                Label("Saved", systemImage: "checkmark")
                    .foregroundStyle(p.mutedC)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                find.isShowing ? find.hide() : find.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("⌘F  Find & Replace")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.faintC)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.horizontal, 18)
        .frame(height: 34)
        .animation(.easeOut(duration: 0.25), value: store.justSaved)
    }

    private func stat(_ value: Int, _ label: String, highlight: Bool, _ p: Palette) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(highlight ? p.accentTextC : p.fg2C)
            Text(label).foregroundStyle(p.mutedC)
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

/// Reaches the hosting NSWindow for things SwiftUI doesn't expose.
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
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}
