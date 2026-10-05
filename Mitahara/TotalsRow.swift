import SwiftUI

/// Horizontal strip of per-column totals. Tapping a chip edits that column's
/// daily target; long-press offers "Show in Center" for the ring's big number.
struct TotalsRow: View {
    @EnvironmentObject private var store: Store
    let date: Date
    /// Receives the column as currently defined (not resolved to `date`):
    /// target edits always apply from today.
    let onEditTarget: (ColumnDef) -> Void

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
        // Mirrors dayAssessment: targets only score once the day has any
        // tracked activity, and tracking-only columns show no verdict.
        let met: Bool? = (column.hasGoal && column.countsInSuccess)
            ? (store.hasTrackedActivity(on: date) && column.isMet(total: total) == true)
            : nil
        let isCenter = store.centerColumn?.id == column.id

        Button {
            if let current = store.data.columns.first(where: { $0.id == column.id }) {
                onEditTarget(current)
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
                        if column.hasGoal {
                            Text(column.goalText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text("Set target")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
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
        .contextMenu {
            Button {
                if let current = store.data.columns.first(where: { $0.id == column.id }) {
                    onEditTarget(current)
                }
            } label: {
                Label("Edit Target", systemImage: "target")
            }
            if !isCenter {
                Button {
                    withAnimation(.snappy) {
                        store.data.centerColumnID = column.id
                    }
                } label: {
                    Label("Show in Center", systemImage: "circle.circle")
                }
            }
        }
        .accessibilityHint("Edits the daily target")
    }
}
