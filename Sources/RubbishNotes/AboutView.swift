import AppKit
import SwiftUI

/// Settings › About: centered and quiet, like About This Mac.
struct AboutSettings: View {
    @StateObject private var showLicenses = ViewState(false)

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
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.bottom, 18)
            Text(verbatim: "Rubbish Notes")
                .font(.system(size: 24, weight: .semibold))
            Text(verbatim: version)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)

            Text("Rubbish Notes is a plain-text notes app. Every note is a real .txt file, saved a moment after you stop typing, and pasted text arrives without formatting.", tableName: "About")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 460)
                .padding(.top, 26)

            Text("Rubbish Notes is free software under the GNU GPL v3.0.", tableName: "About")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)

            HStack(spacing: 18) {
                Link("witchmymac.com", destination: URL(string: "http://witchmymac.com")!)
                    .font(.system(size: 12))
                Button { showLicenses.value = true } label: {
                    Text("Open-source licenses", tableName: "About")
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .padding(.horizontal, 20)
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
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 460)
    }
}
