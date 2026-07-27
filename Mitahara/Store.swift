import SwiftUI
import SwiftData
import CoreData
import WidgetKit

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet {
            guard !isApplyingRemote else { return }
            scheduleSave()
        }
    }

    private let container: ModelContainer?
    private var isApplyingRemote = false
    private var hasPendingSave = false
    private var saveTask: Task<Void, Never>?
    private var remoteObserver: NSObjectProtocol?

    private static let cloudContainerID = "iCloud.com.aryanjangir.Mitahara"

    private static var legacyFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("mitahara.json")
    }

    init() {
        container = Self.makeContainer()
        data = AppData()
        isApplyingRemote = true
        migrateLegacyJSONIfNeeded()
        if let stored = loadFromStore() {
            data = stored
        } else {
            data = AppData.seeded()
            persist(data)
        }
        isApplyingRemote = false
        SharedSnapshot.write(data)

        // CloudKit imports land in the underlying store and post remote-change
        // notifications; refresh our snapshot when that happens.
        remoteObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromCloud()
            }
        }
    }

    deinit {
        if let remoteObserver {
            NotificationCenter.default.removeObserver(remoteObserver)
        }
    }

    // MARK: - SwiftData / CloudKit plumbing

    private static func makeContainer() -> ModelContainer? {
        let schema = Schema([DayRecord.self, SettingsRecord.self])
        // CloudKit setup traps asynchronously (it does not throw) when the
        // iCloud entitlement is missing, and has nothing to sync without an
        // iCloud account — so only enable mirroring when an iCloud identity
        // is actually present. Both stores share the same file, so data
        // carries over when the user signs in and relaunches.
        if FileManager.default.ubiquityIdentityToken != nil {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return container
            }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [local])
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    /// Imports the pre-CloudKit JSON file once, then renames it out of the way.
    private func migrateLegacyJSONIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.legacyFileURL.path) else { return }
        if let context = container?.mainContext {
            let settingsCount = (try? context.fetchCount(FetchDescriptor<SettingsRecord>())) ?? 0
            let dayCount = (try? context.fetchCount(FetchDescriptor<DayRecord>())) ?? 0
            if settingsCount == 0, dayCount == 0,
               let raw = try? Data(contentsOf: Self.legacyFileURL),
               let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
                persist(decoded)
            }
        }
        let backup = Self.legacyFileURL.appendingPathExtension("bak")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: Self.legacyFileURL, to: backup)
    }

    private func loadFromStore() -> AppData? {
        guard let context = container?.mainContext else { return nil }
        let settingsRecords = (try? context.fetch(FetchDescriptor<SettingsRecord>())) ?? []
        let dayRecords = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        guard !settingsRecords.isEmpty || !dayRecords.isEmpty else { return nil }

        var result = AppData()

        // CloudKit sync can leave duplicate settings records (fresh install +
        // remote copy). Prefer the one with the richest column set.
        let best = settingsRecords.max { lhs, rhs in
            let l = decode([ColumnDef].self, from: lhs.columnsData)?.count ?? 0
            let r = decode([ColumnDef].self, from: rhs.columnsData)?.count ?? 0
            return l < r
        }
        if let best {
            result.columns = decode([ColumnDef].self, from: best.columnsData) ?? []
            result.centerColumnID = best.centerColumnID
            result.graceDaysPerMonth = best.graceDaysPerMonth
            result.cheatDays = best.cheatDays
        }
        if result.columns.isEmpty {
            result.columns = AppData.seeded().columns
            result.centerColumnID = result.columns.last?.id
        }

        // Duplicate day records for the same date merge by row id.
        for record in dayRecords {
            let rows = decode([EntryRow].self, from: record.rowsData) ?? []
            guard !rows.isEmpty else { continue }
            if var existing = result.days[record.dateKey] {
                let seen = Set(existing.map(\.id))
                existing.append(contentsOf: rows.filter { !seen.contains($0.id) })
                result.days[record.dateKey] = existing
            } else {
                result.days[record.dateKey] = rows
            }
        }
        return result
    }

    private func persist(_ snapshot: AppData) {
        guard let context = container?.mainContext else { return }

        let settingsRecords = (try? context.fetch(FetchDescriptor<SettingsRecord>())) ?? []
        let settings = settingsRecords.first ?? {
            let record = SettingsRecord()
            context.insert(record)
            return record
        }()
        let encodedColumns = encode(snapshot.columns)
        if settings.columnsData != encodedColumns { settings.columnsData = encodedColumns }
        if settings.centerColumnID != snapshot.centerColumnID { settings.centerColumnID = snapshot.centerColumnID }
        if settings.graceDaysPerMonth != snapshot.graceDaysPerMonth { settings.graceDaysPerMonth = snapshot.graceDaysPerMonth }
        if settings.cheatDays != snapshot.cheatDays { settings.cheatDays = snapshot.cheatDays }
        for extra in settingsRecords.dropFirst() { context.delete(extra) }

        let dayRecords = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        let byKey = Dictionary(grouping: dayRecords, by: \.dateKey)
        for (key, rows) in snapshot.days {
            let encoded = encode(rows)
            if let records = byKey[key], let first = records.first {
                if first.rowsData != encoded { first.rowsData = encoded }
                for extra in records.dropFirst() { context.delete(extra) }
            } else {
                context.insert(DayRecord(dateKey: key, rowsData: encoded))
            }
        }
        for (key, records) in byKey where snapshot.days[key] == nil {
            records.forEach(context.delete)
        }

        try? context.save()

        SharedSnapshot.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func scheduleSave() {
        hasPendingSave = true
        saveTask?.cancel()
        let snapshot = data
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.persist(snapshot)
                self?.hasPendingSave = false
            }
        }
    }

    /// Re-reads the store (called on foreground and on CloudKit remote-change
    /// notifications). Skipped while a local edit is waiting to be saved so
    /// in-progress typing is never clobbered.
    func refreshFromCloud() {
        guard !hasPendingSave else { return }
        guard let fresh = loadFromStore(), fresh != data else { return }
        isApplyingRemote = true
        data = fresh
        isApplyingRemote = false
    }

    // MARK: - Dates

    func key(for date: Date) -> String {
        DayKey.key(for: date)
    }

    // MARK: - Rows

    func rows(on date: Date) -> [EntryRow] {
        data.rows(on: date)
    }

    func addRow(on date: Date) {
        data.days[key(for: date), default: []].append(EntryRow())
    }

    func deleteRow(_ rowID: UUID, on date: Date) {
        let k = key(for: date)
        data.days[k]?.removeAll { $0.id == rowID }
        if data.days[k]?.isEmpty == true {
            data.days.removeValue(forKey: k)
        }
    }

    func setValue(_ value: String, rowID: UUID, columnID: UUID, on date: Date) {
        let k = key(for: date)
        guard var rows = data.days[k],
              let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].values[columnID] = value
        data.days[k] = rows
    }

    func value(rowID: UUID, columnID: UUID, on date: Date) -> String {
        rows(on: date).first { $0.id == rowID }?.values[columnID] ?? ""
    }

    // MARK: - Columns

    var numericColumns: [ColumnDef] {
        data.numericColumns
    }

    var centerColumn: ColumnDef? {
        if let id = data.centerColumnID,
           let col = numericColumns.first(where: { $0.id == id }) {
            return col
        }
        return numericColumns.first
    }

    func addColumn(_ column: ColumnDef) {
        data.columns.append(column)
        if data.centerColumnID == nil, column.type == .number {
            data.centerColumnID = column.id
        }
    }

    func updateColumn(_ column: ColumnDef) {
        guard let idx = data.columns.firstIndex(where: { $0.id == column.id }) else { return }
        let old = data.columns[idx]
        var new = column
        new.goalHistory = old.goalHistory
        // A goal change only applies from today onward; past days keep the
        // goals that were active at the time.
        if new.type == .number, new.minGoal != old.minGoal || new.maxGoal != old.maxGoal {
            let today = DayKey.key(for: Date())
            var history = old.goalHistory ?? []
            if history.isEmpty {
                history.append(GoalSpan(effectiveFrom: "", minGoal: old.minGoal, maxGoal: old.maxGoal))
            }
            history.removeAll { $0.effectiveFrom == today }
            history.append(GoalSpan(effectiveFrom: today, minGoal: new.minGoal, maxGoal: new.maxGoal))
            new.goalHistory = history
        }
        data.columns[idx] = new
    }

    func deleteColumn(_ columnID: UUID) {
        data.columns.removeAll { $0.id == columnID }
        for (k, rows) in data.days {
            var rows = rows
            for i in rows.indices {
                rows[i].values.removeValue(forKey: columnID)
            }
            data.days[k] = rows
        }
        if data.centerColumnID == columnID {
            data.centerColumnID = numericColumns.first?.id
        }
    }

    // MARK: - Totals & goals

    func total(of column: ColumnDef, on date: Date) -> Double {
        data.total(of: column, on: date)
    }

    /// A day counts as successful when it has at least one non-blank entry,
    /// at least one counting column has a goal, and every counting goal is
    /// met — judged by the goals that were active on that day.
    func isDaySuccessful(_ date: Date) -> Bool {
        let dayRows = rows(on: date)
        guard dayRows.contains(where: { !$0.isBlank }) else { return false }
        let dayKey = key(for: date)
        let goalColumns = numericColumns
            .filter(\.countsInSuccess)
            .map { $0.resolved(on: dayKey) }
            .filter(\.hasGoal)
        guard !goalColumns.isEmpty else { return false }
        return goalColumns.allSatisfy { $0.isMet(total: total(of: $0, on: date)) == true }
    }

    struct StreakInfo {
        var count: Int = 0
        /// Day keys of missed days inside the streak that grace covered.
        var graceDays: Set<String> = []
    }

    var graceDaysPerMonth: Int {
        get { data.graceDaysPerMonth ?? 0 }
        set { data.graceDaysPerMonth = newValue }
    }

    // MARK: - Cheat days

    var cheatDaySet: Set<String> { Set(data.cheatDays ?? []) }

    func isCheatDay(_ date: Date) -> Bool {
        cheatDaySet.contains(key(for: date))
    }

    func toggleCheatDay(_ date: Date) {
        var set = cheatDaySet
        let dayKey = key(for: date)
        if set.contains(dayKey) {
            set.remove(dayKey)
        } else {
            set.insert(dayKey)
        }
        data.cheatDays = set.isEmpty ? nil : set.sorted()
    }

    func streakInfo(asOf today: Date = Date()) -> StreakInfo {
        let cal = Calendar.current
        var info = StreakInfo()

        // Grace can bridge gaps, so bound the walk at the earliest logged day.
        let earliestLoggedKey = data.days
            .filter { _, rows in rows.contains { !$0.isBlank } }
            .keys.min()
        guard let earliestLoggedKey else { return info }

        var graceUsed: [String: Int] = [:]   // "yyyy-MM" -> used
        let budget = graceDaysPerMonth

        var day = cal.startOfDay(for: today)
        // Today doesn't break the streak while it's still in progress.
        if isDaySuccessful(day) {
            info.count += 1
        }
        day = cal.date(byAdding: .day, value: -1, to: day)!

        let cheat = cheatDaySet
        while key(for: day) >= earliestLoggedKey {
            let dayKey = key(for: day)
            if isDaySuccessful(day) {
                info.count += 1
            } else if cheat.contains(dayKey) {
                // Explicit cheat day — bridged for free, no budget consumed.
                info.graceDays.insert(dayKey)
            } else {
                let monthKey = String(dayKey.prefix(7))
                if graceUsed[monthKey, default: 0] < budget {
                    graceUsed[monthKey, default: 0] += 1
                    info.graceDays.insert(dayKey)
                } else {
                    break
                }
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return info
    }

    func currentStreak(asOf today: Date = Date()) -> Int {
        streakInfo(asOf: today).count
    }

    /// Wipes everything — local store, CloudKit (via mirroring), and the
    /// widget snapshot — and reseeds the default columns.
    func eraseAllData() {
        if let context = container?.mainContext {
            try? context.delete(model: DayRecord.self)
            try? context.delete(model: SettingsRecord.self)
            try? context.save()
        }
        isApplyingRemote = true
        data = AppData.seeded()
        isApplyingRemote = false
        persist(data)
    }
}
