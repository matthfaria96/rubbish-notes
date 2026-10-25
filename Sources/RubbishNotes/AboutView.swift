import AppKit
import SwiftUI

/// Settings › About: the icon glowing in the app's color, the version in a
/// glass capsule and the links as glass buttons.
struct AboutSettings: View {
    @AppStorage(Prefs.iconStyle) private var iconStyleRaw = IconStyle.blue.rawValue
    @StateObject private var showLicenses = ViewState(false)

    private var accent: Color { (IconStyle(rawValue: iconStyleRaw) ?? .blue).accent }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return String(format: NSLocalizedString("Version %@", tableName: "About", comment: ""), marketing)
            + " (" + build + ")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: accent.opacity(0.45), radius: 26, y: 10)
                .padding(.bottom, 16)
            Text(verbatim: "Rubbish Notes")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(verbatim: version)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .compatGlass(in: Capsule())
                .padding(.top, 8)

            Text("Rubbish Notes is a plain-text notes app. Every note is a real .txt file, saved a moment after you stop typing, and pasted text arrives without formatting.", tableName: "About")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://witchmymac.com")!) {
                    Label { Text(verbatim: "witchmymac.com") } icon: { Image(systemName: "globe") }
                }
                Link(destination: URL(string: "https://github.com/matthfaria96/rubbish-notes")!) {
                    Label { Text(verbatim: "GitHub") } icon: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                }
                Button { showLicenses.value = true } label: {
                    Label { Text(L("Licenses")) } icon: { Image(systemName: "doc.text") }
                }
            }
            .compatGlassButtonStyle()
            .controlSize(.regular)
            .padding(.top, 22)

            CheckForUpdatesButton()
                .compatGlassButtonStyle()
                .controlSize(.regular)
                .padding(.top, 10)

            Text("Rubbish Notes is free software under the GNU GPL v3.0.", tableName: "About")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .padding(.horizontal, 20)
        .background(alignment: .top) {
            // A soft wash of the app's color behind the icon.
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .top, startRadius: 10, endRadius: 280)
                .frame(height: 300)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showLicenses.value) { OpenSourceLicensesView() }
    }
}

/// The license of Rubbish Notes, shown in full so the notice travels with the app.
struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private let notice = """
    Copyright (C) 2026 Matheus Faria
    Source code: https://github.com/matthfaria96/rubbish-notes

    Rubbish Notes is free software: you can redistribute it and/or modify it under \
    the terms of the GNU General Public License as published by the Free Software \
    Foundation, either version 3 of the License, or (at your option) any later \
    version. It is distributed WITHOUT ANY WARRANTY; without even the implied \
    warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Full license text: https://www.gnu.org/licenses/gpl-3.0.html
    """

    /// Sparkle (in-app updates) is MIT: its notice has to travel with the app.
    private let sparkleNotice = """
    Copyright (c) 2006-2013 Andy Matuschak.
    Copyright (c) 2009-2013 Elgato Systems GmbH.
    Copyright (c) 2011-2014 Kornel Lesiński.
    Copyright (c) 2015-2017 Mayur Pawashe.
    Copyright (c) 2014 C.W. Betts.
    Copyright (c) 2014 Petroules Corporation.
    Copyright (c) 2014 Big Nerd Ranch.
    All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy of \
    this software and associated documentation files (the "Software"), to deal in \
    the Software without restriction, including without limitation the rights to \
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of \
    the Software, and to permit persons to whom the Software is furnished to do so, \
    subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all \
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS \
    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR \
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER \
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN \
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

    Sparkle also bundles third-party code under its own licenses \
    (https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE).
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open-source licenses", tableName: "About")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Text("Done", tableName: "About") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Rubbish Notes is free software. Its license is reproduced below.", tableName: "About")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Rubbish Notes").font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "GNU General Public License v3.0")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(verbatim: notice)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
                            .padding(.top, 6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Sparkle").font(.system(size: 13, weight: .semibold))
                        Text(verbatim: "MIT License · https://sparkle-project.org")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(verbatim: sparkleNotice)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
                            .padding(.top, 6)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 460)
    }
}
