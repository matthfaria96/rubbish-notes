import AppKit
import SwiftUI

/// Colors for the writing area. "Default" uses the system text colors and
/// the app's accent; the others are the published palettes of well-known
/// free color schemes (all MIT or similarly licensed).
struct EditorTheme: Identifiable, Equatable {
    let id: String
    let name: String
    /// nil follows the system appearance.
    let isDark: Bool?
    let background: NSColor?
    let text: NSColor?
    /// Comments in the original scheme; used for secondary text and rules.
    let secondary: NSColor?
    /// Cursor and highlight color; nil uses the app icon's accent.
    let accent: NSColor?
    let selection: NSColor?

    func backgroundNS() -> NSColor { background ?? .textBackgroundColor }
    func textNS() -> NSColor { text ?? .textColor }
    func secondaryNS() -> NSColor { secondary ?? .secondaryLabelColor }
    func accentNS(fallback: NSColor) -> NSColor { accent ?? fallback }
    func selectionNS(fallback: NSColor) -> NSColor { selection ?? accentNS(fallback: fallback).withAlphaComponent(0.28) }

    static func == (a: EditorTheme, b: EditorTheme) -> Bool { a.id == b.id }

    /// Scheme names are proper names; only "Default" is translated.
    var displayName: String { id == "default" ? L("Default") : name }

    static func named(_ id: String) -> EditorTheme { all.first { $0.id == id } ?? .standard }

    static let standard = EditorTheme(id: "default", name: "Default", isDark: nil,
                                      background: nil, text: nil, secondary: nil, accent: nil, selection: nil)

    private static func dark(_ id: String, _ name: String, bg: UInt32, fg: UInt32, comment: UInt32,
                             accent: UInt32, selection: UInt32) -> EditorTheme {
        EditorTheme(id: id, name: name, isDark: true, background: NSColor(hex: bg), text: NSColor(hex: fg),
                    secondary: NSColor(hex: comment), accent: NSColor(hex: accent), selection: NSColor(hex: selection))
    }

    private static func light(_ id: String, _ name: String, bg: UInt32, fg: UInt32, comment: UInt32,
                              accent: UInt32, selection: UInt32) -> EditorTheme {
        EditorTheme(id: id, name: name, isDark: false, background: NSColor(hex: bg), text: NSColor(hex: fg),
                    secondary: NSColor(hex: comment), accent: NSColor(hex: accent), selection: NSColor(hex: selection))
    }

    static let all: [EditorTheme] = [
        .standard,
        dark("dracula", "Dracula", bg: 0x282A36, fg: 0xF8F8F2, comment: 0x6272A4, accent: 0xBD93F9, selection: 0x44475A),
        dark("nord", "Nord", bg: 0x2E3440, fg: 0xD8DEE9, comment: 0x616E88, accent: 0x88C0D0, selection: 0x434C5E),
        dark("one-dark", "One Dark", bg: 0x282C34, fg: 0xABB2BF, comment: 0x5C6370, accent: 0x61AFEF, selection: 0x3E4451),
        dark("monokai", "Monokai", bg: 0x272822, fg: 0xF8F8F2, comment: 0x75715E, accent: 0xA6E22E, selection: 0x49483E),
        dark("tokyo-night", "Tokyo Night", bg: 0x1A1B26, fg: 0xA9B1D6, comment: 0x565F89, accent: 0x7AA2F7, selection: 0x33467C),
        dark("catppuccin-mocha", "Catppuccin Mocha", bg: 0x1E1E2E, fg: 0xCDD6F4, comment: 0x6C7086, accent: 0xCBA6F7, selection: 0x45475A),
        dark("gruvbox-dark", "Gruvbox Dark", bg: 0x282828, fg: 0xEBDBB2, comment: 0x928374, accent: 0xFABD2F, selection: 0x504945),
        dark("rose-pine", "Rosé Pine", bg: 0x191724, fg: 0xE0DEF4, comment: 0x6E6A86, accent: 0xEBBCBA, selection: 0x403D52),
        dark("solarized-dark", "Solarized Dark", bg: 0x002B36, fg: 0x839496, comment: 0x586E75, accent: 0x268BD2, selection: 0x073642),
        light("solarized-light", "Solarized Light", bg: 0xFDF6E3, fg: 0x657B83, comment: 0x93A1A1, accent: 0x268BD2, selection: 0xEEE8D5),
        light("catppuccin-latte", "Catppuccin Latte", bg: 0xEFF1F5, fg: 0x4C4F69, comment: 0x9CA0B0, accent: 0x8839EF, selection: 0xCCD0DA),
        light("github-light", "GitHub Light", bg: 0xFFFFFF, fg: 0x24292F, comment: 0x6E7781, accent: 0x0969DA, selection: 0xDDF4FF),
    ]
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

/// A small page of text drawn in a theme: title, a selected word, the
/// cursor and a secondary line.
struct ThemeSample: View {
    let theme: EditorTheme
    let fallbackAccent: NSColor
    var large = false

    var body: some View {
        let text = Color(nsColor: theme.textNS())
        let secondary = Color(nsColor: theme.secondaryNS())
        let accent = Color(nsColor: theme.accentNS(fallback: fallbackAccent))
        let selection = Color(nsColor: theme.selectionNS(fallback: fallbackAccent))
        let size: CGFloat = large ? 14 : 9
        VStack(alignment: .leading, spacing: large ? 7 : 3) {
            Text("Shopping list").font(.system(size: size + (large ? 3 : 1), weight: .semibold)).foregroundStyle(text)
            HStack(spacing: 0) {
                Text("written on ").foregroundStyle(text)
                Text("rubbish,")
                    .foregroundStyle(text)
                    .padding(.horizontal, 1)
                    .background(selection, in: RoundedRectangle(cornerRadius: 2))
            }
            HStack(spacing: 1) {
                Text("kept like treasure.").foregroundStyle(text)
                Rectangle().fill(accent).frame(width: large ? 2 : 1.5, height: size + 2)
            }
            Text("— saved a moment ago").foregroundStyle(secondary)
        }
        .font(.system(size: size))
        .lineLimit(1)
        .padding(large ? 18 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.backgroundNS()))
    }
}
