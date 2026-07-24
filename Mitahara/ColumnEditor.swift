import SwiftUI

struct ColumnEditorTarget: Identifiable {
    var column: ColumnDef
    var isNew: Bool
    var id: UUID { column.id }
}

struct ColumnEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let target: ColumnEditorTarget

    @State private var name: String
    @State private var type: ColumnType
    @State private var minText: String
    @State private var maxText: String
    @State private var colorHex: String
    @State private var countsTowardSuccess: Bool
    @State private var confirmDelete = false

    init(target: ColumnEditorTarget) {
        self.target = target
        _name = State(initialValue: target.column.name)
        _type = State(initialValue: target.column.type)
        _minText = State(initialValue: target.column.minGoal.map(\.compactString) ?? "")
        _maxText = State(initialValue: target.column.maxGoal.map(\.compactString) ?? "")
        _colorHex = State(initialValue: target.column.colorHex)
        _countsTowardSuccess = State(initialValue: target.column.countsInSuccess)
    }

    private func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var goalSummary: String {
        let lo = parse(minText)
        let hi = parse(maxText)
        switch (lo, hi) {
        case (nil, nil):
            return "No goal — this column is just tracked, it won't affect your streak."
        case let (lo?, nil):
            return "Goal: eat at least \(lo.compactString) to succeed."
        case let (nil, hi?):
            return "Goal: stay at or under \(hi.compactString) to succeed."
        case let (lo?, hi?):
            return "Goal: land between \(lo.compactString) and \(hi.compactString) to succeed."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Column") {
                    TextField("Name (e.g. Kcal, Protein)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(ColumnType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if type == .number {
                    Section {
                        HStack {
                            Text("Min")
                            Spacer()
                            TextField("optional", text: $minText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                        HStack {
                            Text("Max")
                            Spacer()
                            TextField("optional", text: $maxText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                        Toggle("Counts toward successful day", isOn: $countsTowardSuccess)
                    } header: {
                        Text("Daily goal")
                    } footer: {
                        Text(countsTowardSuccess
                             ? goalSummary
                             : "Just tracking — this column shows its ring and totals but never affects your streak or calendar, on any day.")
                    }

                    Section("Ring color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                            ForEach(RingPalette.hexes, id: \.self) { hex in
                                Button {
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 36, height: 36)
                                        .overlay {
                                            if colorHex == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.black))
                                                    .foregroundStyle(.black)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                if !target.isNew {
                    Section {
                        Button("Delete column", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(target.isNew ? "New Column" : "Edit Column")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(target.column.name)\"? All its values will be removed.",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.deleteColumn(target.column.id)
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        var column = target.column
        column.name = name.trimmingCharacters(in: .whitespaces)
        column.type = type
        column.minGoal = type == .number ? parse(minText) : nil
        column.maxGoal = type == .number ? parse(maxText) : nil
        column.colorHex = colorHex
        column.countsTowardSuccess = countsTowardSuccess
        if target.isNew {
            store.addColumn(column)
        } else {
            store.updateColumn(column)
        }
        dismiss()
    }
}
