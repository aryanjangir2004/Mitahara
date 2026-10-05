import SwiftUI

struct GoalsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var trackedToday = Calendar.current.startOfDay(for: Date())
    @State private var showDatePicker = false
    @State private var showGoalEditor = false
    @State private var editingGoal: GoalDefinition?
    @State private var goalPendingDeletion: GoalDefinition?
    @State private var editingColumn: ColumnEditorTarget?
    @State private var appeared = false

    private var calendar: Calendar { Calendar.current }

    private var occurrences: [GoalOccurrence] {
        store.goalOccurrences(on: selectedDate)
    }

    private var assessment: DayAssessment {
        store.dayAssessment(on: selectedDate)
    }

    private var isFutureDay: Bool {
        selectedDate > calendar.startOfDay(for: Date())
    }

    private var isPastDay: Bool {
        selectedDate < calendar.startOfDay(for: Date())
    }

    private var dayTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private var fullDate: String {
        selectedDate.formatted(.dateTime.day().month(.wide).year())
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    topBar
                        .goalEntrance(appeared, index: 0)

                    dateCard
                        .goalEntrance(appeared, index: 1)

                    assessmentCard
                        .goalEntrance(appeared, index: 2)

                    goalsSection
                        .goalEntrance(appeared, index: 3)

                    if !targetColumns.isEmpty {
                        targetsSection
                            .goalEntrance(appeared, index: 4)
                    }

                    Spacer(minLength: 34)
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .statusBarScrim()
        .sheet(isPresented: $showDatePicker) {
            GoalDatePickerSheet(selectedDate: $selectedDate)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showGoalEditor) {
            GoalEditor(defaultDate: selectedDate)
                .environmentObject(store)
                .presentationDetents([.large])
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditor(defaultDate: selectedDate, editing: goal)
                .environmentObject(store)
                .presentationDetents([.large])
        }
        .sheet(item: $editingColumn) { target in
            ColumnEditor(target: target)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Delete \"\(goalPendingDeletion?.title ?? "")\"? It disappears from every day and past medals are re-evaluated.",
            isPresented: Binding(
                get: { goalPendingDeletion != nil },
                set: { if !$0 { goalPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Goal", role: .destructive) {
                if let goal = goalPendingDeletion {
                    withAnimation(.snappy) {
                        store.deleteGoal(goal.id)
                    }
                }
                goalPendingDeletion = nil
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                    appeared = true
                }
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

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Goals")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text("Small promises, kept daily")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showGoalEditor = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.orange)
            .accessibilityLabel("Add goal")
        }
        .padding(.horizontal, 4)
    }

    private var dateCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    shiftDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Previous day")

                Button {
                    showDatePicker = true
                } label: {
                    VStack(spacing: 2) {
                        Text(dayTitle)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                        Text(fullDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the date picker")

                Button {
                    shiftDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Next day")
            }

            HStack(spacing: 6) {
                ForEach(-3...3, id: \.self) { offset in
                    if let date = calendar.date(byAdding: .day, value: offset, to: selectedDate) {
                        dayButton(date)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)

        return Button {
            withAnimation(.snappy) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? Color.black.opacity(0.65) : .secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? .black : .white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.orange.gradient)
                } else if today {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.75), lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var assessmentCard: some View {
        let presentation = resultPresentation
        let progress = assessment.total == 0 ? 0 : Double(assessment.met) / Double(assessment.total)

        return HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(presentation.color.opacity(0.16))
                Image(systemName: presentation.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(presentation.color)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(assessmentMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if assessment.total > 0 {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.09), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            presentation.color.gradient,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(assessment.met)/\(assessment.total)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                .frame(width: 48, height: 48)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: progress)
                .accessibilityLabel("\(assessment.met) of \(assessment.total) requirements met")
            }
        }
        .padding(16)
        .glassEffect(
            .regular.tint(presentation.color.opacity(0.08)),
            in: .rect(cornerRadius: 24)
        )
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("On your list")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if !occurrences.isEmpty {
                    Text(goalCountText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)

            if occurrences.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                        GoalRow(
                            occurrence: occurrence,
                            onEdit: { editingGoal = occurrence.goal },
                            onDelete: { goalPendingDeletion = occurrence.goal }
                        )
                        .environmentObject(store)

                        if index < occurrences.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.leading, 56)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
            }
        }
    }

    /// Food targets that count toward the day result — listed here so the
    /// requirement count in the result card adds up to what's on screen.
    private var targetColumns: [ColumnDef] {
        let dayKey = store.key(for: selectedDate)
        return store.numericColumns
            .filter(\.countsInSuccess)
            .map { $0.resolved(on: dayKey) }
            .filter(\.hasGoal)
    }

    private var targetsSection: some View {
        let columns = targetColumns
        let metCount = columns.filter { $0.isMet(total: store.total(of: $0, on: selectedDate)) == true }.count

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Food targets")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if !isFutureDay {
                    Text("\(metCount) of \(columns.count) on track")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    targetRow(column)
                    if index < columns.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .padding(.leading, 56)
                    }
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    private func targetRow(_ column: ColumnDef) -> some View {
        let total = store.total(of: column, on: selectedDate)
        let met = column.isMet(total: total) == true
        let progress = column.ringTarget.map { $0 > 0 ? min(total / $0, 1) : 0 } ?? 0

        return Button {
            if let current = store.data.columns.first(where: { $0.id == column.id }) {
                editingColumn = .target(for: current)
            }
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .stroke(column.color.opacity(0.18), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: isFutureDay ? 0 : progress)
                        .stroke(column.color.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 30, height: 30)
                .padding(4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(column.name)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(isFutureDay ? "Target \(column.goalText)" : "\(total.compactString) · \(column.goalText)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if !isFutureDay {
                    Image(systemName: met ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.title3)
                        .foregroundStyle(met ? Color.green : Color.white.opacity(0.3))
                        .frame(width: 44, height: 44)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(column.name), \(total.compactString), target \(column.goalText)")
        .accessibilityValue(isFutureDay ? "Planned" : (met ? "On track" : "Not met"))
        .accessibilityHint("Edits the target")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.goalDefinitions.isEmpty ? "checklist" : "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)

            VStack(spacing: 5) {
                Text(store.goalDefinitions.isEmpty ? "Create your first goal" : "Nothing planned")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(emptyStateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showGoalEditor = true
            } label: {
                Label("Add a goal", systemImage: "plus")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var emptyStateMessage: String {
        if store.goalDefinitions.isEmpty {
            return "Add a daily habit, choose days of the week, or plan something just once."
        }
        if calendar.isDateInToday(selectedDate) {
            return "Your schedule is clear today."
        }
        return "No goals are scheduled for \(dayTitle.lowercased())."
    }

    private var goalCountText: String {
        let completed = occurrences.filter { $0.status == .completed }.count
        let active = occurrences.filter { $0.status != .cancelled }.count
        return "\(completed) of \(active) done"
    }

    private var assessmentMessage: String {
        if store.isCheatDay(selectedDate) {
            return "Enjoy it — today can't break your streak."
        }
        guard assessment.total > 0 else {
            return "No success requirements are scheduled."
        }
        if isFutureDay {
            return "\(assessment.total) requirement\(assessment.total == 1 ? "" : "s") scheduled."
        }
        if isPastDay {
            if assessment.met == assessment.total {
                return "Every requirement was met."
            }
            return "\(assessment.met) of \(assessment.total) requirements were met."
        }
        if assessment.met == assessment.total {
            return "Every requirement has been met."
        }
        let remaining = assessment.unmet
        return "\(remaining) requirement\(remaining == 1 ? "" : "s") still to meet."
    }

    private var resultPresentation: (title: String, symbol: String, color: Color) {
        // A declared cheat day outranks everything, including "today".
        if store.isCheatDay(selectedDate) {
            return ("Cheat day", "star.fill", .orange)
        }
        if isFutureDay {
            return ("Planned day", "calendar.badge.clock", .blue)
        }
        if assessment.tier.countsAsSuccess || assessment.tier == .unrated {
            return tierPresentation(for: assessment.tier)
        }
        if calendar.isDateInToday(selectedDate) {
            return tierPresentation(for: assessment.tier)
        }
        let dayKey = store.key(for: selectedDate)
        let streak = store.streakInfo()
        if streak.semiGraceDays.contains(dayKey) {
            return ("Semi-grace day", DayTier.semiGrace.symbol, DayTier.semiGrace.color)
        }
        if streak.graceDays.contains(dayKey) {
            return ("Grace day", "shield.checkered", .dayGrace)
        }
        return ("Missed day", "xmark.circle", .red)
    }

    private func tierPresentation(for tier: DayTier) -> (title: String, symbol: String, color: Color) {
        switch tier {
        case .gold:
            return ("Gold day", tier.symbol, tier.color)
        case .silver:
            return ("Silver day", tier.symbol, tier.color)
        case .bronze:
            return ("Bronze day", tier.symbol, tier.color)
        case .semiGrace:
            return ("Semi-grace day", tier.symbol, tier.color)
        case .missed:
            // Only reached for today — the day is still running, so no red.
            return ("Not there yet", tier.symbol, .secondary)
        case .unrated:
            return ("Open day", tier.symbol, .secondary)
        }
    }

    private func shiftDay(_ amount: Int) {
        guard let next = calendar.date(byAdding: .day, value: amount, to: selectedDate) else { return }
        withAnimation(.snappy) {
            selectedDate = calendar.startOfDay(for: next)
        }
    }

    private func handleDayChange() {
        let newToday = calendar.startOfDay(for: Date())
        guard newToday != trackedToday else { return }
        if calendar.isDate(selectedDate, inSameDayAs: trackedToday) {
            withAnimation(.snappy) {
                selectedDate = newToday
            }
        }
        trackedToday = newToday
    }
}

private struct GoalRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let occurrence: GoalOccurrence
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var completionAnimation = false

    private var isCompleted: Bool { occurrence.status == .completed }
    private var isCancelled: Bool { occurrence.status == .cancelled }
    private var isInactive: Bool { isCompleted || isCancelled }
    private var isFutureOccurrence: Bool {
        occurrence.displayDay > DayKey.key(for: Date())
    }
    private var isRepeating: Bool {
        occurrence.goal.schedule.kind != .oneTime && occurrence.goal.endsBefore == nil
    }

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onEdit) {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the goal")

            Menu {
                actionItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Goal options")

            if isCancelled {
                Image(systemName: "minus.circle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            } else {
                Button {
                    toggleCompletion()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isCompleted ? Color.green.gradient : Color.clear.gradient)
                        Circle()
                            .strokeBorder(
                                isCompleted ? Color.green : Color.white.opacity(0.25),
                                lineWidth: isCompleted ? 0 : 1.5
                            )
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(isCompleted ? .black : .secondary)
                            .symbolEffect(.bounce, value: completionAnimation)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(isFutureOccurrence)
                .opacity(isFutureOccurrence ? 0.45 : 1)
                .accessibilityLabel(completionAccessibilityLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(.rect)
        .contextMenu {
            actionItems
        }
        .accessibilityValue(statusAccessibilityValue)
        .accessibilityActions {
            if isCancelled {
                Button("Restore for This Day") { restoreOccurrence() }
            } else if isCompleted {
                Button("Mark Incomplete") { toggleCompletion() }
            } else {
                Button("Move to Next Day") { moveOccurrence() }
                Button("Cancel for This Day") { cancelOccurrence() }
            }
            Button("Edit Goal") { onEdit() }
            if isRepeating {
                Button("Stop Repeating After Today") { stopRepeating() }
            }
            Button("Delete Goal") { onDelete() }
        }
    }

    /// Icon, title and schedule chips — the tappable part of the row.
    private var summary: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                Image(systemName: leadingSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text(occurrence.goal.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(isInactive ? Color.secondary : Color.white)
                    .strikethrough(isInactive, color: .secondary)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isInactive)

                HStack(spacing: 7) {
                    Label(scheduleText, systemImage: scheduleSymbol)

                    if occurrence.wasDeferred {
                        Label("Moved", systemImage: "arrow.turn.down.right")
                            .foregroundStyle(.orange)
                    }

                    if !occurrence.goal.impactsDaySuccess {
                        Label("Personal", systemImage: "heart")
                            .foregroundStyle(.secondary)
                    }

                    if isCancelled {
                        Text("Cancelled")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var actionItems: some View {
        if isCancelled {
            Button {
                restoreOccurrence()
            } label: {
                Label("Restore for This Day", systemImage: "arrow.uturn.backward")
            }
        } else if isCompleted {
            Button {
                toggleCompletion()
            } label: {
                Label("Mark Incomplete", systemImage: "arrow.uturn.backward.circle")
            }
        } else {
            Button {
                moveOccurrence()
            } label: {
                Label("Move to Next Day", systemImage: "arrow.right")
            }

            Button(role: .destructive) {
                cancelOccurrence()
            } label: {
                Label("Cancel for This Day", systemImage: "xmark.circle")
            }
        }

        Divider()

        Button {
            onEdit()
        } label: {
            Label("Edit Goal", systemImage: "pencil")
        }

        if isRepeating {
            Button(role: .destructive) {
                stopRepeating()
            } label: {
                Label("Stop Repeating After Today", systemImage: "calendar.badge.minus")
            }
        }

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete Goal", systemImage: "trash")
        }
    }

    private var completionAccessibilityLabel: String {
        if isCompleted { return "Mark \(occurrence.goal.title) incomplete" }
        if isFutureOccurrence { return "\(occurrence.goal.title) can be completed when it is due" }
        return "Complete \(occurrence.goal.title)"
    }

    private var statusAccessibilityValue: String {
        if isCancelled { return "Cancelled" }
        if isCompleted { return "Completed" }
        if isFutureOccurrence { return "Scheduled" }
        return "Incomplete"
    }

    private func toggleCompletion() {
        if reduceMotion {
            store.toggleGoalCompletion(occurrence)
        } else {
            completionAnimation.toggle()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                store.toggleGoalCompletion(occurrence)
            }
        }
    }

    private func restoreOccurrence() {
        if reduceMotion {
            store.restoreGoalOccurrence(occurrence)
        } else {
            withAnimation(.snappy) {
                store.restoreGoalOccurrence(occurrence)
            }
        }
    }

    private func moveOccurrence() {
        if reduceMotion {
            store.deferGoalOccurrence(occurrence)
        } else {
            withAnimation(.snappy) {
                store.deferGoalOccurrence(occurrence)
            }
        }
    }

    private func cancelOccurrence() {
        if reduceMotion {
            store.cancelGoalOccurrence(occurrence)
        } else {
            withAnimation(.snappy) {
                store.cancelGoalOccurrence(occurrence)
            }
        }
    }

    private func stopRepeating() {
        if reduceMotion {
            store.stopRepeatingGoal(occurrence.goal.id)
        } else {
            withAnimation(.snappy) {
                store.stopRepeatingGoal(occurrence.goal.id)
            }
        }
    }

    private var leadingSymbol: String {
        if isCompleted { return "checkmark" }
        if isCancelled { return "xmark" }
        return occurrence.goal.impactsDaySuccess ? "medal" : "heart"
    }

    private var accentColor: Color {
        if isCompleted { return .green }
        if isCancelled { return .secondary }
        return occurrence.goal.impactsDaySuccess ? .orange : .pink
    }

    private var scheduleSymbol: String {
        switch occurrence.goal.schedule.kind {
        case .daily: return "arrow.clockwise"
        case .weekly: return "calendar"
        case .oneTime: return "calendar.badge.checkmark"
        }
    }

    private var scheduleText: String {
        switch occurrence.goal.schedule.kind {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .oneTime:
            return "One time"
        }
    }
}

private struct GoalDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    var body: some View {
        NavigationStack {
            DatePicker(
                "Choose a date",
                selection: Binding(
                    get: { selectedDate },
                    set: { selectedDate = Calendar.current.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            .navigationTitle("Choose Date")
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

private struct GoalEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var scheduleKind: GoalScheduleKind = .oneTime
    @State private var selectedWeekdays: Set<Int> = []
    @State private var scheduledDate: Date
    @State private var impactsDaySuccess = true
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private let editingGoal: GoalDefinition?
    private let calendar = Calendar.current

    init(defaultDate: Date, editing: GoalDefinition? = nil) {
        editingGoal = editing
        let today = Calendar.current.startOfDay(for: Date())
        if let editing {
            _title = State(initialValue: editing.title)
            _scheduleKind = State(initialValue: editing.schedule.kind)
            _selectedWeekdays = State(initialValue: Set(editing.schedule.weekdays))
            let existingDate = editing.schedule.kind == .oneTime
                ? editing.schedule.dateKey.flatMap(DayKey.date(from:))
                : DayKey.date(from: editing.createdOn)
            _scheduledDate = State(initialValue: existingDate ?? today)
            _impactsDaySuccess = State(initialValue: editing.impactsDaySuccess)
        } else {
            _scheduledDate = State(initialValue: max(Calendar.current.startOfDay(for: defaultDate), today))
        }
    }

    /// New goals start today or later; editing keeps an existing past
    /// start date reachable.
    private var earliestDate: Date {
        let today = Calendar.current.startOfDay(for: Date())
        guard let editingGoal,
              let existingStart = DayKey.date(from: editingGoal.createdOn) else { return today }
        return min(existingStart, today)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedTitle.isEmpty && (scheduleKind != .weekly || !selectedWeekdays.isEmpty)
    }

    private var orderedWeekdays: [Int] {
        (0..<7).map { offset in
            ((calendar.firstWeekday - 1 + offset) % 7) + 1
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("What do you want to get done?", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                }

                Section {
                    Picker("Repeats", selection: $scheduleKind) {
                        Text("Once").tag(GoalScheduleKind.oneTime)
                        Text("Daily").tag(GoalScheduleKind.daily)
                        Text("Weekly").tag(GoalScheduleKind.weekly)
                    }
                    .pickerStyle(.segmented)

                    if scheduleKind == .weekly {
                        weekdayPicker
                    }

                    DatePicker(
                        scheduleKind == .oneTime ? "Due" : "Starts",
                        selection: $scheduledDate,
                        in: earliestDate...,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(scheduleFooter)
                }

                Section {
                    Toggle("Counts toward day result", isOn: $impactsDaySuccess)
                        .tint(.orange)
                } header: {
                    Text("Daily medal")
                } footer: {
                    Text(impactsDaySuccess
                         ? "Leaving this goal incomplete affects whether the day is gold, silver, bronze, or semi-grace."
                         : "This stays on your list, but it won't affect the day's medal or your streak.")
                }

                if editingGoal != nil {
                    Section {
                        Button("Delete Goal", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        Text("Removes this goal from every day, past and future, and re-evaluates your medals.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(editingGoal == nil ? "New Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingGoal == nil ? "Add" : "Save") { save() }
                        .disabled(!canAdd)
                }
            }
            .confirmationDialog(
                "Delete \"\(editingGoal?.title ?? "")\"? It disappears from every day and past medals are re-evaluated.",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Goal", role: .destructive) {
                    if let editingGoal {
                        store.deleteGoal(editingGoal.id)
                    }
                    dismiss()
                }
            }
            .onAppear {
                if editingGoal == nil {
                    titleFocused = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var weekdayPicker: some View {
        HStack(spacing: 5) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let selected = selectedWeekdays.contains(weekday)
                Button {
                    if selected {
                        selectedWeekdays.remove(weekday)
                    } else {
                        selectedWeekdays.insert(weekday)
                    }
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selected ? .black : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            selected ? Color.orange : Color.white.opacity(0.07),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduleFooter: String {
        switch scheduleKind {
        case .daily:
            return "This goal appears every day from the start date."
        case .weekly:
            if selectedWeekdays.isEmpty {
                return "Choose at least one day of the week."
            }
            return "This goal repeats on the selected days from the start date."
        case .oneTime:
            return "This goal appears only on the chosen date."
        }
    }

    private func save() {
        guard canAdd else { return }

        let schedule: GoalSchedule
        switch scheduleKind {
        case .daily:
            schedule = .daily
        case .weekly:
            schedule = .weekly(Array(selectedWeekdays))
        case .oneTime:
            schedule = .oneTime(on: store.key(for: scheduledDate))
        }

        if let editingGoal {
            var updated = editingGoal
            updated.title = trimmedTitle
            updated.schedule = schedule
            updated.createdOn = store.key(for: scheduledDate)
            updated.impactsDaySuccess = impactsDaySuccess
            store.updateGoal(updated)
        } else {
            store.addGoal(GoalDefinition(
                title: trimmedTitle,
                schedule: schedule,
                createdOn: store.key(for: scheduledDate),
                impactsDaySuccess: impactsDaySuccess
            ))
        }
        dismiss()
    }
}

private struct GoalEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 24)
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.65, dampingFraction: 0.82).delay(Double(index) * 0.07),
                value: appeared
            )
    }
}

private extension View {
    func goalEntrance(_ appeared: Bool, index: Int) -> some View {
        modifier(GoalEntranceModifier(appeared: appeared, index: index))
    }
}
