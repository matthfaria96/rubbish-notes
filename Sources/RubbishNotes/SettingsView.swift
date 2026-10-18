import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.theme) private var themeRaw = AppTheme.auto.rawValue
    @AppStorage(Prefs.fontName) private var fontName = FontChoice.defaultName
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.spellCheck) private var spellCheck = false
    @AppStorage(Prefs.ruled) private var ruled = true

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .auto }

    var body: some View {
        let p = Palette.resolve(theme, scheme: scheme)
        VStack(alignment: .leading, spacing: 26) {
            section("THEME", p) {
                HStack(spacing: 14) {
                    ForEach(AppTheme.allCases) { option in
                        ThemeCard(theme: option, selected: option == theme, palette: p)
                            .onTapGesture { themeRaw = option.rawValue }
                    }
                }
                .frame(maxWidth: .infinity)
                Text("Auto follows your system appearance. Black is pure black, made for OLED displays.")
                    .font(.system(size: 11))
                    .foregroundStyle(p.mutedC)
                    .frame(maxWidth: .infinity)
            }

            section("TYPOGRAPHY", p) {
                HStack {
                    Text("Font").foregroundStyle(p.fgC)
                    Picker("Font", selection: $fontName) {
                        ForEach(FontChoice.all, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    Spacer()
                    Toggle("Check spelling", isOn: $spellCheck)
                        .toggleStyle(.switch)
                        .foregroundStyle(p.fgC)
                }
                HStack(spacing: 12) {
                    Text("Size").foregroundStyle(p.fgC)
                    Slider(value: $fontSize, in: 11...28, step: 1)
                        .tint(p.accentC)
                    Text("\(Int(fontSize)) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(p.mutedC)
                        .frame(width: 44, alignment: .trailing)
                }
                Toggle("Ruled paper", isOn: $ruled)
                    .toggleStyle(.switch)
                    .foregroundStyle(p.fgC)
                preview(p)
            }
        }
        .font(.system(size: 13))
        .tint(p.accentC)
        .padding(28)
        .frame(width: 560)
        .background(p.bgC)
        .preferredColorScheme(theme.forcedScheme)
    }

    private func section<Content: View>(_ title: String, _ p: Palette, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(p.faintC)
                .frame(maxWidth: .infinity, alignment: title == "THEME" ? .center : .leading)
            content()
        }
    }

    private func preview(_ p: Palette) -> some View {
        let font = FontChoice.font(fontName, size: fontSize)
        let lineHeight = ceil(font.pointSize * 1.75)
        return ZStack(alignment: .topLeading) {
            if ruled {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Spacer().frame(height: lineHeight - 1)
                        Rectangle().fill(p.ruleC).frame(height: 1)
                    }
                }
                Rectangle().fill(p.marginC).frame(width: 1).padding(.leading, 26)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("written on rubbish,").frame(height: lineHeight, alignment: .bottom)
                Text("kept like treasure.").frame(height: lineHeight, alignment: .bottom)
            }
            .font(Font(font))
            .foregroundStyle(p.fgC)
            .padding(.leading, 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: lineHeight * 3)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.panelC))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A miniature of the main window in a given theme.
struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    let palette: Palette

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if theme == .auto {
                    HStack(spacing: 0) {
                        miniature(.paper)
                        miniature(.dark)
                    }
                } else {
                    miniature(Palette.resolve(theme, scheme: .light))
                }
            }
            .frame(width: 104, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? palette.accentC : palette.faintC.opacity(0.5), lineWidth: selected ? 2 : 1)
            )
            Text(theme.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.fgC : palette.mutedC)
        }
        .contentShape(Rectangle())
    }

    private func miniature(_ p: Palette) -> some View {
        ZStack(alignment: .topLeading) {
            p.bgC
            HStack(spacing: 3) {
                Circle().fill(Color(nsColor: NSColor(hex: 0xFF5F57))).frame(width: 5, height: 5)
                Circle().fill(Color(nsColor: NSColor(hex: 0xFEBC2E))).frame(width: 5, height: 5)
                Circle().fill(Color(nsColor: NSColor(hex: 0x28C840))).frame(width: 5, height: 5)
            }
            .padding(7)
            RoundedRectangle(cornerRadius: 4)
                .fill(p.panelC)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<4, id: \.self) { _ in Rectangle().fill(p.ruleC.opacity(2)).frame(height: 1) }
                    }
                    .padding(.top, 9)
                }
                .overlay(alignment: .leading) { Rectangle().fill(p.marginC).frame(width: 1).padding(.leading, 9) }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(p.fg2C).frame(width: 30, height: 2)
                        Capsule().fill(p.mutedC).frame(width: 20, height: 2)
                    }
                    .padding(.leading, 13)
                    .padding(.top, 6)
                }
                .padding(.top, 18)
                .padding([.leading, .trailing, .bottom], 5)
        }
    }
}
