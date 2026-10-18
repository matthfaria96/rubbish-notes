import AppKit
import SwiftUI

struct SelectionStats: Equatable {
    var words = 0
    var characters = 0
}

enum Counting {
    static func words(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

/// Plain-text NSTextView using system colors and the system find bar.
/// Optionally drawn as a ruled sheet, with a red margin line from the logo.
final class EditorTextView: NSTextView {
    var onRichPaste: (() -> Void)?
    var ruled = false
    var lineHeight: CGFloat = 26
    var ruleColor = NSColor.separatorColor
    let maxColumnWidth: CGFloat = 700

    /// Start with the cursor in the note, not in the sidebar list.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
            guard let self, let window, !(window.firstResponder is NSText) else { return }
            window.makeFirstResponder(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(36, floor((newSize.width - maxColumnWidth) / 2))
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: Self.insetHeight)
        }
    }

    /// The inset applies to top and bottom alike; the text starts higher, which
    /// leaves room at the end so the last lines clear the floating word count.
    private static let insetHeight: CGFloat = 56
    private static let topMargin: CGFloat = 24

    override var textContainerOrigin: NSPoint {
        NSPoint(x: textContainerInset.width, y: Self.topMargin)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard ruled, lineHeight > 4 else { return }
        let top = textContainerOrigin.y
        ruleColor.withAlphaComponent(0.35).setFill()
        let firstRule = max(1, floor((rect.minY - top) / lineHeight))
        var y = top + firstRule * lineHeight
        while y <= rect.maxY + lineHeight {
            NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill()
            y += lineHeight
        }
        NSColor.systemRed.withAlphaComponent(0.35).setFill()
        NSRect(x: textContainerOrigin.x - 16, y: rect.minY, width: 1, height: rect.height).fill()
    }

    // Only words come in: formatting from rich pastes is dropped.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html, NSPasteboard.PasteboardType("com.apple.flat-rtfd")]
        let wasRich = pasteboard.availableType(from: richTypes) != nil
        guard let plain = Self.plainString(from: pasteboard) else {
            super.paste(sender)
            return
        }
        insertText(plain, replacementRange: selectedRange())
        if wasRich { onRichPaste?() }
    }

    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    private static func plainString(from pasteboard: NSPasteboard) -> String? {
        if let string = pasteboard.string(forType: .string) { return string }
        // HTML-only pastes are not parsed; RTF is read as text without attachments.
        if let data = pasteboard.data(forType: .rtf) {
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        }
        return nil
    }
}

struct EditorView: NSViewRepresentable {
    let text: String
    let textVersion: Int
    let noteID: UUID?
    let font: NSFont
    let spellCheck: Bool
    let ruled: Bool
    let editable: Bool
    let theme: EditorTheme
    let accent: NSColor
    /// Sidebar search text, highlighted in the open note.
    let highlight: String
    @Binding var selection: SelectionStats
    var onRichPaste: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = EditorTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textColor = .textColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        let coordinator = context.coordinator
        textView.onRichPaste = { [weak coordinator] in coordinator?.parent.onRichPaste() }

        scroll.documentView = textView
        scroll.findBarPosition = .aboveContent
        coordinator.textView = textView
        coordinator.observeFocusRequests()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let textView = c.textView else { return }
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)

        let lineHeight = ceil(font.pointSize * (ruled ? 1.75 : 1.45))
        let styleKey = "\(font.fontName)|\(font.pointSize)|\(ruled)|\(theme.id)"
        if c.styleKey != styleKey {
            c.styleKey = styleKey
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            c.attributes = [
                .font: font,
                .foregroundColor: theme.textNS(),
                .paragraphStyle: paragraph,
                .baselineOffset: ruled ? max(0, lineHeight * 0.2 + font.descender) : 0,
            ]
            textView.defaultParagraphStyle = paragraph
            textView.lineHeight = lineHeight
            textView.ruled = ruled
            textView.ruleColor = theme.secondaryNS()
            scroll.backgroundColor = theme.backgroundNS()
            c.applyAttributes()
            textView.needsDisplay = true
        }
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.isEditable = editable
        textView.insertionPointColor = theme.accentNS(fallback: accent)
        textView.selectedTextAttributes = [.backgroundColor: theme.selectionNS(fallback: accent)]

        if c.lastVersion != textVersion {
            c.lastVersion = textVersion
            if textView.string != text {
                c.syncing = true
                let caret = textView.selectedRange().location
                textView.string = text
                c.applyAttributes()
                let length = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: min(caret, length), length: 0))
                c.syncing = false
            }
            if c.lastNoteID != noteID {
                c.lastNoteID = noteID
                // One undo stack serves the window (so archiving and trashing can be
                // undone too); drop only the previous note's typing from it.
                if let undo = textView.undoManager {
                    undo.removeAllActions(withTarget: textView)
                    if let storage = textView.textStorage { undo.removeAllActions(withTarget: storage) }
                }
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
        }

        let highlightKey = "\(highlight)|\(textVersion)|\(noteID?.uuidString ?? "")"
        if c.highlightKey != highlightKey {
            let noteChanged = !c.highlightKey.hasSuffix(noteID?.uuidString ?? "-")
            c.highlightKey = highlightKey
            c.highlight(highlight, scroll: noteChanged)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: EditorTextView?
        var attributes: [NSAttributedString.Key: Any] = [:]
        var styleKey = ""
        var lastVersion = -1
        var lastNoteID: UUID?
        var syncing = false
        var highlightKey = ""
        private var focusObserver: NSObjectProtocol?

        /// Marks every match of the sidebar search and brings the first into view.
        func highlight(_ query: String, scroll: Bool) {
            guard let textView, let layout = textView.layoutManager else { return }
            let text = textView.string as NSString
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: text.length))
            let query = query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return }
            let color = parent.theme.accentNS(fallback: parent.accent).withAlphaComponent(0.35)
            var range = NSRange(location: 0, length: text.length)
            var first: NSRange?
            while true {
                let hit = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range)
                if hit.location == NSNotFound || hit.length == 0 { break }
                layout.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: hit)
                if first == nil { first = hit }
                range = NSRange(location: NSMaxRange(hit), length: text.length - NSMaxRange(hit))
            }
            if scroll, let first { textView.scrollRangeToVisible(first) }
        }

        init(_ parent: EditorView) { self.parent = parent }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        }

        func observeFocusRequests() {
            focusObserver = NotificationCenter.default.addObserver(forName: .focusEditor, object: nil, queue: .main) { [weak self] _ in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }

        func applyAttributes() {
            guard let textView, let storage = textView.textStorage else { return }
            textView.typingAttributes = attributes
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, let textView else { return }
            NoteStore.shared.editorChanged(textView.string)
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
    }
}
