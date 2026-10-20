import AppKit
import SwiftUI

/// The sidebar's backdrop. Glass shows what is behind the window, tinted with
/// the theme; off, it is the theme's solid color (or the system's).
struct SidebarBackdrop: View {
    let theme: EditorTheme
    let glass: Bool

    var body: some View {
        let tint = theme.background.map { Color(nsColor: $0) }
        ZStack {
            if glass {
                BehindWindowGlass()
                if let tint { tint.opacity(0.45) }
            } else {
                tint ?? Color(nsColor: .windowBackgroundColor)
            }
        }
        .ignoresSafeArea()
    }
}

/// Real behind-window blur, so the desktop shows through the sidebar.
private struct BehindWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

extension View {
    /// A theme with its own text color sets it for everything drawn here;
    /// .secondary and friends then follow it.
    @ViewBuilder
    func themedForeground(_ theme: EditorTheme) -> some View {
        if let text = theme.text {
            foregroundStyle(Color(nsColor: text))
        } else {
            self
        }
    }
}
