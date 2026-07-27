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
        let graceDays = store.graceDaysPerMonth > 0 ? store.streakInfo().graceDays : []
        VStack(spacing: 14) {
            HStack {
                Button {
                    withAnimation(.snappy) {
                        displayedMonth = cal.date(byAdding: .month, value: -1, to: displayedMonth)!
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)

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
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, graceDays: graceDays)
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }

            HStack(spacing: 14) {
                legend(color: .green, text: "Goal hit")
                if store.graceDaysPerMonth > 0 || !store.cheatDaySet.isEmpty {
                    legend(color: .orange, text: "Grace")
                }
                legend(color: .white.opacity(0.25), text: "Missed")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date, graceDays: Set<String>) -> some View {
        let success = store.isDaySuccessful(day)
        let isGrace = !success && (graceDays.contains(store.key(for: day)) || store.isCheatDay(day))
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
        let isFuture = day > Date()

        Button {
            withAnimation(.snappy) { selectedDate = day }
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(.footnote, design: .rounded).weight(success || isGrace ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isFuture ? Color.white.opacity(0.2) : (success || isGrace ? .black : .white))
                .frame(width: 32, height: 32)
                .background {
                    if success {
                        Circle().fill(Color.green.gradient)
                    } else if isGrace {
                        Circle().fill(Color.orange.gradient)
                    } else if isSelected {
                        Circle().fill(Color.white.opacity(0.12))
                    }
                }
                .overlay {
                    if isToday {
                        Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}
