import UniformTypeIdentifiers
import AppKit
import SwiftUI

/// Note blocks written inside a note's text. In the .txt file each one is
///
///     ⟦bloco⟧            (or ⟦bloco recolhido⟧ when collapsed)
///     its text
///     ⟦/bloco⟧
///
/// and in the editor it is a single attachment character with a live view on top.
enum InlineBlocks {
    static let openMarker = "⟦bloco⟧"
    static let collapsedMarker = "⟦bloco recolhido⟧"
    static let closeMarker = "⟦/bloco⟧"

    enum Segment: Equatable {
        case text(String)
        /// `title` is nil while the block keeps its default name.
        case block(content: String, expanded: Bool, title: String? = nil)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: "⟦bloco( recolhido)?(?:: ([^⟧\\n]*))?⟧\\n([\\s\\S]*?)\\n⟦/bloco⟧")

    static func segments(of text: String) -> [Segment] {
        let ns = text as NSString
        var out: [Segment] = []
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                out.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            let named = match.range(at: 2).location == NSNotFound ? nil : ns.substring(with: match.range(at: 2))
            out.append(.block(content: ns.substring(with: match.range(at: 3)),
                              expanded: match.range(at: 1).location == NSNotFound,
                              title: named.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { out.append(.text(ns.substring(from: cursor))) }
        return out
    }

    static func serialize(_ content: String, expanded: Bool, title: String? = nil) -> String {
        let state = expanded ? "⟦bloco" : "⟦bloco recolhido"
        let name = title.map { ": " + clean($0) } ?? ""
        return "\(state)\(name)⟧\n\(content)\n\(closeMarker)"
    }

    /// A name fits on the marker's line: no line breaks, no closing bracket.
    static func clean(_ title: String) -> String {
        title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "⟧", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The text as a person reads it: every block shown open, under its label.
    /// Used for exports and the sidebar preview.
    static func readable(_ text: String) -> String {
        segments(of: text).map { segment in
            switch segment {
            case .text(let string): return string
            case .block(let content, _, let title): return "\(title ?? L("Note block")):\n\(content)"
            }
        }.joined()
    }

    /// The editor's contents: plain text with each block as an attachment.
    static func attributed(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for segment in segments(of: text) {
            switch segment {
            case .text(let string):
                out.append(NSAttributedString(string: string, attributes: attributes))
            case .block(let content, let expanded, let title):
                let block = InlineBlockAttachment(content: content, expanded: expanded)
                block.title = title
                out.append(attachmentString(block, attributes: attributes))
            }
        }
        return out
    }

    static func attachmentString(_ attachment: InlineBlockAttachment, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attrs = attributes
        attrs[.attachment] = attachment
        attrs[.paragraphStyle] = blockParagraph
        attrs[.baselineOffset] = 0
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    /// The block's line must grow to the block's height (the note's lines are fixed).
    static let blockParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        style.paragraphSpacingBefore = 4
        return style
    }()

    /// Back to the file's text. Stray attachment characters (pasted) are dropped.
    static func serialize(_ storage: NSAttributedString) -> String {
        var out = ""
        let ns = storage.string as NSString
        // Whole runs at a time, so emoji and other surrogate pairs stay intact.
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            if let block = value as? InlineBlockAttachment {
                out += serialize(block.content, expanded: block.expanded, title: block.title)
            } else {
                out += ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return out
    }
}

final class InlineBlockAttachment: NSTextAttachment {
    let blockID = UUID()
    var content: String
    var expanded: Bool
    /// nil shows the default "Note block".
    var title: String?

    init(content: String, expanded: Bool) {
        self.content = content
        self.expanded = expanded
        super.init(data: nil, ofType: nil)
        attachmentCell = InlineBlockCell()
    }

    required init?(coder: NSCoder) { fatalError("not coded") }

    /// Wide enough for the label and a glimpse of the first line.
    static let collapsedSize = CGSize(width: 380, height: 30)
    /// Set when the toolbar's (+) makes it, so its text area takes the cursor once.
    var isNew = false
    /// Header plus room for three lines of text.
    static let expandedHeight: CGFloat = 122
}

/// Only reserves room; the block itself is a view laid over that spot.
final class InlineBlockCell: NSTextAttachmentCell {
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let block = attachment as? InlineBlockAttachment
        if block?.expanded ?? true {
            let width = min(560, max(200, lineFrag.width - position.x - 8))
            return NSRect(x: 0, y: -6, width: width, height: InlineBlockAttachment.expandedHeight)
        }
        let size = InlineBlockAttachment.collapsedSize
        return NSRect(x: 0, y: -6, width: size.width, height: size.height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {}
    override func wantsToTrackMouse() -> Bool { false }
}

/// The colors a block borrows from the editor's theme.
struct InlineBlockStyle {
    var text: NSColor
    var secondary: NSColor
    var accent: NSColor
    /// The page color, so a block being dragged hides the lines it passes over.
    var background: NSColor = .textBackgroundColor
}

/// The block on screen. Collapsed: a small chip. Expanded: a box with three
/// lines of text, a copy button and a button to fold it back.
struct InlineBlockView: View {
    let content: String
    let expanded: Bool
    var title: String?
    let editable: Bool
    let style: InlineBlockStyle
    let onEdit: (String) -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    var onRename: () -> Void = {}
    /// While dragging: how far the block has moved; on release, where it was let go.
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    @State private var draft: String?
    @State private var copied = false
    @State private var dragOffset: CGSize = .zero
    @State private var hovering = false
    /// A block just inserted takes the cursor.
    var startsFocused = false

    private var text: Color { Color(nsColor: style.text) }
    private var secondary: Color { Color(nsColor: style.secondary) }

    var body: some View {
        let dragging = dragOffset != .zero
        Group {
            if expanded { box } else { chip }
        }
        .background {
            if dragging {
                RoundedRectangle(cornerRadius: expanded ? 12 : 15, style: .continuous)
                    .fill(Color(nsColor: style.background))
            }
        }
        .scaleEffect(dragging ? 1.02 : 1)
        .offset(y: dragOffset.height)
        .shadow(color: .black.opacity(dragging ? 0.3 : 0), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.12), value: dragging)
    }

    /// Grab here to move the block up or down between the lines.
    private var grip: some View {
        BlockGrip(color: style.secondary) { translation in
            dragOffset = translation
            onDragChanged(translation)
        } onEnd: { translation in
            dragOffset = .zero
            onDragEnded(translation)
        }
        .frame(width: 18, height: 22)
        .help("Drag to move the block")
        .opacity(editable ? 1 : 0)
        .allowsHitTesting(editable)
    }

    /// The first line of the block, shown when it is folded.
    private var preview: String {
        (draft ?? content).split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0.trimmingCharacters(in: .whitespaces)) } ?? ""
    }

    /// The top row: a click anywhere on it opens or folds the block; the
    /// chevron at the far right shows which way it will go.
    private func header(showMenu: Bool) -> some View {
        HStack(spacing: 8) {
            grip
            Text(title ?? L("Note block"))
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .fixedSize()
            if !expanded, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(text.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if showMenu { blockMenu }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 18, height: 20)
        }
        .foregroundStyle(secondary)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(text.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onToggle)
        .help(L(expanded ? "Collapse" : "Expand"))
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var chip: some View {
        header(showMenu: false)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(text.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(text.opacity(0.14)))
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 4) {
            header(showMenu: true)
            BlockTextArea(text: draft ?? content, color: style.text, accent: style.accent,
                          editable: editable, focusOnAppear: startsFocused) {
                draft = $0
                onEdit($0)
            }
            .overlay(alignment: .topLeading) {
                if (draft ?? content).isEmpty {
                    Text("Write or paste here…")
                        .font(.system(size: 13))
                        .foregroundStyle(secondary.opacity(0.8))
                        .padding(.leading, 4)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(text.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(text.opacity(0.14)))
        .onChange(of: content) { if content != draft { draft = nil } }
    }

    /// Copy and Export above, Delete apart below them.
    private var blockMenu: some View {
        Menu {
            Button { copy() } label: {
                Label { Text("Copy Block") } icon: { Image(systemName: "doc.on.doc") }.labelStyle(.titleAndIcon)
            }
            Menu {
                ForEach(BlockExportFormat.allCases) { format in
                    Button { NoteExporter.exportBlock(draft ?? content, title: title, as: format) } label: {
                        Label { Text(format.title) } icon: { Image(systemName: format.symbol) }.labelStyle(.titleAndIcon)
                    }
                }
            } label: {
                Label { Text("Export") } icon: { Image(systemName: "square.and.arrow.up") }.labelStyle(.titleAndIcon)
            }
            if editable {
                Button(action: onRename) {
                    Label { Text("Change Name") } icon: { Image(systemName: "pencil") }.labelStyle(.titleAndIcon)
                }
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label { Text("Delete Block") } icon: { Image(systemName: "trash") }.labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondary)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft ?? content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }
}

/// Hosts a block over the text; the pointer is an arrow on it, not the I-beam.
final class InlineBlockHost: NSHostingView<InlineBlockView> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// The text inside an open block. AppKit, because a SwiftUI text editor
/// hosted inside the note's own text view never receives the click.
struct BlockTextArea: NSViewRepresentable {
    let text: String
    let color: NSColor
    let accent: NSColor
    let editable: Bool
    var focusOnAppear = false
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.isRichText = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 2
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
        view.delegate = context.coordinator
        view.string = text
        if focusOnAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { view.window?.makeFirstResponder(view) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        // While typing here, the view is the truth; an update can lag a key behind.
        let typing = view.window?.firstResponder === view
        if !typing, view.string != text { view.string = text }
        view.textColor = color
        view.insertionPointColor = accent
        view.isEditable = editable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextArea
        init(_ parent: BlockTextArea) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.onChange(view.string)
        }
    }
}

/// The block's drag handle. AppKit handles the mouse itself, so the note's
/// text view underneath never starts a text selection instead.
struct BlockGrip: NSViewRepresentable {
    let color: NSColor
    let onChange: (CGSize) -> Void
    let onEnd: (CGSize) -> Void

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.imageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.imageView.contentTintColor = color
        view.onChange = onChange
        view.onEnd = onEnd
    }

    /// Measures the drag in the note's own coordinates, so scrolling while
    /// dragging (wheel, trackpad or the automatic scroll near an edge) keeps the
    /// block and its drop line under the pointer.
    final class GripView: NSView {
        let imageView = NSImageView()
        var onChange: ((CGSize) -> Void)?
        var onEnd: ((CGSize) -> Void)?
        private var start: NSPoint?
        private var lastWindowPoint: NSPoint?
        private var scrollTimer: Timer?
        private var boundsObserver: NSObjectProtocol?

        override init(frame: NSRect) {
            super.init(frame: frame)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("not coded") }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// The note's text view this handle sits in.
        private var editor: NSTextView? {
            var view = superview
            while let current = view {
                if let text = current as? EditorTextView { return text }
                view = current.superview
            }
            return nil
        }

        private func documentPoint(_ windowPoint: NSPoint) -> NSPoint? {
            editor?.convert(windowPoint, from: nil)
        }

        private func report() {
            guard let start, let window = lastWindowPoint, let now = documentPoint(window) else { return }
            // The text view is flipped: y grows downward, like the block's offset.
            onChange?(CGSize(width: now.x - start.x, height: now.y - start.y))
        }

        override func mouseDown(with event: NSEvent) {
            lastWindowPoint = event.locationInWindow
            start = documentPoint(event.locationInWindow)
            NSCursor.closedHand.push()
            if let clip = editor?.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in self?.report() }
            }
            // Keeps scrolling while the pointer rests near the top or bottom edge.
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                self?.autoscrollNearEdge()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            lastWindowPoint = event.locationInWindow
            report()
        }

        override func mouseUp(with event: NSEvent) {
            lastWindowPoint = event.locationInWindow
            scrollTimer?.invalidate()
            scrollTimer = nil
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            NSCursor.pop()
            if let start, let now = documentPoint(event.locationInWindow) {
                onEnd?(CGSize(width: now.x - start.x, height: now.y - start.y))
            }
            start = nil
        }

        /// Faster the closer the pointer is to (or past) the edge.
        private func autoscrollNearEdge() {
            guard let window = lastWindowPoint, let scroll = editor?.enclosingScrollView,
                  let doc = scroll.documentView else { return }
            let clip = scroll.contentView
            let inClip = clip.convert(window, from: nil)
            let band: CGFloat = 48
            let visible = clip.bounds
            var step: CGFloat = 0
            if inClip.y < visible.minY + band { step = -(visible.minY + band - inClip.y) }
            if inClip.y > visible.maxY - band { step = inClip.y - (visible.maxY - band) }
            guard step != 0 else { return }
            let speed = max(-40, min(40, step / 2))
            let maxY = max(0, doc.frame.height - visible.height)
            let y = max(0, min(maxY, visible.origin.y + speed))
            guard y != visible.origin.y else { return }
            clip.scroll(to: NSPoint(x: visible.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
        }
    }
}
