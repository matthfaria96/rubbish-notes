import AppKit
import SwiftUI

/// The note's name in the bar above it. A click turns it into a field;
/// Return or clicking away saves, Esc puts the old name back.
struct TitleField: View {
    let title: String
    let editable: Bool
    /// Room the title may take, so the buttons after it stay at the far end.
    let width: CGFloat
    let onRename: (String) -> Void
    @StateObject private var draft = ViewState<String?>(nil)

    var body: some View {
        HStack(spacing: 6) {
            if editable {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let text = draft.value {
                RenameField(initial: text, bold: true, onCommit: commit, onCancel: cancel)
            } else {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: begin)
        .help(editable ? L("Click to rename") : "")
        .onChange(of: title) { draft.value = nil }
    }

    private func begin() {
        guard editable, draft.value == nil else { return }
        draft.value = title
    }

    private func cancel() {
        draft.value = nil
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    private func commit(_ text: String) {
        guard draft.value != nil else { return }
        draft.value = nil
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != title { onRename(clean) }
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }
}

/// An AppKit field, because SwiftUI focus doesn't reach into the toolbar:
/// it takes the keyboard itself and selects the whole name.
struct RenameField: NSViewRepresentable {
    let initial: String
    var bold = false
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: initial)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = bold ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        // A closing context menu hands focus back late, so ask again until it sticks.
        Self.takeFocus(field, tries: 6)
        return field
    }

    private static func takeFocus(_ field: NSTextField, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = field.window else { return }
            if field.currentEditor() == nil, window.makeFirstResponder(field) {
                field.currentEditor()?.selectAll(nil)
            }
            if tries > 1 { takeFocus(field, tries: tries - 1) }
        }
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        private var cancelled = false

        init(parent: RenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            cancelled = true
            parent.onCancel()
            return true
        }

        /// Return, Tab or a click elsewhere all end here; that saves.
        func controlTextDidEndEditing(_ note: Notification) {
            guard !cancelled, let field = note.object as? NSTextField else { return }
            parent.onCommit(field.stringValue)
        }
    }
}
