import SwiftUI

/// Horizontal strip of per-column totals. Tapping a chip selects which
/// number is displayed in the middle of the rings.
struct TotalsRow: View {
    @EnvironmentObject private var store: Store
    let date: Date

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.numericColumns) { column in
                    chip(for: column.resolved(on: store.key(for: date)))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func chip(for column: ColumnDef) -> some View {
        let total = store.total(of: column, on: date)
        let met = column.isMet(total: total)
        let isCenter = store.centerColumn?.id == column.id

        Button {
            withAnimation(.snappy) {
                store.data.centerColumnID = column.id
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(column.color)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(column.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(total.compactString)
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(column.goalText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let met {
                    Image(systemName: met ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.subheadline)
                        .foregroundStyle(met ? .green : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isCenter ? .regular.tint(column.color.opacity(0.25)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .overlay {
            if isCenter {
                Capsule().strokeBorder(column.color.opacity(0.6), lineWidth: 1)
            }
        }
    }
}
