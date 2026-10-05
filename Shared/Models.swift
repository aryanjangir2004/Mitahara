import SwiftUI

enum ColumnType: String, Codable, CaseIterable, Identifiable {
    case text
    case number

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        }
    }
}

/// A goal snapshot that applies from `effectiveFrom` (a day key, "" = since
/// forever) until the next span. Lets past days keep the goals that were
/// active at the time instead of being rewritten by later goal edits.
struct GoalSpan: Codable, Equatable {
    var effectiveFrom: String
    var minGoal: Double?
    var maxGoal: Double?
}

struct ColumnDef: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var type: ColumnType
    var minGoal: Double?
    var maxGoal: Double?
    var colorHex: String = "FF9F0A"
    var goalHistory: [GoalSpan]?
    /// nil = true (backward compatible). When false the column is tracked
    /// and shown, but never affects whether a day counts as successful.
    var countsTowardSuccess: Bool?

    var countsInSuccess: Bool { countsTowardSuccess ?? true }

    var color: Color { Color(hex: colorHex) }

    var hasGoal: Bool { type == .number && (minGoal != nil || maxGoal != nil) }

    /// The value used as the "full ring" target.
    var ringTarget: Double? { maxGoal ?? minGoal }

    /// nil = no goal set for this column.
    func isMet(total: Double) -> Bool? {
        guard type == .number else { return nil }
        switch (minGoal, maxGoal) {
        case (nil, nil):
            return nil
        case let (lo?, nil):
            return total >= lo
        case let (nil, hi?):
            return total <= hi
        case let (lo?, hi?):
            return total >= lo && total <= hi
        }
    }

    /// The goals that were active on the given day. Day keys ("yyyy-MM-dd")
    /// compare correctly as strings.
    func goals(on dayKey: String) -> (min: Double?, max: Double?) {
        guard let history = goalHistory, !history.isEmpty else {
            return (minGoal, maxGoal)
        }
        let sorted = history.sorted { $0.effectiveFrom < $1.effectiveFrom }
        let active = sorted.last { $0.effectiveFrom <= dayKey } ?? sorted[0]
        return (active.minGoal, active.maxGoal)
    }

    /// A copy of this column with min/max swapped for the goals that were
    /// active on the given day — everything downstream (rings, chips,
    /// success checks) can then treat it like a normal column.
    func resolved(on dayKey: String) -> ColumnDef {
        var copy = self
        let goals = goals(on: dayKey)
        copy.minGoal = goals.min
        copy.maxGoal = goals.max
        return copy
    }

    var goalText: String {
        switch (minGoal, maxGoal) {
        case (nil, nil): return "no goal"
        case let (lo?, nil): return "min \(lo.compactString)"
        case let (nil, hi?): return "max \(hi.compactString)"
        case let (lo?, hi?): return "\(lo.compactString)–\(hi.compactString)"
        }
    }
}

struct EntryRow: Identifiable, Codable, Equatable {
    var id = UUID()
    var values: [UUID: String] = [:]

    /// True when the row has no real content — blank rows never make a day
    /// count as "logged".
    var isBlank: Bool {
        values.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - Daily goals

enum GoalScheduleKind: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case oneTime

    var id: String { rawValue }
}

/// Describes when a goal creates an occurrence. Weekdays use Foundation's
/// Calendar values (Sunday = 1 ... Saturday = 7), which keeps schedules
/// correct when the user's first weekday changes.
struct GoalSchedule: Codable, Equatable {
    var kind: GoalScheduleKind
    var weekdays: [Int] = []
    var dateKey: String?

    static var daily: GoalSchedule {
        GoalSchedule(kind: .daily)
    }

    static func weekly(_ weekdays: [Int]) -> GoalSchedule {
        GoalSchedule(kind: .weekly, weekdays: Array(Set(weekdays)).sorted())
    }

    static func oneTime(on dayKey: String) -> GoalSchedule {
        GoalSchedule(kind: .oneTime, dateKey: dayKey)
    }

    func occurs(on dayKey: String, createdOn: String, endsBefore: String? = nil) -> Bool {
        guard dayKey >= createdOn else { return false }
        if let endsBefore, dayKey >= endsBefore { return false }
        switch kind {
        case .daily:
            return true
        case .weekly:
            guard let date = DayKey.date(from: dayKey) else { return false }
            return weekdays.contains(Calendar.current.component(.weekday, from: date))
        case .oneTime:
            return dateKey == dayKey
        }
    }
}

struct GoalDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var schedule: GoalSchedule
    var createdOn: String
    /// Exclusive end date for a repeating schedule. This retires a series
    /// without rewriting its earlier occurrences and day results.
    var endsBefore: String?
    /// When false the goal is still scheduled and tracked, but it is omitted
    /// from the day's medal and streak calculation.
    var impactsDaySuccess: Bool = true
    /// Goal definitions may be retired on another device; latest edit wins.
    var updatedAt: Date? = Date()
}

enum GoalOccurrenceStatus: String, Codable, Equatable {
    case pending
    case completed
    case cancelled
}

