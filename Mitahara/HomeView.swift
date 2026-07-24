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
    @AppStorage("didDismissHint") private var didDismissHint = false
    @Environment(\.scenePhase) private var scenePhase

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

                    RingGauge(
                        columns: ringColumns,
                        totals: totals,
                        centerColumn: store.centerColumn?.resolved(on: store.key(for: selectedDate)),
                        animateIn: appeared
                    )
                    .frame(height: 190)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .entrance(appeared, index: 2)

                    TotalsRow(date: selectedDate)
                        .entrance(appeared, index: 3)

                    if !didDismissHint {
                        hintCard
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    FoodTable(
                        date: selectedDate,
                        onEditColumn: { editorTarget = ColumnEditorTarget(column: $0, isNew: false) },
                        onAddColumn: {
                            editorTarget = ColumnEditorTarget(
                                column: ColumnDef(name: "", type: .number, colorHex: nextColorHex()),
                                isNew: true
                            )
                        },
                        onArrange: { showArrange = true }
                    )
                    .padding(.horizontal, 16)
                    .entrance(appeared, index: 4)

                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
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
                Text("Tap a column header to set its goal and ring color. Edit under the table adds and rearranges columns. Tap a total chip to change the center number.")
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

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    showCalendar.toggle()
                }
            } label: {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)

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

    private var streakBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)
                )
            Text("\(store.currentStreak())")
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .capsule)
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

            Text(dateLabel)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 110)
                .contentTransition(.numericText())

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
