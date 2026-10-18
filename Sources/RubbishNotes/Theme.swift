import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case paper, dark, black, auto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .dark: "Dark"
        case .black: "Black"
        case .auto: "Auto"
        }
    }

    /// nil lets the window follow the system appearance.
    var forcedScheme: ColorScheme? {
        switch self {
        case .paper: .light
        case .dark, .black: .dark
        case .auto: nil
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Colors are taken from the logo: crumpled ruled paper on an amber ground.
struct Palette: Equatable {
    let id: String
    let bg: NSColor
    let panel: NSColor
    let panel2: NSColor
    let fg: NSColor
    let fg2: NSColor
    let muted: NSColor
    let faint: NSColor
    let accent: NSColor
    /// Accent dark enough to read as text on the panel.
    let accentText: NSColor
    /// The red margin line of a ruled sheet.
    let margin: NSColor
    /// The blue rules of a ruled sheet.
    let rule: NSColor
    let isDark: Bool

    var accentSoft: NSColor { accent.withAlphaComponent(isDark ? 0.22 : 0.22) }
    var selection: NSColor { accent.withAlphaComponent(isDark ? 0.32 : 0.30) }

    var bgC: Color { Color(nsColor: bg) }
    var panelC: Color { Color(nsColor: panel) }
    var panel2C: Color { Color(nsColor: panel2) }
    var fgC: Color { Color(nsColor: fg) }
    var fg2C: Color { Color(nsColor: fg2) }
    var mutedC: Color { Color(nsColor: muted) }
    var faintC: Color { Color(nsColor: faint) }
    var accentC: Color { Color(nsColor: accent) }
    var accentTextC: Color { Color(nsColor: accentText) }
    var marginC: Color { Color(nsColor: margin) }
    var ruleC: Color { Color(nsColor: rule) }

    static let paper = Palette(
        id: "paper",
        bg: NSColor(hex: 0xEFE5CC),
        panel: NSColor(hex: 0xFBF7EC),
        panel2: NSColor(hex: 0xE3D7B8),
        fg: NSColor(hex: 0x2B261C),
        fg2: NSColor(hex: 0x4F4636),
        muted: NSColor(hex: 0x8A7E64),
        faint: NSColor(hex: 0xADA083),
        accent: NSColor(hex: 0xE5A117),
        accentText: NSColor(hex: 0xA86F00),
        margin: NSColor(hex: 0xD9534A, alpha: 0.55),
        rule: NSColor(hex: 0x6E8FB8, alpha: 0.26),
        isDark: false
    )

    static let dark = Palette(
        id: "dark",
        bg: NSColor(hex: 0x1C1A16),
        panel: NSColor(hex: 0x24211C),
        panel2: NSColor(hex: 0x312C23),
        fg: NSColor(hex: 0xE8E0CD),
        fg2: NSColor(hex: 0xCBC2AE),
        muted: NSColor(hex: 0x8F866F),
        faint: NSColor(hex: 0x645C4A),
        accent: NSColor(hex: 0xF2B126),
        accentText: NSColor(hex: 0xF2B126),
        margin: NSColor(hex: 0xE0645A, alpha: 0.38),
        rule: NSColor(hex: 0xFFFFFF, alpha: 0.055),
        isDark: true
    )

    static let black = Palette(
        id: "black",
        bg: NSColor(hex: 0x000000),
        panel: NSColor(hex: 0x0F0E0B),
        panel2: NSColor(hex: 0x1C1A15),
        fg: NSColor(hex: 0xE8E0CD),
        fg2: NSColor(hex: 0xCBC2AE),
        muted: NSColor(hex: 0x8F866F),
        faint: NSColor(hex: 0x5A5343),
        accent: NSColor(hex: 0xF2B126),
        accentText: NSColor(hex: 0xF2B126),
        margin: NSColor(hex: 0xE0645A, alpha: 0.32),
        rule: NSColor(hex: 0xFFFFFF, alpha: 0.045),
        isDark: true
    )

    static func resolve(_ theme: AppTheme, scheme: ColorScheme) -> Palette {
        switch theme {
        case .paper: .paper
        case .dark: .dark
        case .black: .black
        case .auto: scheme == .dark ? .dark : .paper
        }
    }

    static func == (a: Palette, b: Palette) -> Bool { a.id == b.id }
}

enum FontChoice {
    static let defaultName = "Courier New"
    static let all = [
        "Courier New", "American Typewriter", "SF Mono", "Menlo", "Monaco",
        "Georgia", "Avenir Next", "Helvetica Neue",
    ]

    static func font(_ name: String, size: Double) -> NSFont {
        let size = CGFloat(size)
        if name == "SF Mono" { return .monospacedSystemFont(ofSize: size, weight: .regular) }
        return NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// View-local state. Used instead of @State, whose macro plugin isn't
/// available when building with the Command Line Tools alone.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
