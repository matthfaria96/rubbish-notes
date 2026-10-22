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
        case block(content: String, expanded: Bool)
    }

    private static let pattern = try! NSRegularExpression(
        pattern: "⟦bloco( recolhido)?⟧\\n([\\s\\S]*?)\\n⟦/bloco⟧")

    static func segments(of text: String) -> [Segment] {
        let ns = text as NSString
        var out: [Segment] = []
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                out.append(.text(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))))
            }
            out.append(.block(content: ns.substring(with: match.range(at: 2)),
                              expanded: match.range(at: 1).location == NSNotFound))
            cursor = NSMaxRange(match.range)
        }
        if cursor < ns.length { out.append(.text(ns.substring(from: cursor))) }
        return out
    }

    static func serialize(_ content: String, expanded: Bool) -> String {
        "\(expanded ? openMarker : collapsedMarker)\n\(content)\n\(closeMarker)"
    }

    /// The text as a person reads it: every block shown open, under its label.
    /// Used for exports and the sidebar preview.
    static func readable(_ text: String) -> String {
        segments(of: text).map { segment in
            switch segment {
            case .text(let string): return string
            case .block(let content, _): return "\(L("Note block")):\n\(content)"
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
            case .block(let content, let expanded):
                out.append(attachmentString(InlineBlockAttachment(content: content, expanded: expanded), attributes: attributes))
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
                out += serialize(block.content, expanded: block.expanded)
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

    init(content: String, expanded: Bool) {
        self.content = content
        self.expanded = expanded
        super.init(data: nil, ofType: nil)
        attachmentCell = InlineBlockCell()
    }

    required init?(coder: NSCoder) { fatalError("not coded") }

    static let collapsedSize = CGSize(width: 200, height: 28)
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
}

/// The block on screen. Collapsed: a small chip. Expanded: a box with three
/// lines of text, a copy button and a button to fold it back.
struct InlineBlockView: View {
    let content: String
    let expanded: Bool
    let editable: Bool
    let style: InlineBlockStyle
    let onEdit: (String) -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void
    @State private var draft: String?
    @State private var copied = false

    private var text: Color { Color(nsColor: style.text) }
    private var secondary: Color { Color(nsColor: style.secondary) }

    var body: some View {
        if expanded { box } else { chip }
    }

    private var chip: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                Image(systemName: "text.alignleft").font(.system(size: 11))
                Text("Note block").font(.callout).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(text.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(text.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Expand")
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        Text("Note block").font(.callout.weight(.medium))
                    }
                    .contentShape(Rectangle())
                }
                .help("Collapse")
                Spacer()
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy Block")
                if editable {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .help("Remove Block")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(secondary)
            BlockTextArea(text: draft ?? content, color: style.text, accent: style.accent, editable: editable) {
                draft = $0
                onEdit($0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(text.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(text.opacity(0.14)))
        .onChange(of: content) { if content != draft { draft = nil } }
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
