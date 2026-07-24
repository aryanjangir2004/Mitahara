import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmErase = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Krec \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        value: Binding(
                            get: { store.graceDaysPerMonth },
                            set: { store.graceDaysPerMonth = $0 }
                        ),
                        in: 0...5
                    ) {
                        HStack {
                            Text("Grace days")
                            Spacer()
                            Text(store.graceDaysPerMonth == 0 ? "Strict" : "\(store.graceDaysPerMonth)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Streak")
                } footer: {
                    Text(store.graceDaysPerMonth == 0
                         ? "Strict: missing a day breaks your streak."
                         : "Up to \(store.graceDaysPerMonth) missed day\(store.graceDaysPerMonth == 1 ? "" : "s") per month won't break your streak — they just don't add to it. Grace days show amber in the calendar.")
                }

                Section {
                    Button("Erase All Data", role: .destructive) {
                        confirmErase = true
                    }
                } footer: {
                    Text("Deletes every entry, column and goal — from this device and your iCloud.")
                }

                Section {
                } footer: {
                    Text(version)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "This permanently deletes all your data from this device and iCloud. This cannot be undone.",
                isPresented: $confirmErase,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive) {
                    store.eraseAllData()
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
