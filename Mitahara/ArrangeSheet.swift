import SwiftUI

/// Drag-to-reorder for columns. The column order drives everything:
/// ring order (outermost first), the totals chips, and the table.
struct ArrangeColumnsSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.data.columns) { column in
                        HStack(spacing: 12) {
                            if column.type == .number {
                                Circle()
                                    .fill(column.color)
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: "textformat")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 10)
                            }
                            Text(column.name)
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Spacer()
                            Text(column.type == .number ? column.goalText : "text")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onMove { source, destination in
                        store.data.columns.move(fromOffsets: source, toOffset: destination)
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                } footer: {
                    Text("Drag to reorder. Rings, totals, the table and widgets all follow this order — the first number column is the outermost ring.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
