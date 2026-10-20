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

/// Room around a footer button's icon.
struct LegacyFooterPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Capsule())
    }
}
