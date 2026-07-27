import SwiftUI

/// The editable, user-defined table. Column headers are tappable (edit column).
/// The Edit button (bottom right) reveals the editing controls: delete row,
/// add column, and rearrange columns.
struct FoodTable: View {
    @EnvironmentObject private var store: Store
    let date: Date
    let onEditColumn: (ColumnDef) -> Void
    let onAddColumn: () -> Void
    let onArrange: () -> Void
    /// Called (after the keyboard settles) with the focused row's frame in
    /// global coordinates, so the outer scroll can bring it above the keyboard.
    let onRowFocused: (CGRect) -> Void

    /// Row frames in global space. A reference type on purpose: geometry
    /// updates mutate it without invalidating the view.
    private final class RowFrameCache {
        var frames: [UUID: CGRect] = [:]
    }

    @State private var isEditing = false
    @State private var availableWidth: CGFloat = 0
    @State private var rowFrames = RowFrameCache()
    @FocusState private var focusedRowID: UUID?
    @AppStorage("cheatOverlayDismissedDay") private var cheatOverlayDismissedDay = ""

    /// Every column has the same floor width and the same gap between columns;
    /// beyond that, a column grows to fit its widest content.
    private let minColumnWidth: CGFloat = 64
    private let columnGap: CGFloat = 18
    private let numberCellWidth: CGFloat = 30
    /// Width reserved for the add/arrange header buttons while editing.
    private let editControlsWidth: CGFloat = 96

    private func naturalWidth(for column: ColumnDef) -> CGFloat {
        let headerFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let cellFont = UIFont.systemFont(ofSize: 15)
        // Header text plus its adornments (color dot + chevron).
        var maxWidth = (column.name as NSString)
            .size(withAttributes: [.font: headerFont]).width + 30
        for row in store.rows(on: date) {
            let value = row.values[column.id] ?? ""
            guard !value.isEmpty else { continue }
            let w = (value as NSString).size(withAttributes: [.font: cellFont]).width
            maxWidth = max(maxWidth, w)
        }
        return max(minColumnWidth, ceil(maxWidth) + 6)
    }

    /// Leftover card width shared equally between columns so the table
    /// justifies edge to edge; zero once content needs to scroll.
    private var extraPerColumn: CGFloat {
        let columns = store.data.columns
        guard availableWidth > 0, !columns.isEmpty else { return 0 }
        var natural = columnGap + numberCellWidth + columnGap
        if isEditing { natural += editControlsWidth }
        for column in columns {
            natural += columnGap + naturalWidth(for: column)
        }
        return max(0, (availableWidth - natural) / CGFloat(columns.count))
    }

    private func width(for column: ColumnDef) -> CGFloat {
        naturalWidth(for: column) + extraPerColumn
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            headerRow
                            Divider().overlay(Color.white.opacity(0.15))
                            ForEach(Array(store.rows(on: date).enumerated()), id: \.element.id) { index, row in
                                entryRow(row, number: index + 1)
                                    .id(row.id)
                                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                                        rowFrames.frames[row.id] = frame
                                    }
                                Divider().overlay(Color.white.opacity(0.07))
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                        availableWidth = width
                    }
                    .onChange(of: isEditing) { _, editing in
                        guard editing else { return }
                        // Let the controls appear first, then slide them into view.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            withAnimation(.snappy) {
                                proxy.scrollTo("editControls", anchor: .trailing)
                            }
                        }
                    }
                }

                addRowButton
            }
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .onChange(of: focusedRowID) { _, newValue in
                guard let newValue else { return }
                // Wait for the keyboard animation before repositioning.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard focusedRowID == newValue,
                          let frame = rowFrames.frames[newValue] else { return }
                    onRowFocused(frame)
                }
            }

            HStack {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        if !store.isCheatDay(date) {
                            // Re-marking should show the takeover again.
                            cheatOverlayDismissedDay = ""
                        }
                        store.toggleCheatDay(date)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.isCheatDay(date) ? "star.fill" : "star")
                            .font(.caption.weight(.bold))
                        Text("Cheat day")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .tint(store.isCheatDay(date) ? .orange : nil)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        isEditing.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isEditing ? "checkmark" : "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.glass)
                .tint(isEditing ? .orange : nil)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: numberCellWidth)
                .padding(.vertical, 12)
                .padding(.leading, columnGap)

            ForEach(store.data.columns) { column in
                Button {
                    onEditColumn(column)
                } label: {
                    HStack(spacing: 5) {
                        if column.type == .number {
                            Circle()
                                .fill(column.color)
                                .frame(width: 7, height: 7)
                        }
                        Text(column.name)
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: width(for: column), alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.leading, columnGap)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                HStack(spacing: 8) {
                    Button(action: onAddColumn) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)

                    Button(action: onArrange) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.footnote.weight(.bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .id("editControls")
            }
        }
        .padding(.trailing, columnGap)
    }

    private func entryRow(_ row: EntryRow, number: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(number)")
                .font(.system(.footnote, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: numberCellWidth)
                .padding(.leading, columnGap)

            ForEach(store.data.columns) { column in
                cell(row: row, column: column)
            }

            if isEditing {
                Button {
                    withAnimation(.snappy) {
                        store.deleteRow(row.id, on: date)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6), .red.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.trailing, columnGap)
    }

    private func cell(row: EntryRow, column: ColumnDef) -> some View {
        TextField(
            column.type == .text ? "Food" : "0",
            text: Binding(
                get: { store.value(rowID: row.id, columnID: column.id, on: date) },
                set: { store.setValue($0, rowID: row.id, columnID: column.id, on: date) }
            )
        )
        .font(.system(.subheadline, design: .rounded))
        .keyboardType(column.type == .number ? .decimalPad : .default)
        .foregroundStyle(.white)
        .focused($focusedRowID, equals: row.id)
        .frame(width: width(for: column), alignment: .leading)
        .padding(.vertical, 12)
        .padding(.leading, columnGap)
    }

    private var addRowButton: some View {
        Button {
            withAnimation(.snappy) {
                store.addRow(on: date)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Add entry")
            }
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