/// Created only after an occurrence is completed, cancelled or moved. The
/// source day stays stable while displayDay changes when the user defers it.
struct GoalOccurrenceOverride: Codable, Equatable {
    var goalID: UUID
    var sourceDay: String
    var displayDay: String
    var status: GoalOccurrenceStatus
    /// Used to resolve the same occurrence being changed on two devices.
    /// Optional keeps snapshots from early builds decodable.
    var updatedAt: Date?
}

/// A materialized goal for one day. Its id is stable across deferrals so a
/// moved goal remains the same piece of work rather than becoming a copy.
struct GoalOccurrence: Identifiable, Equatable {
    var id: String
    var goal: GoalDefinition
    var sourceDay: String
    var displayDay: String
    var status: GoalOccurrenceStatus

    var wasDeferred: Bool { sourceDay != displayDay }
}

enum DayTier: String, Equatable {
    case gold
    case silver
    case bronze
    case semiGrace
    case missed
    case unrated

    var countsAsSuccess: Bool {
        self == .gold || self == .silver || self == .bronze
    }

    /// Single source of truth for tier colors, shared by the calendar,
    /// settings, the Goals page, the Log tab chip and the widgets.
    var color: Color {
        switch self {
        case .gold: return Color(red: 1.00, green: 0.78, blue: 0.16)
        case .silver: return Color(red: 0.78, green: 0.82, blue: 0.88)
        case .bronze: return Color(red: 0.80, green: 0.48, blue: 0.24)
        case .semiGrace: return Color(red: 0.38, green: 0.82, blue: 0.84)
        case .missed: return Color(red: 1.00, green: 0.35, blue: 0.35)
        case .unrated: return Color.white.opacity(0.35)
        }
    }

    var symbol: String {
        switch self {
        case .gold, .silver, .bronze: return "medal.fill"
        case .semiGrace: return "leaf.fill"
        case .missed: return "circle.dashed"
        case .unrated: return "sparkles"
        }
    }
}

extension Color {
    /// Calendar fill for days bridged by the monthly grace budget. Distinct
    /// from orange, which belongs to cheat days.
    static let dayGrace = Color(red: 0.56, green: 0.62, blue: 1.0)
}

struct DayAssessment: Equatable {
    var tier: DayTier
    var met: Int
    var unmet: Int

    var total: Int { met + unmet }
}

struct AppData: Codable, Equatable {
    var columns: [ColumnDef] = []
    var days: [String: [EntryRow]] = [:]
    var centerColumnID: UUID?
    /// Missed days per calendar month that don't break the streak. nil = 0.
    var graceDaysPerMonth: Int?
    /// Day keys the user explicitly marked as cheat days — they never break
    /// the streak and never consume the monthly grace budget.
    var cheatDays: [String]?
    /// Prevents the seeded nutrition goal from rating dates before the user
    /// began using the app. Optional for older snapshots.
    var trackingStartedOn: String?
    /// Optional for decoding snapshots written before the Goals page existed.
    var goals: [GoalDefinition]?
    var goalOverrides: [String: GoalOccurrenceOverride]?

    static func seeded() -> AppData {
        var data = AppData()
        let name = ColumnDef(name: "Name", type: .text)
        let kcal = ColumnDef(name: "Kcal", type: .number, minGoal: nil, maxGoal: 2000, colorHex: "FF9F0A")
        data.columns = [name, kcal]
        data.centerColumnID = kcal.id
        data.trackingStartedOn = DayKey.key(for: Date())
        return data
    }
}

enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }
}

extension AppData {
    var numericColumns: [ColumnDef] {
        columns.filter { $0.type == .number }
    }

    func rows(on date: Date) -> [EntryRow] {
        days[DayKey.key(for: date)] ?? []
    }

