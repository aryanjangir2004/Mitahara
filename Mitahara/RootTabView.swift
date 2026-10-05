import SwiftUI

struct RootTabView: View {
    private enum TabSelection: String, Hashable {
        case log
        case goals
    }

    @AppStorage("selectedMainTab") private var selection: TabSelection = .log

    var body: some View {
        TabView(selection: $selection) {
            Tab("Log", systemImage: "fork.knife", value: .log) {
                HomeView()
            }

            Tab("Goals", systemImage: "checklist", value: .goals) {
                GoalsView()
            }
        }
        .tint(.orange)
    }
}
