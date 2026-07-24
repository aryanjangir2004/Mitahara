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

struct AppData: Codable, Equatable {
    var columns: [ColumnDef] = []
    var days: [String: [EntryRow]] = [:]
    var centerColumnID: UUID?
    /// Missed days per calendar month that don't break the streak. nil = 0.
    var graceDaysPerMonth: Int?

    static func seeded() -> AppData {
        var data = AppData()
        let name = ColumnDef(name: "Name", type: .text)
        let kcal = ColumnDef(name: "Kcal", type: .number, minGoal: nil, maxGoal: 2000, colorHex: "FF9F0A")
        data.columns = [name, kcal]
        data.centerColumnID = kcal.id
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
