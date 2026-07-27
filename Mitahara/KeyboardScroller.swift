import UIKit

/// Tracks the keyboard's top edge (in screen coordinates). SwiftUI's built-in
/// keyboard avoidance gives up when a field lives inside a nested horizontal
/// ScrollView (our table), so HomeView uses this plus the focused row's frame
/// to scroll the outer ScrollView itself.
@MainActor
final class KeyboardScroller {
    static let shared = KeyboardScroller()

    private var keyboardTop: CGFloat = .infinity

    /// The keyboard's top y in global/screen coordinates, nil when hidden.
    var currentKeyboardTop: CGFloat? {
        keyboardTop.isFinite ? keyboardTop : nil
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { [weak self] note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                MainActor.assumeIsolated { self?.keyboardTop = frame.minY }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardTop = .infinity }
        }
    }
}
