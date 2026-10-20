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

    /// A footer button: native glass on macOS 26+, a material capsule before.
    @ViewBuilder
    func compatFooterButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        } else {
            buttonStyle(.plain).compatGlass(in: Capsule())
        }
    }

    /// Notes scrolling under the sidebar's foot get a clear edge on macOS 26+.
    @ViewBuilder
    func compatHardBottomEdge() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            self
        }
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

/// Glass buttons size themselves on macOS 26+; the older plain style needs room.
struct LegacyFooterPadding: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
    }
}
