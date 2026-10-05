import SwiftUI

struct CalendarCard: View {
    @EnvironmentObject private var store: Store
    @Binding var selectedDate: Date

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())

    private var cal: Calendar { Calendar.current }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var dayCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstDay = interval.start
        let numDays = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        let weekday = cal.component(.weekday, from: firstDay)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<numDays {
            cells.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        return cells
    }

    var body: some View {
        let streak = store.streakInfo()
        VStack(spacing: 14) {
            HStack {
                Button {
                    withAnimation(.snappy) {
                        displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth)!
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Previous month")

                Spacer()
                Text(monthTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()

                Button {
                    withAnimation(.snappy) {
                        displayedMonth = cal.date(byAdding: .month, value: 1, to: displayedMonth)!
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Next month")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 3) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, streak: streak)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                alignment: .leading,
                spacing: 7
            ) {
                legend(color: DayTier.gold.color, text: "Gold")
                legend(color: DayTier.silver.color, text: "Silver")
                legend(color: DayTier.bronze.color, text: "Bronze")
                legend(color: DayTier.semiGrace.color, text: "Semi")
                legend(color: .dayGrace, text: "Grace")
                legend(color: .orange, text: "Cheat")
                legend(color: .white.opacity(0.25), text: "Missed")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .onAppear {
            displayedMonth = selectedDate
        }
        .onChange(of: selectedDate) { _, newDate in
            guard !cal.isDate(newDate, equalTo: displayedMonth, toGranularity: .month) else { return }
            displayedMonth = newDate
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date, streak: Store.StreakInfo) -> some View {
        let dayKey = store.key(for: day)
        let assessment = store.dayAssessment(on: day)
        let isCheat = store.isCheatDay(day)
        let isGrace = streak.graceDays.contains(dayKey)
        let isToday = cal.isDateInToday(day)
        let isSemiGrace = streak.semiGraceDays.contains(dayKey)
            || (isToday && assessment.tier == .semiGrace)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let isFuture = day > Date()
        let fillColor: Color? = {
            guard !isFuture else { return nil }
            if isCheat { return .orange }
            if assessment.tier.countsAsSuccess { return assessment.tier.color }
            if isGrace { return .dayGrace }
            if isSemiGrace { return DayTier.semiGrace.color }
            if assessment.tier == .missed || assessment.tier == .semiGrace {
                return Color.white.opacity(0.18)
            }
            return nil
        }()
        let usesDarkText = assessment.tier.countsAsSuccess || isCheat || isGrace || isSemiGrace

        Button {
            withAnimation(.snappy) { selectedDate = day }
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(.footnote, design: .rounded).weight(fillColor == nil ? .regular : .bold))
                .monospacedDigit()
                .foregroundStyle(isFuture ? Color.white.opacity(0.2) : (usesDarkText ? .black : .white))
                .frame(width: 44, height: 44)
                .background {
                    if let fillColor {
                        Circle().fill(fillColor.gradient)
                    } else if isSelected {
                        Circle().fill(Color.white.opacity(0.12))
                    }
                }
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.white, lineWidth: 2.5)
                    } else if isToday {
                        Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(dayStatus(
            assessment: assessment,
            isCheat: isCheat,
            isGrace: isGrace,
            isSemiGrace: isSemiGrace,
            isFuture: isFuture
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayStatus(
        assessment: DayAssessment,
        isCheat: Bool,
        isGrace: Bool,
        isSemiGrace: Bool,
        isFuture: Bool
    ) -> String {
        if isFuture { return "Future date" }
        if isCheat { return "Cheat day" }
        if isGrace { return "Grace day" }
        if isSemiGrace { return "Semi-grace day" }
        switch assessment.tier {
        case .gold: return "Gold day"
        case .silver: return "Silver day"
        case .bronze: return "Bronze day"
        case .semiGrace, .missed: return "Missed day"
        case .unrated: return "No result"
        }
    }
}
