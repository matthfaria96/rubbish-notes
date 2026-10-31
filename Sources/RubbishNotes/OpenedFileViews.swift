import AppKit
import SwiftUI

/// An outside file in the notes window: just the text, with its kind and
/// counts in the footer. Blocks, images, status and the rest stay hidden.
struct OpenedFileDetail: View {
    @EnvironmentObject private var files: OpenedFiles
    let file: OpenedFile
    /// Font, size and theme, so a change in Settings restyles the text.
    let styleKey: String
    let highlight: String
    let focusMode: Bool
    @StateObject private var selectionState = ViewState(SelectionStats())

    var body: some View {
        if files.unreadable {
            ContentUnavailableView {
                Label(L("Can’t Open “%@”", file.name), systemImage: "doc.questionmark")
            } description: {
                Text("It may have been moved or deleted. Choose it again to keep editing it here.")
            } actions: {
                Button("Choose File…") { chooseAgain() }
                    .compatGlassProminentButtonStyle()
                Button("Remove from List") { files.close(file.id) }
            }
        } else {
            PlainFileEditor(
                text: files.text,
                textVersion: files.textVersion,
                fileID: file.id,
                styleKey: styleKey,
                editable: !files.readOnly,
                highlight: highlight,
                selection: $selectionState.value
            )
            .overlay(alignment: .bottom) {
                if !focusMode { footer }
            }
        }
    }

