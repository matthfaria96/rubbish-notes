import SwiftUI

extension View {
    /// The look of a footer panel: it sits in the note's own area just above its
    /// button (so clicks land in it) and grows upward out of that corner.
    func footerPanel(edge: HorizontalEdge, isPresented: Binding<Bool>) -> some View {
        let anchor: UnitPoint = edge == .leading ? .bottomLeading : .bottomTrailing
        return self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.2))
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
            .onExitCommand { isPresented.wrappedValue = false }
            .padding(edge == .leading ? .leading : .trailing, 16)
            // Footer buttons sit 14 pt up and are about 34 pt tall.
            .padding(.bottom, 14 + 34 + 10)
            .transition(.scale(scale: 0.92, anchor: anchor).combined(with: .opacity))
    }
}
