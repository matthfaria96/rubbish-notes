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
    /// Image files or pasted image data; returns true when they were kept.
    var onImages: (([URL], Data?) -> Bool)?
    var ruled = false
    var lineHeight: CGFloat = 26
    var ruleColor = NSColor.separatorColor
    let maxColumnWidth: CGFloat = 700
    var blockStyle = InlineBlockStyle(text: .textColor, secondary: .secondaryLabelColor, accent: .controlAccentColor)
    /// Called when a block's text, open state or presence changes.
    var onBlocksChanged: (() -> Void)?
    private var blockHosts: [UUID: InlineBlockHost] = [:]
    /// What each block's view last showed; its view is rebuilt only when this changes.
    private var blockSignatures: [UUID: String] = [:]

    /// Areas of the window (top-left origin) where floating panels and their
    /// buttons sit: the pointer is an arrow there, never the text I-beam.
    static var arrowZones: [CGRect] = []

    private func inArrowZone(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView, !Self.arrowZones.isEmpty else { return false }
        let p = content.convert(event.locationInWindow, from: nil)
        let flipped = CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y)
        return Self.arrowZones.contains { $0.contains(flipped) }
    }

    /// Clicks on a block go to the block, not to the note's text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for host in blockHosts.values where host.frame.contains(local) {
            if let hit = host.hitTest(local) { return hit }
        }
        return super.hitTest(point)
    }

    private func overBlock(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        return blockHosts.values.contains { $0.frame.contains(p) }
    }

    // MARK: Note blocks

    /// Lays each block's view over the spot its attachment holds in the text.
    func layoutInlineBlocks() {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return }
        var seen = Set<UUID>()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let block = value as? InlineBlockAttachment else { return }
            seen.insert(block.blockID)
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            // An open block's text lives in its own field; only a folded one shows it (its preview).
            let shown = block.expanded ? 0 : block.content.hashValue
            let signature = "\(shown)|\(block.expanded)|\(block.title ?? "")|\(isEditable)|\(blockStyle.text)|\(blockStyle.accent)|\(block.isNew)"
            if let host = blockHosts[block.blockID] {
                // Typing elsewhere in the note re-lays the text; the block stays as is.
                if blockSignatures[block.blockID] != signature {
                    host.rootView = blockView(for: block)
                }
            } else {
                let made = InlineBlockHost(rootView: blockView(for: block))
                addSubview(made)
                blockHosts[block.blockID] = made
            }
            blockSignatures[block.blockID] = signature
            if let host = blockHosts[block.blockID], host.frame != rect { host.frame = rect }
        }
        for (id, host) in blockHosts where !seen.contains(id) {
            host.removeFromSuperview()
            blockHosts[id] = nil
            blockSignatures[id] = nil
        }
    }

    private func blockView(for block: InlineBlockAttachment) -> InlineBlockView {
        defer { block.isNew = false }
        return InlineBlockView(
            content: block.content,
            expanded: block.expanded,
            title: block.title,
            editable: isEditable,
            style: blockStyle,
            onEdit: { [weak self, weak block] text in
                block?.content = text
                self?.onBlocksChanged?()
            },
            onToggle: { [weak self, weak block] in
                guard let self, let block else { return }
                block.expanded.toggle()
                self.relayout(block)
                self.onBlocksChanged?()
            },
            onRemove: { [weak self, weak block] in
                guard let self, let block else { return }
                self.confirmRemoval(of: block)
            },
            onRename: { [weak self, weak block] in
                guard let self, let block else { return }
                self.askName(for: block)
            },
            onDragChanged: { [weak self, weak block] translation in
                guard let self, let block else { return }
                self.showDropLine(for: block, translation: translation)
            },
            onDragEnded: { [weak self, weak block] translation in
                guard let self, let block else { return }
                self.move(block, by: translation)
            },
            startsFocused: block.isNew
        )
    }

    /// A small dialog to name the block; Confirm saves, Cancel leaves it.
    private func askName(for block: InlineBlockAttachment) {
        let alert = NSAlert()
        alert.messageText = L("Change Name")
        alert.informativeText = L("Give this note block a name.")
        let field = NSTextField(string: block.title ?? L("Note block"))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.placeholderString = L("Note block")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Confirm"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        let apply = { [weak self, weak block] in
            guard let self, let block else { return }
            let name = InlineBlocks.clean(field.stringValue)
            block.title = name.isEmpty || name == L("Note block") ? nil : name
            self.layoutInlineBlocks()
            self.onBlocksChanged?()
        }
        if let window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { apply() } }
            DispatchQueue.main.async { field.selectText(nil) }
        } else if alert.runModal() == .alertFirstButtonReturn {
            apply()
        }
    }

    /// Asks first; the block and the line it sat on go away together.
    private func confirmRemoval(of block: InlineBlockAttachment) {
        let alert = NSAlert()
        alert.messageText = L("Delete this note block?")
        alert.informativeText = L("Its text will be removed from the note.")
        alert.addButton(withTitle: L("Delete")).hasDestructiveAction = true
        alert.addButton(withTitle: L("Cancel"))
        let remove = { [weak self, weak block] in
            guard let self, let block, let index = self.index(of: block), let storage = self.textStorage else { return }
            let ns = storage.string as NSString
            let ownLine = index + 1 < ns.length && ns.character(at: index + 1) == 10
            let range = NSRange(location: index, length: ownLine ? 2 : 1)
            if self.shouldChangeText(in: range, replacementString: "") {
                storage.replaceCharacters(in: range, with: "")
                self.didChangeText()
            }
        }
        if let window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { remove() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            remove()
        }
    }

    private let dropLine: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1.5
        view.isHidden = true
        return view
    }()

    /// Where a dragged block would land: the character it goes before (nil when
    /// that is where it already is), and the y of that line's top.
    private func dropTarget(for block: InlineBlockAttachment, translation: CGSize) -> (index: Int, y: CGFloat)? {
        guard let from = index(of: block), let storage = textStorage, let layout = layoutManager,
              let container = textContainer, let host = blockHosts[block.blockID] else { return nil }
        // The block lands on the line under the handle, which sits near its top.
        let handle = host.frame.minY + min(16, host.frame.height / 2)
        let drop = NSPoint(x: 4, y: handle + translation.height - textContainerOrigin.y)
        let ns = storage.string as NSString
        var target: Int
        if drop.y > layout.usedRect(for: container).maxY {
            target = ns.length
        } else {
            let glyph = layout.glyphIndex(for: drop, in: container)
            let char = layout.characterIndexForGlyph(at: glyph)
            target = ns.lineRange(for: NSRange(location: min(char, ns.length), length: 0)).location
        }
        let ownLine = from + 1 < ns.length && ns.character(at: from + 1) == 10
        if target >= from && target <= from + (ownLine ? 2 : 1) { return nil }
        let y: CGFloat
        if target >= ns.length {
            y = layout.usedRect(for: container).maxY
        } else {
            let glyph = layout.glyphIndexForCharacter(at: target)
            y = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }
        return (target, y + textContainerOrigin.y)
    }

    /// A line in the theme's accent where the block would go, as in the sidebar.
    private func showDropLine(for block: InlineBlockAttachment, translation: CGSize) {
        if dropLine.superview == nil { addSubview(dropLine) }
        guard abs(translation.height) > 4, let target = dropTarget(for: block, translation: translation) else {
            dropLine.isHidden = true
            return
        }
        let width = min(maxColumnWidth, bounds.width - textContainerOrigin.x * 2)
        dropLine.layer?.backgroundColor = blockStyle.accent.cgColor
        dropLine.frame = NSRect(x: textContainerOrigin.x - 2, y: target.y - 1.5, width: width + 4, height: 3)
        dropLine.isHidden = false
    }

    /// Dropped after a drag: the block moves to the start of the line under it.
    private func move(_ block: InlineBlockAttachment, by translation: CGSize) {
        dropLine.isHidden = true
        guard abs(translation.height) > 4, let from = index(of: block), let storage = textStorage,
              let target = dropTarget(for: block, translation: translation)?.index else { return }
        let ns = storage.string as NSString
        let ownLine = from + 1 < ns.length && ns.character(at: from + 1) == 10
        let removal = NSRange(location: from, length: ownLine ? 2 : 1)
        let piece = storage.attributedSubstring(from: NSRange(location: from, length: 1)).mutableCopy() as! NSMutableAttributedString
        let lineAttrs = typingAttributes
        if target == ns.length, ns.length > 0, ns.character(at: ns.length - 1) != 10 {
            piece.insert(NSAttributedString(string: "\n", attributes: lineAttrs), at: 0)
        }
        piece.append(NSAttributedString(string: "\n", attributes: lineAttrs))
        breakUndoCoalescing()
        // Insert first when the target is above, so the removal range stays valid.
        if target < removal.location {
            replace(NSRange(location: target, length: 0), with: piece)
            replace(NSRange(location: removal.location + piece.length, length: removal.length), with: NSAttributedString())
        } else {
            replace(NSRange(location: target, length: 0), with: piece)
            replace(removal, with: NSAttributedString())
        }
        layoutInlineBlocks()
    }

    private func replace(_ range: NSRange, with string: NSAttributedString) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: string.string) else { return }
        storage.replaceCharacters(in: range, with: string)
        didChangeText()
    }

    private func index(of block: InlineBlockAttachment) -> Int? {
        guard let storage = textStorage else { return nil }
        var found: Int?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? InlineBlockAttachment) === block { found = range.location; stop.pointee = true }
        }
        return found
    }

    private func relayout(_ block: InlineBlockAttachment) {
        guard let index = index(of: block), let layout = layoutManager else { return }
        let range = NSRange(location: index, length: 1)
        layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layout.invalidateDisplay(forCharacterRange: range)
        if let container = textContainer { layout.ensureLayout(for: container) }
        layoutInlineBlocks()
    }

    /// The toolbar's (+): a new open block on its own line at the cursor.
    func insertInlineBlock(attributes: [NSAttributedString.Key: Any]) {
        guard isEditable, let storage = textStorage else { return }
        let range = selectedRange()
        let ns = storage.string as NSString
        let piece = NSMutableAttributedString()
        if range.location > 0, ns.character(at: range.location - 1) != 10 {
            piece.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        let block = InlineBlockAttachment(content: "", expanded: true)
        block.isNew = true
        piece.append(InlineBlocks.attachmentString(block, attributes: attributes))
        let end = NSMaxRange(range)
        if end >= ns.length || ns.character(at: end) != 10 {
            piece.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        guard shouldChangeText(in: range, replacementString: piece.string) else { return }
        storage.replaceCharacters(in: range, with: piece)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + piece.length, length: 0))
        typingAttributes = attributes
        focus(block)
    }

    /// Puts the cursor inside a block's text area (once its view exists).
    private func focus(_ block: InlineBlockAttachment, tries: Int = 8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.layoutInlineBlocks()
            if let host = self.blockHosts[block.blockID], let area = Self.firstTextView(in: host) {
                self.window?.makeFirstResponder(area)
            } else if tries > 1 {
                self.focus(block, tries: tries - 1)
            }
        }
    }

    private static func firstTextView(in view: NSView) -> NSTextView? {
        for sub in view.subviews {
            if let text = sub as? NSTextView { return text }
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }

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
        DispatchQueue.main.async { [weak self] in self?.layoutInlineBlocks() }
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
    /// The footer's buttons float over the bottom of the text; there the
    /// pointer is an arrow, not the text I-beam, since a click there acts.
    private static let footerBand: CGFloat = 64

    private func isOverFooter(_ event: NSEvent) -> Bool {
        convert(event.locationInWindow, from: nil).y > visibleRect.maxY - Self.footerBand
    }

    private func wantsArrow(_ event: NSEvent) -> Bool {
        isOverFooter(event) || inArrowZone(event) || overBlock(event)
    }

    override func mouseMoved(with event: NSEvent) {
        if wantsArrow(event) { NSCursor.arrow.set() } else { super.mouseMoved(with: event) }
    }

    override func cursorUpdate(with event: NSEvent) {
        if wantsArrow(event) { NSCursor.arrow.set() } else { super.cursorUpdate(with: event) }
    }

    /// Esc closes the find bar when it is open.
    override func cancelOperation(_ sender: Any?) {
        if enclosingScrollView?.isFindBarVisible == true {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.hideFindInterface.rawValue
            performTextFinderAction(item)
        } else {
            super.cancelOperation(sender)
        }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html, NSPasteboard.PasteboardType("com.apple.flat-rtfd")]
        let wasRich = pasteboard.availableType(from: richTypes) != nil
        if takeImages(from: pasteboard) { return }
        guard let plain = Self.plainString(from: pasteboard) else {
            super.paste(sender)
            return
        }
        insertText(plain, replacementRange: selectedRange())
        if wasRich { onRichPaste?() }
    }

    override func pasteAsRichText(_ sender: Any?) { paste(sender) }

    /// A plain-text view otherwise disables Paste (and refuses drops) when only an image is offered.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff, .fileURL]
    }

    // Images dropped on the text go to the footer instead of becoming text.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        takeImages(from: sender.draggingPasteboard) || super.performDragOperation(sender)
    }

    private func takeImages(from pasteboard: NSPasteboard) -> Bool {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter(NoteStore.isImageFile)
        if !files.isEmpty { return onImages?(files, nil) ?? false }
        // Screenshots and copied images arrive as data; text with an image keeps the text.
        guard pasteboard.string(forType: .string) == nil,
              pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
              let data = NSImage(pasteboard: pasteboard)?.tiffRepresentation else { return false }
        return onImages?([], data) ?? false
    }

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
    var onImages: ([URL], Data?) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = EditorTextView(frame: .zero)
        // Blocks are attachment cells, which need the TextKit 1 layout manager.
        textView.layoutManager?.delegate = context.coordinator
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
        textView.onImages = { [weak coordinator] files, data in coordinator?.parent.onImages(files, data) ?? false }
        textView.onBlocksChanged = { [weak coordinator] in coordinator?.saveText() }
        NoteStore.shared.findBarVisible = { [weak scroll] in scroll?.isFindBarVisible ?? false }

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
            textView.blockStyle = InlineBlockStyle(text: theme.textNS(), secondary: theme.secondaryNS(),
                                                   accent: theme.accentNS(fallback: accent),
                                                   background: theme.backgroundNS())
            scroll.backgroundColor = theme.backgroundNS()
            c.applyAttributes()
            textView.needsDisplay = true
        }
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.isEditable = editable
        textView.layoutInlineBlocks()
        textView.insertionPointColor = theme.accentNS(fallback: accent)
        textView.selectedTextAttributes = [.backgroundColor: theme.selectionNS(fallback: accent)]

        if c.lastVersion != textVersion {
            c.lastVersion = textVersion
            if c.currentText() != text {
                c.syncing = true
                let caret = textView.selectedRange().location
                textView.textStorage?.setAttributedString(InlineBlocks.attributed(text, attributes: c.attributes))
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

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: EditorView
        weak var textView: EditorTextView?
        var attributes: [NSAttributedString.Key: Any] = [:]
        var styleKey = ""
        var lastVersion = -1
        var lastNoteID: UUID?
        var syncing = false
        var highlightKey = ""
        private var focusObserver: NSObjectProtocol?
        private var insertObserver: NSObjectProtocol?

        /// The note as saved: blocks written back as their markers.
        func currentText() -> String {
            guard let storage = textView?.textStorage else { return "" }
            return InlineBlocks.serialize(storage)
        }

        func saveText() {
            guard !syncing else { return }
            NoteStore.shared.editorChanged(currentText())
        }

        func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
            guard layoutFinishedFlag else { return }
            DispatchQueue.main.async { [weak self] in self?.textView?.layoutInlineBlocks() }
        }

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
            if let insertObserver { NotificationCenter.default.removeObserver(insertObserver) }
        }

        func observeFocusRequests() {
            focusObserver = NotificationCenter.default.addObserver(forName: .focusEditor, object: nil, queue: .main) { [weak self] _ in
                guard let textView = self?.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
            insertObserver = NotificationCenter.default.addObserver(forName: .insertInlineBlock, object: nil, queue: .main) { [weak self] _ in
                guard let self, let textView = self.textView else { return }
                textView.window?.makeFirstResponder(textView)
                textView.insertInlineBlock(attributes: self.attributes)
            }
        }

        func applyAttributes() {
            guard let textView, let storage = textView.textStorage else { return }
            textView.typingAttributes = attributes
            var blocks: [(NSRange, InlineBlockAttachment)] = []
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let block = value as? InlineBlockAttachment { blocks.append((range, block)) }
            }
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            for (range, block) in blocks {
                storage.setAttributes(InlineBlocks.attachmentString(block, attributes: attributes)
                    .attributes(at: 0, effectiveRange: nil), range: range)
            }
            storage.endEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, textView != nil else { return }
            saveText()
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