    /// "Markdown · 120 words · 640 characters", or the selection's counts.
    private var footer: some View {
        let selection = selectionState.value
        let hasSelection = selection.characters > 0
        let words = hasSelection ? selection.words : files.counts.words
        let characters = hasSelection ? selection.characters : files.counts.characters
        let counts = [
            words == 1 ? L("1 word") : L("%ld words", words),
            characters == 1 ? L("1 character") : L("%ld characters", characters),
        ].joined(separator: " · ") + (hasSelection ? " " + L("selected") : "")
        return HStack(spacing: 6) {
            Label(file.kindName, systemImage: file.isMarkdown ? "doc.text" : "doc.plaintext")
                .labelStyle(.titleAndIcon)
            if files.readOnly {
                Text("·").foregroundStyle(.tertiary)
                Label("Read Only", systemImage: "lock")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
            Text("·").foregroundStyle(.tertiary)
            Text(counts)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(hasSelection ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: FooterMetrics.height)
        .compatGlass(in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .help(files.readOnly
              ? L("Some characters in “%@” couldn’t be read, so it is shown but never changed.", file.name)
              : L("Plain text file: saved back to “%@” as you type. Note blocks, images and status aren’t available here.", file.name))
    }

    private func chooseAgain() {
        let panel = NSOpenPanel()
        panel.directoryURL = file.url.deletingLastPathComponent()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let old = file.id
        if files.open(url) != old { files.close(old) }
    }
}

/// One outside file in the sidebar: its name and the folder it was opened from.
struct OpenedFileRow: View {
    let file: OpenedFile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(file.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: file.isMarkdown ? "doc.text" : "doc.plaintext")
                    .foregroundStyle(.secondary)
            }
            Label {
                Text(L("in %@", file.folderName)).lineLimit(1)
            } icon: {
                Image(systemName: "folder").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .contextMenu { OpenedFileMenu(file: file).labelStyle(.titleAndIcon) }
        .swipeActions(edge: .trailing) {
            Button("Remove from List", systemImage: "xmark") { OpenedFiles.shared.close(file.id) }
                .tint(.gray)
        }
    }
}

/// What an outside file offers: in its row's right click, the toolbar's ··· and the Note menu.
struct OpenedFileMenu: View {
    let file: OpenedFile

    var body: some View {
        Button("Show in Finder", systemImage: "folder") { OpenedFiles.shared.reveal(file.id) }
        Button("Open in Separate Window", systemImage: "macwindow") {
            // Never open in two places at once: each would save over the other.
            OpenedFiles.shared.leave()
            if OpenedFiles.shared.activeID != file.id { PlainTextDocument.open(file.url) }
        }
        Button("Copy to My Notes", systemImage: "square.and.arrow.down.on.square") {
            OpenedFiles.shared.flushNow()
            NoteStore.shared.importFiles([file.url])
        }
        Divider()
        Button("Remove from List", systemImage: "xmark") { OpenedFiles.shared.close(file.id) }
    }
}

/// The toolbar while an outside file is shown: Find and the file's menu.
struct OpenedFileToolbar: ToolbarContent {
    let file: OpenedFile

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                TextFinder.toggle()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find in File (⌘F)")

            Menu {
                OpenedFileMenu(file: file).labelStyle(.titleAndIcon)
            } label: {
                Label("More", systemImage: "ellipsis").labelStyle(.iconOnly)
            }
            .menuIndicator(.hidden)
            .help("More")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
    }
}

/// A plain NSTextView for an outside file, laid out like the note editor
/// (centred column, room below for the footer) but without blocks or images.
struct PlainFileEditor: NSViewRepresentable {
    let text: String
    let textVersion: Int
    let fileID: UUID
    let styleKey: String
    let editable: Bool
    let highlight: String
    @Binding var selection: SelectionStats

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The window's undo stack outlives this view; its typing goes with it.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let textView = coordinator.textView, let undo = textView.undoManager else { return }
        undo.removeAllActions(withTarget: textView)
        if let storage = textView.textStorage { undo.removeAllActions(withTarget: storage) }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let textView = PlainFileTextView(frame: .zero)
        PlainTextLook.configure(textView)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        scroll.documentView = textView
        scroll.findBarPosition = .aboveContent
        NoteStore.shared.findBarVisible = { [weak scroll] in scroll?.isFindBarVisible ?? false }
        context.coordinator.textView = textView
        context.coordinator.observeFocusRequests()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let textView = c.textView else { return }
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.isEditable = editable
        if c.lastVersion != textVersion {
            c.lastVersion = textVersion
            if textView.string != text {
                c.syncing = true
                let caret = textView.selectedRange().location
                textView.string = text
                textView.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
                c.syncing = false
                c.styleKey = ""
            }
            if c.lastFileID != fileID {
                c.lastFileID = fileID
                textView.undoManager?.removeAllActions(withTarget: textView)
                if let storage = textView.textStorage { textView.undoManager?.removeAllActions(withTarget: storage) }
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
        }
        if c.styleKey != styleKey {
            c.styleKey = styleKey
            let theme = PlainTextLook.apply(to: textView)
            scroll.backgroundColor = theme.backgroundNS()
        }
        if c.highlightKey != "\(highlight)|\(textVersion)" {
            c.highlightKey = "\(highlight)|\(textVersion)"
            c.highlight(highlight)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainFileEditor
        weak var textView: NSTextView?
        var lastVersion = -1
        var lastFileID: UUID?
        var styleKey = ""
        var highlightKey = ""
        var syncing = false
        private var focusObserver: NSObjectProtocol?

        init(_ parent: PlainFileEditor) { self.parent = parent }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        }

        func observeFocusRequests() {
            focusObserver = NotificationCenter.default.addObserver(forName: .focusEditor, object: nil, queue: .main) { [weak self] _ in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, let textView else { return }
            OpenedFiles.shared.editorChanged(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
            let stats = SelectionStats(words: Counting.words(selected), characters: selected.count)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.selection != stats else { return }
                self.parent.selection = stats
            }
        }

        /// Marks the sidebar search in the text, as in notes.
        func highlight(_ query: String) {
            guard let textView, let layout = textView.layoutManager else { return }
            let text = textView.string as NSString
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
            let query = query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            let color = textView.insertionPointColor.withAlphaComponent(0.35)
            var range = NSRange(location: 0, length: text.length)
            while true {
                let hit = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range)
                if hit.location == NSNotFound || hit.length == 0 { break }
                layout.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: hit)
                range = NSRange(location: NSMaxRange(hit), length: text.length - NSMaxRange(hit))
            }
        }
    }
}

/// Keeps the text in a centred column like the note editor, with room at the
/// bottom so the last lines clear the footer.
final class PlainFileTextView: NSTextView {
    private static let maxColumnWidth: CGFloat = 700
    private static let insetHeight: CGFloat = 56
    private static let topMargin: CGFloat = 24

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(36, floor((newSize.width - Self.maxColumnWidth) / 2))
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: Self.insetHeight)
        }
    }

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: Self.topMargin)
    }
}
