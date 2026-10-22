import SwiftUI

/// Liquid Glass on macOS 26+, the closest pre-glass look on macOS 15.
extension View {
    @ViewBuilder
    func compatGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func compatGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A footer button: quiet clear glass, never filled with the accent color.
    func compatFooterButton() -> some View {
        buttonStyle(.plain).compatGlass(in: Capsule())
    }

    @ViewBuilder
    func compatGlassProminentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

/// One size for everything floating in the footer: the corner buttons match
/// each other and the height of the word count in the middle.
enum FooterMetrics {
    static let height: CGFloat = 32
    static let cornerWidth: CGFloat = 64
}

/// A corner button's label: centred in the shared footer size.
struct LegacyFooterPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: FooterMetrics.cornerWidth, height: FooterMetrics.height)
            .contentShape(Capsule())
    }
}
