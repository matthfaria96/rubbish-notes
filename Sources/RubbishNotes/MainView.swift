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
    @AppStorage(Prefs.windowTranslucent) private var translucent = true
    @AppStorage(Prefs.windowOpacity) private var opacity = Prefs.defaultWindowOpacity
    @AppStorage(Prefs.iconStyle) private var iconStyleRaw = IconStyle.blue.rawValue
    @AppStorage(Prefs.editorTheme) private var themeID = EditorTheme.standard.id
    /// Hides everything around the text except the button that ends it.
    @AppStorage(Prefs.focusMode) private var focusMode = false
    @StateObject private var selectionState = ViewState(SelectionStats())
    @StateObject private var toastState = ViewState<Toast?>(nil)
    @StateObject private var toastTask = ViewState<DispatchWorkItem?>(nil)
    @StateObject private var searchState = ViewState("")
    @StateObject private var columns = ViewState(NavigationSplitViewVisibility.all)
    @StateObject private var detailWidth = ViewState<CGFloat>(600)
    /// The note waiting for the "Move to Trash?" confirmation.
    @StateObject private var confirmTrash = ViewState<UUID?>(nil)
    @StateObject private var blocksOpen = ViewState(false)
    @StateObject private var imagesHintOpen = ViewState(false)
    @StateObject private var lightbox = ViewState<URL?>(nil)
    /// Images waiting for the delete confirmation.
    @StateObject private var pendingDelete = ViewState<[URL]>([])

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
            SidebarView(query: $searchState.value)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } detail: {
            detail
        }
        .toolbar(removing: focusMode ? .sidebarToggle : nil)
        .onChange(of: focusMode, initial: true) {
            withAnimation(.smooth(duration: 0.3)) { columns.value = focusMode ? .detailOnly : .all }
        }
        // The theme colors the whole window, not just the page.
        .tint(Color(nsColor: theme.accentNS(fallback: iconStyle.accentNS)))
        .themedForeground(theme)
        .preferredColorScheme(colorScheme)
        .background(WindowConfigurator(
            floatOnTop: floatOnTop,
            opacity: translucent ? min(1, max(0.4, opacity)) : 1,
            background: theme.background
        ))
        .onDrop(of: [.fileURL], isTargeted: nil, perform: importDrop)
        .onChange(of: store.notice) {
            guard let message = store.notice else { return }
            showToast(message)
            store.notice = nil
        }
        .onChange(of: store.undoNotice) {
            guard let message = store.undoNotice else { return }
            showToast(message, undoable: true)
            store.undoNotice = nil
        }
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
                        .compatGlassProminentButtonStyle()
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
                    highlight: searchState.value,
                    selection: $selectionState.value,
                    onRichPaste: { showToast(L("Formatting Removed")) },
                    onImages: attachImages
                )
                .overlay(alignment: .bottom) {
                    if !focusMode {
                        if isTrashed { trashBanner } else { statusCapsule }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !focusMode, !isTrashed, let id = store.activeID {
                        BlocksButton(noteID: id, open: $blocksOpen.value)
                            .padding(.leading, 16)
                            .padding(.bottom, 14)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if blocksOpen.value, !focusMode, !isTrashed, let id = store.activeID {
                        BlocksPanel(noteID: id) { blocksOpen.value = false }
                            .footerPanel(edge: .leading, isPresented: $blocksOpen.value)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if imagesHintOpen.value, !focusMode, !isTrashed {
                        ImagesHintPanel(onChoose: chooseImages) { imagesHintOpen.value = false }
                            .footerPanel(edge: .trailing, isPresented: $imagesHintOpen.value)
                    }
                }
                // One corner panel at a time.
                .onChange(of: blocksOpen.value) { if blocksOpen.value { imagesHintOpen.value = false } }
                .onChange(of: imagesHintOpen.value) { if imagesHintOpen.value { blocksOpen.value = false } }
                .animation(.spring(duration: 0.28, bounce: 0.1), value: blocksOpen.value)
                .animation(.spring(duration: 0.28, bounce: 0.1), value: imagesHintOpen.value)
                .overlay(alignment: .bottomTrailing) { attachmentStrip }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { detailWidth.value = $0 }
        .overlay { lightboxView }
        .overlay(alignment: .top) { toast }
        .onChange(of: store.activeID) {
            lightbox.value = nil
            blocksOpen.value = false
            imagesHintOpen.value = false
        }
        .confirmationDialog(L("Move this note to the Trash?"), isPresented: Binding(
            get: { confirmTrash.value != nil }, set: { if !$0 { confirmTrash.value = nil } }
        )) {
            Button(L("Move to Trash"), role: .destructive) {
                if let id = confirmTrash.value { store.trash(id) }
                confirmTrash.value = nil
            }
        } message: {
            Text("You can restore it from the Trash later.")
        }
        .confirmationDialog(deleteTitle, isPresented: deleteBinding) {
            Button(L("Delete"), role: .destructive) { confirmDelete() }
        } message: {
            Text("You can’t undo this.")
        }
        // The window keeps its title (Window menu); the bar shows the editable one.
        .navigationTitle(store.active?.title ?? "Rubbish Notes")
        .toolbar(removing: .title)
        .toolbar {
            if !focusMode {
                if #available(macOS 26, *) {
                    // Plain text on the bar, not a glass pill; a flexible space
                    // then carries the buttons to the far edge.
                    ToolbarItem(placement: .navigation) { titleField(width: nil) }
                        .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                } else {
                    // Leaves room for the buttons on the right, so none spill into ».
                    ToolbarItem(placement: .navigation) {
                        titleField(width: min(440, max(120, detailWidth.value - 340)))
                    }
                }
            }
            if !focusMode { detailToolbar }
            ToolbarItem(placement: .primaryAction) { focusButton }
        }
        .animation(.smooth(duration: 0.25), value: toastState.value)
    }

    private func titleField(width: CGFloat?) -> some View {
        TitleField(
            title: store.active?.title ?? "Rubbish Notes",
            editable: store.active.map { $0.location != .trash } ?? false,
            width: width
        ) { newTitle in
            if let id = store.activeID { store.rename(id, to: newTitle) }
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
                Button {
                    TextFinder.perform(.showFindInterface)
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .help("Find in Note (⌘F)")

                if note.location == .inbox {
                    Button {
                        store.togglePin(note.id)
                    } label: {
                        Label(L(note.pinned ? "Unpin" : "Pin"), systemImage: note.pinned ? "pin.slash" : "pin")
                    }
                    .help(L(note.pinned ? "Unpin Note" : "Pin Note"))
                }

                Button {
                    note.location == .archive ? store.restore(note.id) : store.archive(note.id)
                } label: {
                    Label(L(note.location == .archive ? "Move to Inbox" : "Archive"),
                          systemImage: note.location == .archive ? "tray.and.arrow.up" : "archivebox")
                }
                .help(L(note.location == .archive ? "Move to Inbox" : "Archive Note"))

                Menu {
                    ForEach(NoteExportFormat.allCases) { format in
                        Button(L("Export as %@…", format.title)) { export(note, as: format) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .menuIndicator(.hidden)
                .help(store.attachmentURLs(of: note.id).isEmpty ? L("Export Note") : L("Export Note with its images (.zip)"))
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmTrash.value = note.id
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .help("Move to Trash")
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
        }
    }

    private func export(_ note: NoteEntry, as format: NoteExportFormat) {
        store.flushNow()
        NoteExporter.export(
            title: note.title,
            text: store.text,
            blocks: store.blocks(of: note.id),
            images: store.attachmentURLs(of: note.id),
            as: format
        )
    }

    private var focusButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { focusMode.toggle() }
        } label: {
            // On: a filled bolt with a small green light.
            Image(systemName: focusMode ? "bolt.fill" : "bolt")
                .overlay(alignment: .topTrailing) {
                    if focusMode {
                        Circle()
                            .fill(Color.green.gradient)
                            .frame(width: 7, height: 7)
                            .shadow(color: .green.opacity(0.8), radius: 3)
                            .offset(x: 5, y: -3)
                    }
                }
                .accessibilityLabel(L(focusMode ? "Exit Focus Mode" : "Focus Mode"))
        }
        .help(L(focusMode ? "Exit Focus Mode (⇧⌘F)" : "Focus Mode (⇧⌘F)"))
    }

    // MARK: Glass overlays

    private var trashBanner: some View {
        HStack(spacing: 12) {
            Label("This note is in the Trash.", systemImage: "trash")
                .foregroundStyle(.secondary)
            Button("Restore") {
                if let id = store.activeID { store.restore(id) }
            }
            .compatGlassProminentButtonStyle()
        }
        .font(.callout)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .compatGlass(in: Capsule())
        .padding(.bottom, 14)
    }

    private var statusCapsule: some View {
        let selection = selectionState.value
        let hasSelection = selection.characters > 0
        let words = hasSelection ? selection.words : store.counts.words
        let characters = hasSelection ? selection.characters : store.counts.characters
        let minutes = max(1, Int((Double(words) / 220).rounded()))
        return HStack(spacing: 6) {
            if let note = store.active {
                StatusDots(status: note.currentStatus) { store.cycleStatus(note.id) }
                Text("·").foregroundStyle(.tertiary).allowsHitTesting(false)
            }
            Group {
            Text(words == 1 ? L("1 word") : L("%ld words", words))
            Text("·").foregroundStyle(.tertiary)
            Text(characters == 1 ? L("1 character") : L("%ld characters", characters))
            if hasSelection {
                Text("selected").foregroundStyle(iconStyle.accent)
            } else if words > 0 {
                Text("·").foregroundStyle(.tertiary)
                Text(L("%ld min read", minutes))
            }
            }
            .allowsHitTesting(false)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .compatGlass(in: Capsule())
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !focusMode, let id = store.activeID {
            let urls = store.attachmentURLs(of: id)
            if urls.isEmpty {
                if !isTrashed {
                    ImagesHintButton(open: $imagesHintOpen.value)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                }
            } else {
                AttachmentShelf(urls: urls) { url in
                    withAnimation(ImageLightbox.motion) { lightbox.value = url }
                }
                    .padding(.trailing, 16)
                    .padding(.bottom, 10)
                    .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var lightboxView: some View {
        if let id = store.activeID, lightbox.value != nil {
            let urls = store.attachmentURLs(of: id)
            ImageLightbox(
                urls: urls,
                current: $lightbox.value,
                title: store.active?.title ?? "",
                onDelete: { pendingDelete.value = [$0] },
                onDeleteAll: { pendingDelete.value = urls },
                theme: theme
            )
            // Grows out of the thumbnails' corner and shrinks back into it.
            .transition(.scale(scale: 0.12, anchor: .bottomTrailing).combined(with: .opacity))
        }
    }

    private var deleteTitle: String {
        pendingDelete.value.count == 1 ? L("Delete this image?") : L("Delete %ld images?", pendingDelete.value.count)
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !pendingDelete.value.isEmpty }, set: { if !$0 { pendingDelete.value = [] } })
    }

    /// Deletes the confirmed images; the lightbox moves on to a neighbour or closes.
    private func confirmDelete() {
        guard let id = store.activeID else { return }
        let doomed = pendingDelete.value
        let before = store.attachmentURLs(of: id)
        pendingDelete.value = []
        if doomed.count == before.count {
            store.removeAllAttachments(of: id)
        } else {
            doomed.forEach { store.removeAttachment($0.lastPathComponent, from: id) }
        }
        let rest = store.attachmentURLs(of: id)
        if let open = lightbox.value, doomed.contains(open) {
            let position = before.firstIndex(of: open) ?? 0
            if rest.isEmpty {
                withAnimation(ImageLightbox.motion) { lightbox.value = nil }
            } else {
                lightbox.value = rest[min(position, rest.count - 1)]
            }
        }
    }

    private func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        if !attachImages(panel.urls, nil) { NSSound.beep() }
    }

    /// Images go to the open note's footer, never into its text.
    private func attachImages(_ files: [URL], _ data: Data?) -> Bool {
        guard store.activeID != nil, !isTrashed else { return false }
        let attached = files.isEmpty ? data.map { store.attachImageData($0) } ?? false : store.attachImageFiles(files)
        if attached {
            imagesHintOpen.value = false
            showToast(L("Image kept in the footer"))
        }
        return attached
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = toastState.value {
            HStack(spacing: 10) {
                Label(toast.message, systemImage: toast.undoable ? "checkmark" : "textformat")
                    .font(.callout.weight(.medium))
                if toast.undoable {
                    Button(L("Undo")) {
                        store.undoLastMove()
                        toastState.value = nil
                    }
                    .compatGlassProminentButtonStyle()
                    .controlSize(.small)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, toast.undoable ? 6 : 16)
            .padding(.vertical, toast.undoable ? 5 : 9)
            .compatGlass(in: Capsule())
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func showToast(_ message: String, undoable: Bool = false) {
        toastTask.value?.cancel()
        toastState.value = Toast(message: message, undoable: undoable)
        let state = toastState
        let work = DispatchWorkItem { state.value = nil }
        toastTask.value = work
        // Leave time to reach the Undo button.
        DispatchQueue.main.asyncAfter(deadline: .now() + (undoable ? 4 : 1.6), execute: work)
    }

    private func importDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if NoteStore.isImageFile(url) {
                        if !attachImages([url], nil) { NSSound.beep() }
                    } else {
                        store.importFiles([url])
                    }
                }
            }
        }
        return accepted
    }
}

/// Reaches the hosting NSWindow for the float-on-top level.
struct WindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool
    let opacity: Double
    /// The theme's page color, so the bar above the note matches it.
    let background: NSColor?

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
        window.alphaValue = opacity
        window.backgroundColor = background ?? .windowBackgroundColor
        NoteStore.shared.undoManager = window.undoManager
        window.tabbingMode = .disallowed
    }
}

private struct Toast: Equatable {
    let message: String
    let undoable: Bool
}

