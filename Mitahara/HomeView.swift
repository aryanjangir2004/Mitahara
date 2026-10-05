import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var trackedToday = Calendar.current.startOfDay(for: Date())
    @State private var showCalendar = false
    @State private var editorTarget: ColumnEditorTarget?
    @State private var showArrange = false
    @State private var showSettings = false
    @State private var appeared = false
    /// Extra scroll room while the keyboard is up, so even the last row of
    /// a short table can be lifted above it.
    @State private var keyboardInset: CGFloat = 0
    @FocusState private var focusedCell: TableCell?
    private let keyboardBarHeight: CGFloat = 52
    @AppStorage("didDismissHint") private var didDismissHint = false
    @AppStorage("cheatOverlayDismissedDay") private var cheatOverlayDismissedDay = ""
    @AppStorage("selectedMainTab") private var selectedTab = "log"
    @Environment(\.scenePhase) private var scenePhase

    /// The takeover only applies to today — browsing past cheat days just
    /// shows the label.
    private var showCheatOverlay: Bool {
        cal.isDateInToday(selectedDate)
            && store.isCheatDay(selectedDate)
            && cheatOverlayDismissedDay != store.key(for: selectedDate)
    }

    /// Live scroll offset, kept in a reference type so per-frame updates
    /// don't re-render the view.
    private final class ScrollOffsetBox {
        var y: CGFloat = 0
    }

    @State private var scrollPosition = ScrollPosition()
    @State private var scrollOffset = ScrollOffsetBox()

    private var cal: Calendar { Calendar.current }

    private var ringColumns: [ColumnDef] {
        let dayKey = store.key(for: selectedDate)
        return store.numericColumns
            .map { $0.resolved(on: dayKey) }
            .filter { $0.ringTarget != nil }
    }

    private var totals: [UUID: Double] {
        var result: [UUID: Double] = [:]
        for column in store.numericColumns {
            result[column.id] = store.total(of: column, on: selectedDate)
        }
        return result
    }

    private var dateLabel: String {
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    topBar
                        .entrance(appeared, index: 0)

                    if showCalendar {
                        CalendarCard(selectedDate: $selectedDate)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }

                    dateBar
                        .entrance(appeared, index: 1)

                    if showCheatOverlay {
                        CheatDayContent(
                            onContinue: {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                    cheatOverlayDismissedDay = store.key(for: selectedDate)
                                }
                            },
                            onCancel: {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                    store.toggleCheatDay(selectedDate)
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        VStack(spacing: 18) {
                            RingGauge(
                                columns: ringColumns,
                                totals: totals,
                                centerColumn: store.centerColumn?.resolved(on: store.key(for: selectedDate)),
                                animateIn: appeared,
                                centerChoices: store.numericColumns.count,
                                centerIndex: store.numericColumns.firstIndex { $0.id == store.centerColumn?.id } ?? 0
                            )
                            .frame(height: 190)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .contentShape(.rect)
                            .onTapGesture { cycleCenterColumn() }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint(store.numericColumns.count > 1 ? "Shows the next column's total" : "")
                            .entrance(appeared, index: 2)

                            TotalsRow(date: selectedDate, onEditTarget: { editorTarget = .target(for: $0) })
                                .entrance(appeared, index: 3)

                            if !didDismissHint {
                                hintCard
                                    .padding(.horizontal, 16)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }

                            FoodTable(
                                date: selectedDate,
                                focusedCell: $focusedCell,
                                onAddEntry: startNewEntry,
                                onNextCell: { moveFocus(by: 1) },
                                onEditColumn: { editorTarget = ColumnEditorTarget(column: $0, isNew: false) },
                                onEditTarget: { editorTarget = .target(for: $0) },
                                onAddColumn: addColumn,
                                onArrange: { showArrange = true },
                                onRowFocused: { frame in
                                    guard let keyboardTop = KeyboardScroller.shared.currentKeyboardTop else { return }
                                    // 24pt breathing room plus the keyboard bar above the keys.
                                    let delta = frame.maxY + 24 + keyboardBarHeight - keyboardTop
                                    guard delta > 0 else { return }
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        scrollPosition.scrollTo(y: scrollOffset.y + delta)
                                    }
                                }
                            )
                            .padding(.horizontal, 16)
                            .entrance(appeared, index: 4)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    Spacer(minLength: 40 + (keyboardInset > 0 ? keyboardInset + keyboardBarHeight : 0))
                }
                .padding(.top, 8)
            }
            .scrollPosition($scrollPosition)
            // Measured from the content's top edge (not the inset-adjusted
            // offset), matching what ScrollPosition.scrollTo(y:) expects.
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, new in
                scrollOffset.y = new
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .statusBarScrim()
        // A hand-rolled keyboard bar: SwiftUI's keyboard toolbar vanishes
        // when focus hops between a text cell and a number cell (the
        // keyboard is torn down and rebuilt), so it can't be relied on.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedCell != nil {
                keyboardBar
                    .transition(.opacity)
            }
        }
        .sheet(item: $editorTarget) { target in
            ColumnEditor(target: target)
                .environmentObject(store)
        }
        .sheet(isPresented: $showArrange) {
            ArrangeColumnsSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: focusedCell) { old, new in
            // An entry abandoned without typing anything shouldn't linger.
            guard new == nil, let old else { return }
            let day = selectedDate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard focusedCell == nil,
                      store.rows(on: day).first(where: { $0.id == old.row })?.isBlank == true else { return }
                withAnimation(.snappy) {
                    store.deleteRow(old.row, on: day)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardInset = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            // Moving between a text and a number cell hides and re-shows the
            // keyboard; dropping the inset in between would yank the page down.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if KeyboardScroller.shared.currentKeyboardTop == nil {
                    keyboardInset = 0
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                appeared = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            handleDayChange()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                handleDayChange()
            }
        }
    }

    /// Snaps the view to the new day at midnight (or on return from
    /// background) — but only if the user was already viewing "today",
    /// so browsing a past day is never interrupted.
    private func handleDayChange() {
        let newToday = cal.startOfDay(for: Date())
        guard newToday != trackedToday else { return }
        if cal.isDate(selectedDate, inSameDayAs: trackedToday) {
            withAnimation(.snappy) {
                selectedDate = newToday
            }
        }
        trackedToday = newToday
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text("Make it yours")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text("Tap a total to set its daily target. Tap the big number to switch what it shows. Column headers have options for renaming, colors and order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) {
                    didDismissHint = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassEffect(.regular.tint(.yellow.opacity(0.06)), in: .rect(cornerRadius: 20))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("Krec")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Spacer()

            streakBadge

            medalChip

            Button(action: toggleCalendar) {
                Image(systemName: showCalendar ? "calendar.badge.checkmark" : "calendar")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(showCalendar ? "Hide calendar" : "Show calendar")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Table focus

    private var keyboardBar: some View {
        HStack {
            HStack(spacing: 0) {
                Button {
                    moveFocus(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 46, height: 40)
                        .contentShape(.rect)
                }
                .disabled(!canMoveFocusBack)
                .opacity(canMoveFocusBack ? 1 : 0.35)
                .accessibilityLabel("Previous field")

                Button {
                    moveFocus(by: 1)
                } label: {
                    Image(systemName: isOnLastCell ? "plus" : "chevron.right")
                        .frame(width: 46, height: 40)
                        .contentShape(.rect)
                }
                .accessibilityLabel(isOnLastCell ? "New entry" : "Next field")
            }
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            Button {
                focusedCell = nil
            } label: {
                Text("Done")
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .contentShape(.capsule)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .font(.body.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Fade the page out behind the bar so content under the glass
        // doesn't muddle the buttons.
        .background {
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black, location: 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -10)
        }
    }

    /// Every table cell in reading order: left to right, then down.
    private var cellOrder: [TableCell] {
        store.rows(on: selectedDate).flatMap { row in
            store.data.columns.map { TableCell(row: row.id, column: $0.id) }
        }
    }

    private var canMoveFocusBack: Bool {
        guard let focusedCell else { return false }
        return focusedCell != cellOrder.first
    }

    private var isOnLastCell: Bool {
        guard let focusedCell else { return false }
        return focusedCell == cellOrder.last
    }

    /// Steps the cursor through the table; stepping past the last cell
    /// starts a new entry, so logging a meal never needs a reach for the
    /// "Add entry" button.
    private func moveFocus(by step: Int) {
        let order = cellOrder
        guard let current = focusedCell, let index = order.firstIndex(of: current) else { return }
        let next = index + step
        if order.indices.contains(next) {
            focusedCell = order[next]
        } else if step > 0 {
            startNewEntry()
        }
    }

    /// Adds (or reuses a trailing blank) row and puts the cursor in it.
    private func startNewEntry() {
        guard let firstColumn = store.data.columns.first else { return }
        let rowID = withAnimation(.snappy) { store.rowForNewEntry(on: selectedDate) }
        // Give the new row a moment to exist before focusing it.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            focusedCell = TableCell(row: rowID, column: firstColumn.id)
        }
    }

    private func toggleCalendar() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showCalendar.toggle()
        }
    }

    private func addColumn() {
        editorTarget = ColumnEditorTarget(
            column: ColumnDef(name: "", type: .number, colorHex: nextColorHex()),
            isNew: true
        )
    }

    /// Tapping the gauge steps its big number through the number columns.
    private func cycleCenterColumn() {
        let columns = store.numericColumns
        guard !columns.isEmpty else {
            addColumn()
            return
        }
        guard columns.count > 1 else { return }
        let index = columns.firstIndex { $0.id == store.centerColumn?.id } ?? 0
        withAnimation(.snappy) {
            store.data.centerColumnID = columns[(index + 1) % columns.count].id
        }
    }

    private var streakBadge: some View {
        Button(action: toggleCalendar) {
            streakBadgeLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.currentStreak()) day streak")
        .accessibilityHint("Shows the calendar")
    }

    private var streakBadgeLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                )
            Text("\(store.currentStreak())")
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .fixedSize()
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.orange.opacity(0.15)).interactive(), in: .capsule)
    }

    /// Today's medal and how many requirements are met so far; taps
    /// through to the Goals tab, where the full verdict lives. While the
    /// day is still running an unmet day reads as neutral progress rather
    /// than a red "missed".
    private var medalChip: some View {
        let isCheat = store.isCheatDay(trackedToday)
        let assessment = store.dayAssessment(on: trackedToday)
        let earned = assessment.tier.countsAsSuccess

        return Button {
            selectedTab = "goals"
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isCheat ? "star.fill" : (earned ? assessment.tier.symbol : "medal"))
                    .foregroundStyle(isCheat ? .orange : (earned ? assessment.tier.color : .secondary))
                if !isCheat, assessment.total > 0 {
                    Text("\(assessment.met)/\(assessment.total)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .fixedSize()
            .font(.body.weight(.semibold))
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, assessment.total > 0 && !isCheat ? 4 : 0)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(isCheat
            ? "Cheat day. Open goals."
            : "Today: \(assessment.met) of \(assessment.total) requirements met. Open goals.")
    }

    // MARK: - Date bar

    private var dateBar: some View {
        HStack(spacing: 14) {
            Button {
                shiftDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)

            VStack(spacing: 3) {
                Button(action: toggleCalendar) {
                    HStack(spacing: 4) {
                        Text(dateLabel)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showCalendar ? 180 : 0))
                    }
                    .frame(minHeight: 32)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(showCalendar ? "Hides the calendar" : "Shows the calendar")

                if store.isCheatDay(selectedDate) || !cal.isDateInToday(selectedDate) {
                    HStack(spacing: 10) {
                        if store.isCheatDay(selectedDate) {
                            Text("Cheat day")
                                .foregroundStyle(.orange)
                        }
                        // Browsing another day: one tap back to today.
                        if !cal.isDateInToday(selectedDate) {
                            Button {
                                withAnimation(.snappy) {
                                    selectedDate = cal.startOfDay(for: Date())
                                }
                            } label: {
                                Label("Back to today", systemImage: "arrow.uturn.forward")
                                    .foregroundStyle(.orange)
                                    .padding(.vertical, 4)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(minWidth: 110)

            Button {
                shiftDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .disabled(cal.isDateInToday(selectedDate))
            .opacity(cal.isDateInToday(selectedDate) ? 0.3 : 1)
        }
    }

    private func shiftDay(_ delta: Int) {
        withAnimation(.snappy) {
            selectedDate = cal.date(byAdding: .day, value: delta, to: selectedDate)!
        }
    }

    private func nextColorHex() -> String {
        let used = Set(store.data.columns.map(\.colorHex))
        return RingPalette.hexes.first { !used.contains($0) } ?? RingPalette.hexes.randomElement()!
    }
}

// MARK: - Entrance transition helper

private struct EntranceModifier: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 26)
            .animation(
                .spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.08),
                value: appeared
            )
    }
}

private extension View {
    func entrance(_ appeared: Bool, index: Int) -> some View {
        modifier(EntranceModifier(appeared: appeared, index: index))
    }
}
