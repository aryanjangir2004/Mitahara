import SwiftUI

struct SettingsSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmErase = false
    @AppStorage("didDismissHint") private var didDismissHint = false

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
                         ? "Gold, silver and bronze days add to your streak. One semi-grace day per month bridges it for free; after that, a missed or semi-grace day breaks it."
                         : "Gold, silver and bronze days add to your streak. One semi-grace day each month is free. After that, up to \(store.graceDaysPerMonth) semi-grace or missed day\(store.graceDaysPerMonth == 1 ? "" : "s") can bridge the streak without adding to it.")
                }

                Section {
                    resultRow(color: DayTier.gold.color, name: "Gold", detail: "Everything met")
                    resultRow(color: DayTier.silver.color, name: "Silver", detail: "1 missed, or 75%+ met")
                    resultRow(color: DayTier.bronze.color, name: "Bronze", detail: "2 missed, or 60%+ met")
                    resultRow(color: DayTier.semiGrace.color, name: "Semi-grace", detail: "Something met")
                } header: {
                    Text("Day results")
                } footer: {
                    Text("Food targets and goals marked ‘Counts toward day result’ are evaluated together. A day where nothing was met earns no medal.")
                }

                if didDismissHint {
                    Section {
                        Button("Show Tips Again") {
                            didDismissHint = false
                            dismiss()
                        }
                    } footer: {
                        Text("Brings back the tips card on the Log tab.")
                    }
                }

                Section {
                    Button("Erase All Data", role: .destructive) {
                        confirmErase = true
                    }
                } footer: {
                    Text("Deletes every entry, column, daily goal and target — from this device and your iCloud.")
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

    private func resultRow(color: Color, name: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