    func total(of column: ColumnDef, on date: Date) -> Double {
        rows(on: date)
            .compactMap { Double(($0.values[column.id] ?? "").replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
    }

    /// Materializes scheduled and deferred work for a day. Pure so the widget
    /// process can evaluate a day exactly like the app; `deferredIn` lets the
    /// app inject its cached display-day index instead of rescanning.
    func goalOccurrences(
        on dayKey: String,
        deferredIn: [String: GoalOccurrenceOverride]? = nil
    ) -> [GoalOccurrence] {
        let goals = goals ?? []
        let overrides = goalOverrides ?? [:]
        var result: [GoalOccurrence] = []

        for goal in goals where goal.schedule.occurs(
            on: dayKey,
            createdOn: goal.createdOn,
            endsBefore: goal.endsBefore
        ) {
            let id = "\(goal.id.uuidString)|\(dayKey)"
            if let override = overrides[id] {
                guard override.displayDay == dayKey else { continue }
                result.append(GoalOccurrence(
                    id: id,
                    goal: goal,
                    sourceDay: override.sourceDay,
                    displayDay: override.displayDay,
                    status: override.status
                ))
            } else {
                result.append(GoalOccurrence(
                    id: id,
                    goal: goal,
                    sourceDay: dayKey,
                    displayDay: dayKey,
                    status: .pending
                ))
            }
        }

        // Occurrences moved here from an earlier day are not produced by the
        // normal schedule lookup above, so append them explicitly.
        let movedIn = deferredIn ?? overrides.filter { $0.value.displayDay == dayKey }
        for (id, override) in movedIn
            where override.displayDay == dayKey && override.sourceDay != dayKey {
            guard let goal = goals.first(where: { $0.id == override.goalID }) else { continue }
            result.append(GoalOccurrence(
                id: id,
                goal: goal,
                sourceDay: override.sourceDay,
                displayDay: override.displayDay,
                status: override.status
            ))
        }

        let order = Dictionary(uniqueKeysWithValues: goals.enumerated().map { ($0.element.id, $0.offset) })
        return result.sorted {
            let lhs = order[$0.goal.id] ?? .max
            let rhs = order[$1.goal.id] ?? .max
            return lhs == rhs ? $0.sourceDay < $1.sourceDay : lhs < rhs
        }
    }

    /// True when the user did anything trackable that day — logged food or
    /// completed a goal. Days without activity can never earn a medal.
    func hasTrackedActivity(on date: Date, occurrences: [GoalOccurrence]? = nil) -> Bool {
        if rows(on: date).contains(where: { !$0.isBlank }) { return true }
        let dayKey = DayKey.key(for: date)
        return (occurrences ?? goalOccurrences(on: dayKey)).contains { $0.status == .completed }
    }

    /// Combines nutrition targets and scheduled goals into the day's medal.
    ///
    /// Grading is proportional with absolute allowances for small sets, and
    /// holds two invariants: a day where nothing was met is never a success,
    /// and meeting more requirements can never produce a worse tier.
    /// - gold: everything met
    /// - silver: at most 1 missed, or 75%+ met
    /// - bronze: at most 2 missed, or 60%+ met
    /// - semi-grace: anything met at all
    /// Future days, days before tracking began, and cheat days are unrated.
    func dayAssessment(on date: Date, occurrences: [GoalOccurrence]? = nil) -> DayAssessment {
        let dayKey = DayKey.key(for: date)
        let todayKey = DayKey.key(for: Date())
        if dayKey > todayKey {
            return DayAssessment(tier: .unrated, met: 0, unmet: 0)
        }
        if let trackingStartedOn, dayKey < trackingStartedOn {
            return DayAssessment(tier: .unrated, met: 0, unmet: 0)
        }
        // A declared cheat day is off the books entirely.
        if (cheatDays ?? []).contains(dayKey) {
            return DayAssessment(tier: .unrated, met: 0, unmet: 0)
        }

        let nutritionGoals = numericColumns
            .filter(\.countsInSuccess)
            .map { $0.resolved(on: dayKey) }
            .filter(\.hasGoal)
        let allOccurrences = occurrences ?? goalOccurrences(on: dayKey)
        let scheduledGoals = allOccurrences.filter {
            $0.goal.impactsDaySuccess && $0.status != .cancelled
        }

        // Targets are evaluated against actual totals — a max-only target is
        // legitimately met at zero, so gold stays reachable on goal-only days.
        var met = nutritionGoals.filter { $0.isMet(total: total(of: $0, on: date)) == true }.count
        var unmet = nutritionGoals.count - met
        met += scheduledGoals.filter { $0.status == .completed }.count
        unmet += scheduledGoals.filter { $0.status != .completed }.count

        guard met + unmet > 0 else {
            return DayAssessment(tier: .unrated, met: 0, unmet: 0)
        }
        guard hasTrackedActivity(on: date, occurrences: allOccurrences), met > 0 else {
            return DayAssessment(tier: .missed, met: met, unmet: unmet)
        }

        let ratio = Double(met) / Double(met + unmet)
        let tier: DayTier
        if unmet == 0 {
            tier = .gold
        } else if unmet == 1 || ratio >= 0.75 {
            tier = .silver
        } else if unmet == 2 || ratio >= 0.6 {
            tier = .bronze
        } else {
            tier = .semiGrace
        }
        return DayAssessment(tier: tier, met: met, unmet: unmet)
    }
}

/// The app writes its full data set to the shared App Group container so the
/// widget extension can read it without touching the SwiftData/CloudKit store.
enum SharedSnapshot {
    static let appGroupID = "group.com.aryanjangir.Mitahara"

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("snapshot.json")
    }

    static func write(_ data: AppData) {
        // Widgets evaluate the day exactly like the app, so the snapshot
        // carries goals and occurrence overrides too.
        guard let url, let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    static func read() -> AppData? {
        guard let url, let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: raw)
    }
}

extension Double {
    var compactString: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(self))
        }
        return String(format: "%.1f", self)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum RingPalette {
    static let hexes: [String] = [
        "FF9F0A", // orange
        "FF375F", // pink/red
        "30D158", // green
        "0A84FF", // blue
        "64D2FF", // cyan
        "BF5AF2", // purple
        "FFD60A", // yellow
        "66D4CF", // mint
        "FF6961", // coral
        "AC8E68", // tan
    ]
}
