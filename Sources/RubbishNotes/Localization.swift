import AppKit
import Foundation

/// Looks up a translated string from Localizable.strings. SwiftUI already
/// translates string literals; this is for text chosen at run time.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Formats a translated pattern such as "%d words".
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

/// The app's language. "System" follows the Mac; any other choice sets this
/// app's AppleLanguages, which macOS applies on the next launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, pt, es, fr, de, it

    var id: String { rawValue }

    /// Each language in its own name, as macOS lists them.
    var nativeName: String {
        switch self {
        case .system: L("System")
        case .en: "English"
        case .pt: "Português"
        case .es: "Español"
        case .fr: "Français"
        case .de: "Deutsch"
        case .it: "Italiano"
        }
    }

    static var current: AppLanguage {
        let override = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String]
        guard let code = override?.first else { return .system }
        return AppLanguage.allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// Opens a fresh copy of the app and quits this one, so the language takes effect.
    static func relaunch() {
        // Open files with unsaved changes are saved (or let go) first, or nothing happens.
        guard OpenedFiles.shared.reviewUnsaved() else { return }
        NoteStore.shared.flushNow()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
