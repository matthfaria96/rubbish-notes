import AppKit
import SwiftUI

/// The app follows the system look; the only brand color is the logo's red.
enum Brand {
    static let red = Color(nsColor: redNS)
    static let redNS = NSColor(srgbRed: 0.93, green: 0.06, blue: 0.07, alpha: 1)
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum FontChoice {
    static let defaultName = "System"
    static let all = [
        "System", "New York", "SF Mono", "Courier New", "Menlo", "Georgia", "American Typewriter",
    ]

    static func font(_ name: String, size: Double) -> NSFont {
        let size = CGFloat(size)
        let system = NSFont.systemFont(ofSize: size)
        switch name {
        case "System":
            return system
        case "New York":
            let serif = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
            return NSFont(descriptor: serif, size: size) ?? system
        case "SF Mono":
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            return NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) ?? system
        }
    }
}

/// View-local state. Used instead of @State, whose macro plugin isn't
/// available when building with the Command Line Tools alone.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
