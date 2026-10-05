import SwiftUI

extension View {
    /// Fades scrolled content out under the status bar. These pages draw
    /// their own headers instead of a navigation bar, so nothing else keeps
    /// content from colliding with the clock.
    func statusBarScrim() -> some View {
        modifier(StatusBarScrim())
    }
}

private struct StatusBarScrim: ViewModifier {
    /// Measured rather than assumed: the pages' black backgrounds ignore
    /// the safe area, which makes their root full-screen, so an overlay
    /// starts at the very top of the display.
    @State private var topInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { inset in
                topInset = inset
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.75),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topInset + 4)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
    }
}
