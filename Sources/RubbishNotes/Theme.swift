import AppKit
import SwiftUI

/// The app follows the system look; its one brand color comes from the
/// chosen icon and tints the cursor, selection and highlights.
enum IconStyle: String, CaseIterable, Identifiable {
    case blue, red

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .red: "Red"
        }
    }

    /// The .icns in the app bundle; the blue one is the bundle's own icon.
    var resourceName: String {
        switch self {
        case .blue: "AppIcon"
        case .red: "AppIconRed"
        }
    }

    var accentNS: NSColor {
        switch self {
        case .blue: NSColor(srgbRed: 0.27, green: 0.52, blue: 0.98, alpha: 1)
        case .red: NSColor(srgbRed: 0.93, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    var accent: Color { Color(nsColor: accentNS) }

    var image: NSImage? {
        Bundle.main.url(forResource: resourceName, withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }

    static var current: IconStyle {
        IconStyle(rawValue: UserDefaults.standard.string(forKey: Prefs.iconStyle) ?? "") ?? .blue
    }

    /// Swaps the Dock icon while the app runs. Finder keeps the bundle's
    /// blue icon: changing it would modify the signed app bundle.
    func applyToDock() {
        NSApp.applicationIconImage = self == .blue ? nil : image
    }
}

enum Brand {
    static var accent: Color { IconStyle.current.accent }
    static var accentNS: NSColor { IconStyle.current.accentNS }
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
