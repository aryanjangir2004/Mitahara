import SwiftUI

@main
struct MitaharaApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register keyboard-frame observers before the first keyboard appears.
        _ = KeyboardScroller.shared
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshFromCloud()
            }
        }
    }
}
