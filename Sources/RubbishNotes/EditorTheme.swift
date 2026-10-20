import AppKit
import SwiftUI

/// Colors for the writing area. "Default" uses the system text colors and
/// the app's accent. The rest are chosen to look clearly different from one
/// another: paper tones, soft pastels, deep colors and a few well-known
/// free schemes (MIT or similarly licensed).
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

    /// Published scheme names (Dracula, Solarized) stay as they are; ours are translated.
    var displayName: String { id == "default" ? L("Default") : L(name) }

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

    /// Light first, then dark; each one a different color family.
    static let all: [EditorTheme] = [
        .standard,
        light("paper", "Paper", bg: 0xF8F1E1, fg: 0x3B2F25, comment: 0x9C8A72, accent: 0xC0392B, selection: 0xEBDDBE),
        light("mint", "Mint", bg: 0xE3F5EA, fg: 0x1E4631, comment: 0x6E9A80, accent: 0x14996B, selection: 0xBFE6CF),
        light("sky", "Sky", bg: 0xE4F0FC, fg: 0x1B3A5C, comment: 0x6F8DB0, accent: 0x1E74D6, selection: 0xC3DCF7),
        light("blossom", "Blossom", bg: 0xFDE9EF, fg: 0x5A2236, comment: 0xB27A8E, accent: 0xD6336C, selection: 0xF8C9D8),
        light("lavender", "Lavender", bg: 0xEFE9FB, fg: 0x35265C, comment: 0x8D7FB5, accent: 0x7048E8, selection: 0xDCD0F7),
        light("solarized-light", "Solarized Light", bg: 0xFDF6E3, fg: 0x586E75, comment: 0x93A1A1, accent: 0x268BD2, selection: 0xEEE8D5),
        dark("midnight", "Midnight", bg: 0x0B1D3A, fg: 0xE3EAF5, comment: 0x6F84A8, accent: 0xF5C451, selection: 0x1F3A66),
        dark("forest", "Forest", bg: 0x12261B, fg: 0xE6EFD9, comment: 0x7C9A80, accent: 0x9BD86B, selection: 0x24452F),
        dark("plum", "Plum", bg: 0x2B1433, fg: 0xF3E4F5, comment: 0x9C7AA6, accent: 0xF08BD6, selection: 0x4A2556),
        dark("espresso", "Espresso", bg: 0x2B1F17, fg: 0xF1E3CF, comment: 0xA08A70, accent: 0xE9965A, selection: 0x4A3627),
        dark("dracula", "Dracula", bg: 0x282A36, fg: 0xF8F8F2, comment: 0x6272A4, accent: 0xBD93F9, selection: 0x44475A),
        dark("terminal", "Terminal", bg: 0x050805, fg: 0x39FF7A, comment: 0x1E8C45, accent: 0x39FF7A, selection: 0x15401F),
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
