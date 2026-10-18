import AppKit
import SwiftUI

final class FindState: ObservableObject {
    static let shared = FindState()

    @Published var isShowing = false
    @Published var query = ""
    @Published var replacement = ""
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var active = 0
    @Published private(set) var focusRequest = 0

    private let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    func show() {
        isShowing = true
        focusRequest += 1
    }

    func hide() {
        isShowing = false
        matches = []
        NotificationCenter.default.post(name: .focusEditor, object: nil)
    }

    func recompute(in text: String) {
        guard isShowing, !query.isEmpty else {
            matches = []
            active = 0
            return
        }
        let ns = text as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let hit = ns.range(of: query, options: options, range: searchRange)
            if hit.location == NSNotFound || hit.length == 0 { break }
            found.append(hit)
            let next = NSMaxRange(hit)
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        matches = found
        if active >= found.count { active = 0 }
    }

    func next() {
        guard !matches.isEmpty else { return }
        active = (active + 1) % matches.count
    }

    func previous() {
        guard !matches.isEmpty else { return }
        active = (active - 1 + matches.count) % matches.count
    }

    func replaceCurrent(in store: NoteStore) {
        guard matches.indices.contains(active) else { return }
        let updated = (store.text as NSString).replacingCharacters(in: matches[active], with: replacement)
        store.replaceText(updated)
        recompute(in: store.text)
    }

    func replaceAll(in store: NoteStore) {
        guard !query.isEmpty, !matches.isEmpty else { return }
        let ns = store.text as NSString
        let updated = ns.replacingOccurrences(of: query, with: replacement, options: options, range: NSRange(location: 0, length: ns.length))
        store.replaceText(updated)
        recompute(in: store.text)
    }
}

struct FindBar: View {
    @EnvironmentObject private var find: FindState
    @EnvironmentObject private var store: NoteStore
    let palette: Palette
    @FocusState private var focus: Field?

    private enum Field { case find, replace }

    var body: some View {
        HStack(spacing: 8) {
            field {
                TextField("Find", text: $find.query)
                    .focused($focus, equals: .find)
                    .onSubmit { find.next() }
                if !find.query.isEmpty {
                    Text(find.matches.isEmpty ? "0" : "\(find.active + 1)/\(find.matches.count)")
                        .foregroundStyle(palette.mutedC)
                        .monospacedDigit()
                }
            }
            field {
                TextField("Replace", text: $find.replacement)
                    .focused($focus, equals: .replace)
                    .onSubmit { find.replaceCurrent(in: store) }
            }
            Button("Replace") { find.replaceCurrent(in: store) }
                .buttonStyle(PillButtonStyle(palette: palette))
                .disabled(find.matches.isEmpty)
            Button("Replace All") { find.replaceAll(in: store) }
                .buttonStyle(PillButtonStyle(palette: palette))
                .disabled(find.matches.isEmpty)
        }
        .font(.system(size: 12, design: .monospaced))
        .tint(palette.accentC)
        .padding(6)
        .background(Capsule().fill(palette.panel2C))
        // The field only accepts focus once it is in the window.
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .find } }
        .onChange(of: find.focusRequest) { DispatchQueue.main.async { focus = .find } }
        .onExitCommand { find.hide() }
        .onKeyPress(.return) {
            guard NSEvent.modifierFlags.contains(.shift), focus == .find else { return .ignored }
            find.previous()
            return .handled
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .textFieldStyle(.plain)
            .foregroundStyle(palette.fgC)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(palette.panelC))
    }
}

struct PillButtonStyle: ButtonStyle {
    let palette: Palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(isEnabled ? palette.fgC : palette.mutedC)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(palette.faintC.opacity(configuration.isPressed ? 0.6 : 0.35)))
    }
}
