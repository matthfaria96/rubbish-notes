import SwiftUI

extension View {
    /// The look of a footer panel: it sits in the note's own area just above its
    /// button (so clicks land in it) and grows upward out of that corner.
    func footerPanel(edge: HorizontalEdge, isPresented: Binding<Bool>) -> some View {
        let anchor: UnitPoint = edge == .leading ? .bottomLeading : .bottomTrailing
        return self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2))
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .onExitCommand { isPresented.wrappedValue = false }
            .padding(edge == .leading ? .leading : .trailing, 16)
            // Just above the footer buttons (14 pt up, FooterMetrics.height tall).
            .padding(.bottom, 14 + FooterMetrics.height + 10)
            .transition(.scale(scale: 0.92, anchor: anchor).combined(with: .opacity))
    }
}

/// Where the footer's panels and their buttons are, in window coordinates
/// (top-left origin). Clicks elsewhere close the open panel, and the pointer
/// is an arrow over all of them.
final class FooterPanelZones {
    static let shared = FooterPanelZones()
    private var frames: [String: CGRect] = [:]
    private var monitor: Any?
    /// Closes whatever panel is open.
    var close: (() -> Void)?
    var isOpen = false {
        didSet { publish() }
    }

    func set(_ key: String, _ frame: CGRect?) {
        frames[key] = frame
        publish()
    }

    private func publish() {
        EditorTextView.arrowZones = isOpen ? Array(frames.values) : []
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isOpen, let content = event.window?.contentView else { return event }
            let p = content.convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y)
            // A click on a panel or on the button that toggles it is left to them.
            if !self.frames.values.contains(where: { $0.contains(point) }) {
                self.close?()
            }
            return event
        }
    }
}

extension View {
    /// Reports this view's frame to `FooterPanelZones` under `key` while shown.
    func footerZone(_ key: String) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { FooterPanelZones.shared.set(key, $0) }
            .onDisappear { FooterPanelZones.shared.set(key, nil) }
    }
}
