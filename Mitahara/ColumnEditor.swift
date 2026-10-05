import SwiftUI

struct ColumnEditorTarget: Identifiable {
    var column: ColumnDef
    var isNew: Bool
    /// Opened to change the daily target (from a totals chip, a header menu
    /// or the Goals tab): the min/max fields get focus right away.
    var focusTarget = false
    var id: UUID { column.id }

    static func target(for column: ColumnDef) -> ColumnEditorTarget {
        ColumnEditorTarget(column: column, isNew: false, focusTarget: true)
    }
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
    @FocusState private var focusedField: Field?
    /// Pre-selects the current value when the editor opens on a target, so
    /// typing replaces "2000" instead of appending to it.
    @State private var minSelection: TextSelection?
    @State private var maxSelection: TextSelection?

    private enum Field: Hashable {
        case name, min, max
    }

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

    private var rangeInvalid: Bool {
        if type == .number, let lo = parse(minText), let hi = parse(maxText) {
            return lo > hi
        }
        return false
    }

    private var goalSummary: String {
        let lo = parse(minText)
        let hi = parse(maxText)
        switch (lo, hi) {
        case (nil, nil):
            return "No target — leave both empty to just track this column."
        case let (lo?, nil):
            return "Reach at least \(lo.compactString) a day."
        case let (nil, hi?):
            return "Stay at or under \(hi.compactString) a day."
        case let (lo?, hi?):
            return "Land between \(lo.compactString) and \(hi.compactString) a day."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Opened to change the target: put it first, above the
                // name/type fields the user didn't come here for.
                if target.focusTarget && type == .number {
                    goalSection
                    columnSection
                } else {
                    columnSection
                    if type == .number {
                        goalSection
                    }
                }

                if type == .number {
                    colorSection
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
            .navigationTitle(target.isNew ? "New Column" : (target.focusTarget ? "\(target.column.name) Target" : "Edit Column"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || rangeInvalid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .fontWeight(.semibold)
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
            .onAppear {
                if target.isNew {
                    focusedField = .name
                } else if target.focusTarget, type == .number {
                    // Land on the bound the user is most likely to adjust.
                    let field: Field = (minText.isEmpty && !maxText.isEmpty) ? .max : .min
                    focusedField = field
                    Task { @MainActor in
                        // After the sheet settles: selecting earlier gets
                        // undone when the field places its cursor.
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        switch field {
                        case .min: minSelection = TextSelection(range: minText.startIndex..<minText.endIndex)
                        case .max: maxSelection = TextSelection(range: maxText.startIndex..<maxText.endIndex)
                        case .name: break
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var columnSection: some View {
        Section("Column") {
            TextField("Name (e.g. Kcal, Protein)", text: $name)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
            Picker("Type", selection: $type) {
                ForEach(ColumnType.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var goalSection: some View {
        Section {
            goalField("Min", caption: "at least", text: $minText, selection: $minSelection, field: .min)
            goalField("Max", caption: "at most", text: $maxText, selection: $maxSelection, field: .max)
            Toggle("Counts toward day result", isOn: $countsTowardSuccess)
        } header: {
            Text("Daily target")
        } footer: {
            if rangeInvalid {
                Text("Min can't be larger than Max.")
                    .foregroundStyle(.red)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(countsTowardSuccess
                         ? goalSummary
                         : "Just tracking — this column shows its ring and totals but never affects the day's medal or your streak.")
                    if goalChanged {
                        Text("New targets apply from today. Past days keep the target they had.")
                    }
                }
            }
        }
    }

    private var colorSection: some View {
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

    private var goalChanged: Bool {
        !target.isNew && (parse(minText) != target.column.minGoal || parse(maxText) != target.column.maxGoal)
    }

    private func goalField(
        _ title: String,
        caption: String,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        field: Field
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("none", text: text, selection: selection)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .focused($focusedField, equals: field)
                .frame(width: 130)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .contentShape(.rect)
        .onTapGesture { focusedField = field }
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
