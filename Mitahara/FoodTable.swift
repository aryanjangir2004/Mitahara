import SwiftUI

/// One editable cell of the table, used as the keyboard focus value.
struct TableCell: Hashable {
    var row: UUID
    var column: UUID
}

/// The editable, user-defined table. Each column header is a menu (target,
/// edit, center, move, delete). The Edit button (bottom right) reveals
/// delete buttons on the rows plus the add/arrange column controls.
/// Focus lives in HomeView, which hosts the keyboard bar and the
/// previous/next/new-entry navigation.
struct FoodTable: View {
    @EnvironmentObject private var store: Store
    let date: Date
    var focusedCell: FocusState<TableCell?>.Binding
    let onAddEntry: () -> Void
    let onNextCell: () -> Void
    let onEditColumn: (ColumnDef) -> Void
    let onEditTarget: (ColumnDef) -> Void
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
    @State private var columnPendingDeletion: ColumnDef?
    @AppStorage("cheatOverlayDismissedDay") private var cheatOverlayDismissedDay = ""

    /// Every column has the same floor width and the same gap between columns;
    /// beyond that, a column grows to fit its widest content.
    private let minColumnWidth: CGFloat = 64
    private let columnGap: CGFloat = 18
    private let numberCellWidth: CGFloat = 30

    private var rows: [EntryRow] { store.rows(on: date) }
    private var columns: [ColumnDef] { store.data.columns }

    private func naturalWidth(for column: ColumnDef) -> CGFloat {
        let headerFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let cellFont = UIFont.systemFont(ofSize: 15)
        // Header text plus its adornments (color dot + chevron).
        var maxWidth = (column.name as NSString)
            .size(withAttributes: [.font: headerFont]).width + 30
        for row in rows {
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
        guard availableWidth > 0, !columns.isEmpty else { return 0 }
        var natural = columnGap + numberCellWidth + columnGap
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
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
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
                    .onChange(of: focusedCell.wrappedValue) { _, cell in
                        guard let cell else { return }
                        // Bring an off-screen column into view in wide tables.
                        withAnimation(.snappy) {
                            proxy.scrollTo(cell, anchor: nil)
                        }
                    }
                }

                if rows.isEmpty {
                    emptyHint
                }

                addRowButton
            }
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .onChange(of: focusedCell.wrappedValue) { _, cell in
                guard let cell else { return }
                // Wait for the keyboard animation before repositioning. Runs
                // on every cell change: a text↔number hop swaps keyboards.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard focusedCell.wrappedValue == cell,
                          let frame = rowFrames.frames[cell.row] else { return }
                    onRowFocused(frame)
                }
            }

            bottomBar
        }
        .confirmationDialog(
            "Delete \"\(columnPendingDeletion?.name ?? "")\"? All its values will be removed.",
            isPresented: Binding(
                get: { columnPendingDeletion != nil },
                set: { if !$0 { columnPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Column", role: .destructive) {
                if let column = columnPendingDeletion {
                    withAnimation(.snappy) {
                        store.deleteColumn(column.id)
                    }
                }
                columnPendingDeletion = nil
            }
        }
        .onChange(of: date) { _, _ in
            focusedCell.wrappedValue = nil
            isEditing = false
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if isEditing {
                pillButton("Column", systemImage: "plus", action: onAddColumn)
                    .accessibilityLabel("Add column")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                Button(action: onArrange) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Arrange columns")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
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
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer()

            Button {
                focusedCell.wrappedValue = nil
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

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .buttonStyle(.glass)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(.tertiary)
                .frame(width: numberCellWidth)
                .padding(.vertical, 12)
                .padding(.leading, columnGap)
                .opacity(isEditing ? 0 : 1)

            ForEach(columns) { column in
                Menu {
                    headerMenu(for: column)
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
                // Keep the first item (the target) nearest the finger and
                // the destructive one farthest, whichever way it opens.
                .menuOrder(.priority)
                .accessibilityLabel("\(column.name) column")
                .accessibilityHint("Shows column options")
            }
        }
        .padding(.trailing, columnGap)
    }

    @ViewBuilder
    private func headerMenu(for column: ColumnDef) -> some View {
        let index = columns.firstIndex { $0.id == column.id } ?? 0

        if column.type == .number {
            Section(column.hasGoal ? "Target: \(column.goalText)" : "No target yet") {
                Button {
                    onEditTarget(column)
                } label: {
                    Label(column.hasGoal ? "Change Target" : "Set Target", systemImage: "target")
                }
                if store.centerColumn?.id != column.id {
                    Button {
                        withAnimation(.snappy) {
                            store.data.centerColumnID = column.id
                        }
                    } label: {
                        Label("Show in Center", systemImage: "circle.circle")
                    }
                }
            }
        }

        Button {
            onEditColumn(column)
        } label: {
            Label("Rename, Color & Type", systemImage: "pencil")
        }

        Section {
            Button {
                withAnimation(.snappy) { store.moveColumn(column.id, by: -1) }
            } label: {
                Label("Move Left", systemImage: "arrow.left")
            }
            .disabled(index == 0)

            Button {
                withAnimation(.snappy) { store.moveColumn(column.id, by: 1) }
            } label: {
                Label("Move Right", systemImage: "arrow.right")
            }
            .disabled(index == columns.count - 1)
        }

        Button(role: .destructive) {
            columnPendingDeletion = column
        } label: {
            Label("Delete Column", systemImage: "trash")
        }
    }

    // MARK: - Rows

    private func entryRow(_ row: EntryRow, number: Int) -> some View {
        HStack(spacing: 0) {
            ZStack {
                if isEditing {
                    Button {
                        if focusedCell.wrappedValue?.row == row.id { focusedCell.wrappedValue = nil }
                        withAnimation(.snappy) {
                            store.deleteRow(row.id, on: date)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                            .frame(width: numberCellWidth, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete entry \(number)")
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else {
                    Text("\(number)")
                        .font(.system(.footnote, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .frame(width: numberCellWidth)
            .padding(.leading, columnGap)

            ForEach(columns) { column in
                cell(row: row, column: column)
            }
        }
        .padding(.trailing, columnGap)
    }

    private func cell(row: EntryRow, column: ColumnDef) -> some View {
        let id = TableCell(row: row.id, column: column.id)
        return TextField(
            column.type == .text ? "Food" : "0",
            text: Binding(
                get: { store.value(rowID: row.id, columnID: column.id, on: date) },
                set: { store.setValue($0, rowID: row.id, columnID: column.id, on: date) }
            )
        )
        .font(.system(.subheadline, design: .rounded))
        .keyboardType(column.type == .number ? .decimalPad : .default)
        .submitLabel(.next)
        .onSubmit(onNextCell)
        .foregroundStyle(.white)
        .focused(focusedCell, equals: id)
        .frame(width: width(for: column), alignment: .leading)
        .padding(.vertical, 12)
        .padding(.leading, columnGap)
        .id(id)
    }

    private var emptyHint: some View {
        Text("Nothing logged \(Calendar.current.isDateInToday(date) ? "today" : "this day") yet.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
    }

    private var addRowButton: some View {
        Button {
            if isEditing {
                withAnimation(.snappy) { isEditing = false }
            }
            onAddEntry()
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
