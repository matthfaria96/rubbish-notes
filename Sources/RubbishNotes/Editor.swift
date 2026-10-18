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

/// Plain-text NSTextView drawn as a ruled sheet: blue rules on a fixed line
/// height and a red margin line to the left of the text column.
final class EditorTextView: NSTextView {
    var onRichPaste: (() -> Void)?
    var ruled = true
    var lineHeight: CGFloat = 26
    var ruleColor = NSColor.clear
    var marginColor = NSColor.clear
    let maxColumnWidth: CGFloat = 680

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(44, floor((newSize.width - maxColumnWidth) / 2))
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: 34)
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard ruled, lineHeight > 4 else { return }
        let top = textContainerOrigin.y
        ruleColor.setFill()
        let firstRule = max(1, floor((rect.minY - top) / lineHeight))
        var y = top + firstRule * lineHeight
        while y <= rect.maxY + lineHeight {
            NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill()
            y += lineHeight
        }
        marginColor.setFill()
        NSRect(x: textContainerOrigin.x - 18, y: rect.minY, width: 1, height: rect.height).fill()
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
        if let data = pasteboard.data(forType: .rtf) { return NSAttributedString(rtf: data, documentAttributes: nil)?.string }
        if let data = pasteboard.data(forType: .html) { return NSAttributedString(html: data, documentAttributes: nil)?.string }
        return nil
    }
}

struct EditorView: NSViewRepresentable {
    let text: String
    let textVersion: Int
    let noteID: UUID?
    let palette: Palette
    let font: NSFont
    let spellCheck: Bool
    let ruled: Bool
    let matches: [NSRange]
    let activeMatch: Int
    let showMatches: Bool
    @Binding var selection: SelectionStats
    var onRichPaste: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = EditorTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.drawsBackground = false
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
        coordinator.textView = textView
        coordinator.observeFocusRequests()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let textView = c.textView else { return }
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)

        let lineHeight = ceil(font.pointSize * 1.75)
        let styleKey = "\(font.fontName)|\(font.pointSize)|\(palette.id)|\(ruled)"
        if c.styleKey != styleKey {
            c.styleKey = styleKey
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            c.attributes = [
                .font: font,
                .foregroundColor: palette.fg,
                .paragraphStyle: paragraph,
                .baselineOffset: max(0, lineHeight * 0.2 + font.descender),
            ]
            textView.defaultParagraphStyle = paragraph
            textView.insertionPointColor = palette.accent
            textView.selectedTextAttributes = [.backgroundColor: palette.selection]
            textView.lineHeight = lineHeight
            textView.ruleColor = palette.rule
            textView.marginColor = palette.margin
            textView.ruled = ruled
            c.applyAttributes()
            textView.needsDisplay = true
        }
        textView.isContinuousSpellCheckingEnabled = spellCheck

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
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
            }
            c.matchesKey = ""
        }

        let matchesKey = showMatches ? matches.map { "\($0.location):\($0.length)" }.joined(separator: ",") + "#\(activeMatch)" : ""
        if c.matchesKey != matchesKey {
            c.matchesKey = matchesKey
            c.highlight(matches: showMatches ? matches : [], active: activeMatch)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: EditorTextView?
        var attributes: [NSAttributedString.Key: Any] = [:]
        var styleKey = ""
        var matchesKey = ""
        var lastVersion = -1
        var lastNoteID: UUID?
        var syncing = false
        private var focusObserver: NSObjectProtocol?

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

        func highlight(matches: [NSRange], active: Int) {
            guard let textView, let layout = textView.layoutManager else { return }
            let length = (textView.string as NSString).length
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for (i, range) in matches.enumerated() where NSMaxRange(range) <= length {
                let color = i == active ? parent.palette.accent.withAlphaComponent(0.55) : parent.palette.accentSoft
                layout.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
            if matches.indices.contains(active), NSMaxRange(matches[active]) <= length {
                textView.scrollRangeToVisible(matches[active])
            }
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
