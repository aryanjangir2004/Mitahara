import SwiftUI
import SwiftData
import CoreData
import WidgetKit

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData {
        didSet {
            goalOverridesByDisplayDayCache = nil
            dayAssessmentCache.removeAll()
            guard !isApplyingRemote else { return }
            scheduleSave()
        }
    }

    private let container: ModelContainer?
    /// Whether the store mirrors to the private iCloud database. Off when
    /// no iCloud identity was available at launch (see `makeContainer`).
    let isCloudSyncEnabled: Bool
    /// When the last iCloud import/export finished successfully.
    @Published private(set) var lastCloudSync: Date?
    /// The most recent iCloud sync failure, cleared by the next success.
    @Published private(set) var cloudSyncProblem: String?
    /// True after a fresh install with iCloud on, until the first import
    /// finishes — the UI says data is being restored instead of looking
    /// empty for good.
    @Published private(set) var isRestoringFromCloud = false
    /// Day keys emptied on this device since the last save. Only these are
    /// deleted from the store: a day missing from a (possibly stale)
    /// snapshot may simply not have been imported from iCloud yet.
    private var locallyDeletedDayKeys: Set<String> = []
    private var cloudEventObserver: NSObjectProtocol?
    private var isApplyingRemote = false
    private var hasPendingSave = false
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0
    private var remoteObserver: NSObjectProtocol?
    private var goalOverridesByDisplayDayCache: [String: [String: GoalOccurrenceOverride]]?
    /// Memoized day medals — `streakInfo` and the calendar would otherwise
    /// re-grade all of history on every render. Invalidated on any data
    /// change, and wholesale when the calendar day rolls over (a cached
    /// "today" or future day is graded differently once the date moves).
    private var dayAssessmentCache: [String: DayAssessment] = [:]
    private var dayAssessmentCacheDay = ""
    /// The last snapshot written for widgets, to skip no-op rewrites.
    private var lastWidgetSnapshot: AppData?

    /// Missing timestamps only exist in legacy snapshots. Treat them as an
    /// old version so any real edit wins during CloudKit duplicate merging.
    private static let legacyVersionDate = Date(timeIntervalSince1970: 0)

    private struct GoalPersistenceCandidate {
        var definition: GoalDefinition?
        var updatedAt: Date
        var orderIndex: Int?
        var isGranular: Bool
        var isTombstone: Bool
        var payloadFingerprint: String
        var recordTieBreaker: String
    }

    private struct OccurrencePersistenceCandidate {
        var state: GoalOccurrenceOverride?
        var updatedAt: Date
        var isGranular: Bool
        var isTombstone: Bool
        var payloadFingerprint: String
        var recordTieBreaker: String
    }

    private static let cloudContainerID = "iCloud.com.aryanjangir.Mitahara"

    private static var legacyFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("mitahara.json")
    }

    init() {
        let (container, cloudEnabled) = Self.makeContainer()
        self.container = container
        isCloudSyncEnabled = cloudEnabled
        data = AppData()
        isApplyingRemote = true
        migrateLegacyJSONIfNeeded()
        if let stored = loadFromStore() {
            data = stored
            isApplyingRemote = false
            // Also writes inferred migration defaults (such as tracking start)
            // back into stores created by earlier app versions.
            persist(data)
        } else {
            // Fresh install: show the starter columns but don't save them.
            // `persist` keeps them out of the store until the user changes
            // them, so they can't compete with real settings still on their
            // way down from iCloud.
            data = AppData.seeded()
            isApplyingRemote = false
            if cloudEnabled {
                isRestoringFromCloud = true
                // Never leave the "restoring" note up if no import event
                // ever arrives (offline, iCloud slow to respond).
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    self?.isRestoringFromCloud = false
                }
            }
        }

        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let endDate = event.endDate else { return }
            let succeeded = event.succeeded
            let isImport = event.type == .import
            let problem = event.error.map { ($0 as NSError).localizedDescription }
            MainActor.assumeIsolated {
                self?.handleCloudEvent(succeeded: succeeded, isImport: isImport, endDate: endDate, problem: problem)
            }
        }

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
        if let cloudEventObserver {
            NotificationCenter.default.removeObserver(cloudEventObserver)
        }
    }

    private func handleCloudEvent(succeeded: Bool, isImport: Bool, endDate: Date, problem: String?) {
        if succeeded {
            lastCloudSync = endDate
            cloudSyncProblem = nil
        } else {
            cloudSyncProblem = problem ?? "iCloud sync failed."
        }
        if isImport, isRestoringFromCloud {
            isRestoringFromCloud = false
            refreshFromCloud()
        }
    }

    // MARK: - SwiftData / CloudKit plumbing

    private static func makeContainer() -> (ModelContainer?, cloudEnabled: Bool) {
        let schema = Schema([
            DayRecord.self,
            SettingsRecord.self,
            GoalDefinitionRecord.self,
            GoalOccurrenceRecord.self,
        ])
        // CloudKit setup traps asynchronously (it does not throw) when the
        // iCloud entitlement is missing, and has nothing to sync without an
        // iCloud account — so only enable mirroring when an iCloud identity
        // is actually present. Both stores share the same file, so data
        // carries over when the user signs in and relaunches.
        if FileManager.default.ubiquityIdentityToken != nil {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return (container, true)
            }
        }
        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return (try ModelContainer(for: schema, configurations: [local]), false)
        } catch {
            assertionFailure("Unable to open the local SwiftData store: \(error)")
            return (nil, false)
        }
    }

    /// True when the settings are still exactly the fresh-install starters.
    private static func hasStarterSettings(_ snapshot: AppData) -> Bool {
        let seed = AppData.seeded()
        return snapshot.columns == seed.columns
            && snapshot.centerColumnID == seed.centerColumnID
            && (snapshot.graceDaysPerMonth ?? 0) == 0
            && (snapshot.cheatDays ?? []).isEmpty
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
        guard fm.fileExists(atPath: Self.legacyFileURL.path),
              let context = container?.mainContext else { return }
        let settingsCount = (try? context.fetchCount(FetchDescriptor<SettingsRecord>())) ?? 0
        let dayCount = (try? context.fetchCount(FetchDescriptor<DayRecord>())) ?? 0
        // Granular goal rows must not block importing unrelated legacy
        // nutrition/settings JSON that still has no settings/day rows.
        if settingsCount == 0, dayCount == 0 {
            guard let raw = try? Data(contentsOf: Self.legacyFileURL),
                  let decoded = try? JSONDecoder().decode(AppData.self, from: raw) else {
                // Leave an unreadable file in place rather than silently
                // archiving data that was never imported.
                return
            }
            persist(decoded)
        }
        let backup = Self.legacyFileURL.appendingPathExtension("bak")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: Self.legacyFileURL, to: backup)
    }

    private func shouldReplace(
        _ existing: GoalPersistenceCandidate,
        with incoming: GoalPersistenceCandidate
    ) -> Bool {
        // A granular deletion suppresses every legacy blob value, regardless
        // of blob timestamp. Only a newer granular non-tombstone can revive it.
        if existing.isGranular, existing.isTombstone, !incoming.isGranular { return false }
        if incoming.isGranular, incoming.isTombstone, !existing.isGranular { return true }
        if incoming.updatedAt != existing.updatedAt {
            return incoming.updatedAt > existing.updatedAt
        }
        if incoming.isTombstone != existing.isTombstone {
            return incoming.isTombstone
        }
        // Compare the logical payload before its storage source. Otherwise a
        // backfilled nil-timestamp record could permanently mask a different
        // nil-timestamp legacy duplicate that arrives later.
        if incoming.payloadFingerprint != existing.payloadFingerprint {
            return incoming.payloadFingerprint > existing.payloadFingerprint
        }
        if incoming.isGranular != existing.isGranular {
            return incoming.isGranular
        }
        return incoming.recordTieBreaker > existing.recordTieBreaker
    }

    private func shouldReplace(
        _ existing: OccurrencePersistenceCandidate,
        with incoming: OccurrencePersistenceCandidate
    ) -> Bool {
        if existing.isGranular, existing.isTombstone, !incoming.isGranular { return false }
        if incoming.isGranular, incoming.isTombstone, !existing.isGranular { return true }
        if incoming.updatedAt != existing.updatedAt {
            return incoming.updatedAt > existing.updatedAt
        }
        if incoming.isTombstone != existing.isTombstone {
            return incoming.isTombstone
        }
        if incoming.payloadFingerprint != existing.payloadFingerprint {
            return incoming.payloadFingerprint > existing.payloadFingerprint
        }
        if incoming.isGranular != existing.isGranular {
            return incoming.isGranular
        }
        return incoming.recordTieBreaker > existing.recordTieBreaker
    }

    private func loadFromStore() -> AppData? {
        guard let context = container?.mainContext else { return nil }
        let settingsRecords = (try? context.fetch(FetchDescriptor<SettingsRecord>())) ?? []
        let dayRecords = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        let granularGoalRecords = (try? context.fetch(FetchDescriptor<GoalDefinitionRecord>())) ?? []
        let granularOccurrenceRecords = (try? context.fetch(FetchDescriptor<GoalOccurrenceRecord>())) ?? []
        guard !settingsRecords.isEmpty
                || !dayRecords.isEmpty
                || !granularGoalRecords.isEmpty
                || !granularOccurrenceRecords.isEmpty else { return nil }

        var result = AppData()

        // Decode each day's rows once; they also decide between duplicate
        // settings records just below.
        let decodedRows = dayRecords.map { decode([EntryRow].self, from: $0.rowsData) ?? [] }
        var columnUsage: [UUID: Int] = [:]
        for rows in decodedRows {
            for row in rows {
                for (columnID, value) in row.values
                where !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    columnUsage[columnID, default: 0] += 1
                }
            }
        }

        // CloudKit sync can leave duplicate settings records (a fresh
        // install's copy + the one restored from iCloud). Prefer the columns
        // the logged entries actually use, then the richest column set.
        // Counting columns alone let fresh starter columns win a tie, which
        // hid every past entry (their values are keyed by column id).
        func rank(_ record: SettingsRecord) -> (Int, Int) {
            let columns = decode([ColumnDef].self, from: record.columnsData) ?? []
            return (columns.reduce(0) { $0 + (columnUsage[$1.id] ?? 0) }, columns.count)
        }
        let best = settingsRecords.max { rank($0) < rank($1) }
        if let best {
            result.columns = decode([ColumnDef].self, from: best.columnsData) ?? []
            result.centerColumnID = best.centerColumnID
            result.graceDaysPerMonth = best.graceDaysPerMonth
            result.cheatDays = best.cheatDays
        }

        // Dual-read legacy settings blobs and granular records. This runs on
        // every load because a legacy CloudKit record may arrive at any time.
        let goalRecords = best.map { preferred in
            [preferred] + settingsRecords.filter { $0 !== preferred }
        } ?? settingsRecords
        var goalCandidates: [UUID: GoalPersistenceCandidate] = [:]
        var legacyOrder = 0
        for record in goalRecords {
            for goal in decode([GoalDefinition].self, from: record.goalsData) ?? [] {
                let candidate = GoalPersistenceCandidate(
                    definition: goal,
                    updatedAt: goal.updatedAt ?? Self.legacyVersionDate,
                    orderIndex: legacyOrder,
                    isGranular: false,
                    isTombstone: false,
                    payloadFingerprint: encode(goal).base64EncodedString(),
                    recordTieBreaker: ""
                )
                legacyOrder += 1
                if let existing = goalCandidates[goal.id] {
                    if shouldReplace(existing, with: candidate) {
                        goalCandidates[goal.id] = candidate
                    }
                } else {
                    goalCandidates[goal.id] = candidate
                }
            }
        }

        for record in granularGoalRecords {
            guard let id = UUID(uuidString: record.semanticID) else { continue }
            let isTombstone = record.tombstoned ?? false
            let definition: GoalDefinition?
            if isTombstone {
                definition = nil
            } else if let schedule = decode(GoalSchedule.self, from: record.scheduleData),
                      !record.createdOn.isEmpty {
                definition = GoalDefinition(
                    id: id,
                    title: record.title,
                    schedule: schedule,
                    createdOn: record.createdOn,
                    endsBefore: record.endsBefore,
                    impactsDaySuccess: record.impactsDaySuccess ?? true,
                    updatedAt: record.updatedAt
                )
            } else {
                // An incomplete imported physical record must not hide a
                // valid legacy definition with the same semantic id.
                continue
            }
            let payload = definition.map { encode($0).base64EncodedString() } ?? "~deleted"
            let candidate = GoalPersistenceCandidate(
                definition: definition,
                updatedAt: record.updatedAt ?? Self.legacyVersionDate,
                orderIndex: record.orderIndex,
                isGranular: true,
                isTombstone: isTombstone,
                payloadFingerprint: payload,
                recordTieBreaker: record.recordID?.uuidString ?? ""
            )
            if let existing = goalCandidates[id] {
                if shouldReplace(existing, with: candidate) {
                    goalCandidates[id] = candidate
                }
            } else {
                goalCandidates[id] = candidate
            }
        }

        let mergedGoals = goalCandidates.values
            .compactMap { candidate -> (GoalDefinition, Int)? in
                guard let definition = candidate.definition else { return nil }
                return (definition, candidate.orderIndex ?? Int.max)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                if lhs.0.createdOn != rhs.0.createdOn { return lhs.0.createdOn < rhs.0.createdOn }
                return lhs.0.id.uuidString < rhs.0.id.uuidString
            }
            .map(\.0)
        result.goals = mergedGoals.isEmpty ? nil : mergedGoals
        if result.columns.isEmpty {
            result.columns = AppData.seeded().columns
            result.centerColumnID = result.columns.last?.id
        }

        // Duplicate day records still merge food rows by id. Their legacy
        // occurrence blobs are candidates alongside the granular records.
        var occurrenceCandidates: [String: OccurrencePersistenceCandidate] = [:]
        for (record, rows) in zip(dayRecords, decodedRows) {
            if !rows.isEmpty {
                if var existing = result.days[record.dateKey] {
                    let seen = Set(existing.map(\.id))
                    existing.append(contentsOf: rows.filter { !seen.contains($0.id) })
                    result.days[record.dateKey] = existing
                } else {
                    result.days[record.dateKey] = rows
                }
            }

            let states = decode([String: GoalOccurrenceOverride].self, from: record.goalOverridesData) ?? [:]
            for (_, state) in states {
                let semanticID = "\(state.goalID.uuidString)|\(state.sourceDay)"
                let candidate = OccurrencePersistenceCandidate(
                    state: state,
                    updatedAt: state.updatedAt ?? Self.legacyVersionDate,
                    isGranular: false,
                    isTombstone: false,
                    payloadFingerprint: encode(state).base64EncodedString(),
                    recordTieBreaker: ""
                )
                if let existing = occurrenceCandidates[semanticID] {
                    if shouldReplace(existing, with: candidate) {
                        occurrenceCandidates[semanticID] = candidate
                    }
                } else {
                    occurrenceCandidates[semanticID] = candidate
                }
            }
        }

        for record in granularOccurrenceRecords {
            guard !record.semanticID.isEmpty else { continue }
            let isTombstone = record.tombstoned ?? false
            let state: GoalOccurrenceOverride?
            if isTombstone {
                state = nil
            } else if let goalID = UUID(uuidString: record.goalID),
                      let status = GoalOccurrenceStatus(rawValue: record.statusRaw),
                      !record.sourceDay.isEmpty,
                      !record.displayDay.isEmpty {
                state = GoalOccurrenceOverride(
                    goalID: goalID,
                    sourceDay: record.sourceDay,
                    displayDay: record.displayDay,
                    status: status,
                    updatedAt: record.updatedAt
                )
            } else {
                continue
            }
            let semanticID: String
            if let state {
                semanticID = "\(state.goalID.uuidString)|\(state.sourceDay)"
            } else {
                // Tombstones have no payload to canonicalize, so their stored
                // semantic id remains authoritative.
                semanticID = record.semanticID
            }
            let payload = state.map { encode($0).base64EncodedString() } ?? "~deleted"
            let candidate = OccurrencePersistenceCandidate(
                state: state,
                updatedAt: record.updatedAt ?? Self.legacyVersionDate,
                isGranular: true,
                isTombstone: isTombstone,
                payloadFingerprint: payload,
                recordTieBreaker: record.recordID?.uuidString ?? ""
            )
            if let existing = occurrenceCandidates[semanticID] {
                if shouldReplace(existing, with: candidate) {
                    occurrenceCandidates[semanticID] = candidate
                }
            } else {
                occurrenceCandidates[semanticID] = candidate
            }
        }

        // Rows typed against the starter columns before the real settings
        // arrived from iCloud: move their values onto the matching real
        // column (same name and type) so they don't silently disappear.
        let liveColumnIDs = Set(result.columns.map(\.id))
        var seedRemap: [UUID: UUID] = [:]
        for seed in AppData.seeded().columns
        where !liveColumnIDs.contains(seed.id) && columnUsage[seed.id] != nil {
            if let match = result.columns.first(where: {
                $0.type == seed.type && $0.name.caseInsensitiveCompare(seed.name) == .orderedSame
            }) {
                seedRemap[seed.id] = match.id
            }
        }
        if !seedRemap.isEmpty {
            for (key, rows) in result.days {
                result.days[key] = rows.map { row in
                    var row = row
                    for (from, to) in seedRemap {
                        guard let value = row.values.removeValue(forKey: from) else { continue }
                        if (row.values[to] ?? "").isEmpty { row.values[to] = value }
                    }
                    return row
                }
            }
        }

        // Overrides for goals that no longer exist (deleted on any device)
        // would otherwise accumulate forever.
        let liveGoalIDs = Set(mergedGoals.map(\.id))
        let mergedGoalOverrides = occurrenceCandidates
            .compactMapValues(\.state)
            .filter { liveGoalIDs.contains($0.value.goalID) }
        result.goalOverrides = mergedGoalOverrides.isEmpty ? nil : mergedGoalOverrides
        let earliestLogged = result.days
            .filter { _, rows in rows.contains { !$0.isBlank } }
            .keys.min()
        let earliestGoal = mergedGoals.map(\.createdOn).min()
        let earliestState = mergedGoalOverrides.values
            .flatMap { [$0.sourceDay, $0.displayDay] }
            .min()
        let earliestSettingsStart = settingsRecords.compactMap(\.trackingStartedOn).min()
        result.trackingStartedOn = [
            earliestSettingsStart,
            earliestLogged,
            earliestGoal,
            earliestState
        ].compactMap { $0 }.min() ?? DayKey.key(for: Date())
        return result
    }

    private func persist(_ snapshot: AppData) {
        guard let context = container?.mainContext else { return }

        let settingsRecords = (try? context.fetch(FetchDescriptor<SettingsRecord>())) ?? []
        // Untouched starter settings never get written over nothing or over
        // real columns: on a fresh install they'd compete with the settings
        // still being restored from iCloud, and a save that was pending when
        // those arrived would overwrite them. The starter columns have fixed
        // ids, so rows saved against them stay readable either way.
        let starterColumns = AppData.seeded().columns
        let storeHasRealColumns = settingsRecords.contains {
            (decode([ColumnDef].self, from: $0.columnsData) ?? []) != starterColumns
        }
        let skipStarterWrite = Self.hasStarterSettings(snapshot)
            && (settingsRecords.isEmpty || storeHasRealColumns)
        if !skipStarterWrite {
            let settings = settingsRecords.first ?? {
                let record = SettingsRecord()
                context.insert(record)
                return record
            }()
            let encodedColumns = encode(snapshot.columns)
            // Duplicate physical settings records may each carry a different
            // legacy goals blob. Keep those blobs available for migration, while
            // normalizing every other field so a refresh cannot resurrect stale
            // columns or settings from one of the retained records.
            let settingsToNormalize = settingsRecords.isEmpty ? [settings] : settingsRecords
            for settings in settingsToNormalize {
                if settings.columnsData != encodedColumns { settings.columnsData = encodedColumns }
                if settings.centerColumnID != snapshot.centerColumnID {
                    settings.centerColumnID = snapshot.centerColumnID
                }
                if settings.graceDaysPerMonth != snapshot.graceDaysPerMonth {
                    settings.graceDaysPerMonth = snapshot.graceDaysPerMonth
                }
                if settings.cheatDays != snapshot.cheatDays { settings.cheatDays = snapshot.cheatDays }
                if settings.trackingStartedOn != snapshot.trackingStartedOn {
                    settings.trackingStartedOn = snapshot.trackingStartedOn
                }
            }
        }

        // `goalsData` remains untouched as an additive CloudKit migration
        // source. Goal definitions are persisted independently below.
        // Keep duplicate settings records: a late legacy CloudKit import may
        // carry goal definitions not present in this debounced snapshot. The
        // loader already merges all physical settings records safely.

        let dayRecords = (try? context.fetch(FetchDescriptor<DayRecord>())) ?? []
        let byKey = Dictionary(grouping: dayRecords, by: \.dateKey)

        // Keep a legacy-override-only day record readable after backfill, but
        // never rewrite its occurrence blob wholesale.
        let legacyOverrideDayKeys = Set(byKey.compactMap { key, records in
            records.contains {
                !(decode([String: GoalOccurrenceOverride].self, from: $0.goalOverridesData) ?? [:]).isEmpty
            } ? key : nil
        })
        let activeDayKeys = Set(snapshot.days.keys).union(legacyOverrideDayKeys)
        for key in activeDayKeys {
            let encodedRows = encode(snapshot.days[key] ?? [])
            if let records = byKey[key], !records.isEmpty {
                let legacyRecords = records.filter {
                    !(decode([String: GoalOccurrenceOverride].self, from: $0.goalOverridesData) ?? [:]).isEmpty
                }
                let recordsToKeep = legacyRecords.isEmpty ? [records[0]] : legacyRecords
                for record in recordsToKeep where record.rowsData != encodedRows {
                    record.rowsData = encodedRows
                }
                for extra in records where !recordsToKeep.contains(where: { $0 === extra }) {
                    context.delete(extra)
                }
            } else {
                context.insert(DayRecord(
                    dateKey: key,
                    rowsData: encodedRows
                ))
            }
        }
        // Only days the user emptied on this device are deleted. Any other
        // stored day missing from this snapshot was imported after the
        // snapshot was taken (e.g. while restoring from iCloud) — deleting it
        // used to wipe restored history, and sync that deletion back up.
        for key in locallyDeletedDayKeys where !activeDayKeys.contains(key) {
            byKey[key]?.forEach(context.delete)
        }
        locallyDeletedDayKeys.removeAll()

        // Upsert each definition independently. Absence from `snapshot` is
        // never interpreted as deletion: a stale debounced snapshot may not
        // yet contain a goal imported from another device.
        let storedGoals = (try? context.fetch(FetchDescriptor<GoalDefinitionRecord>())) ?? []
        let storedGoalsByID = Dictionary(
            grouping: storedGoals.filter { !$0.semanticID.isEmpty },
            by: \.semanticID
        )
        for (orderIndex, goal) in (snapshot.goals ?? []).enumerated() {
            let semanticID = goal.id.uuidString
            let incomingPayload = encode(goal).base64EncodedString()
            let incoming = GoalPersistenceCandidate(
                definition: goal,
                updatedAt: goal.updatedAt ?? Self.legacyVersionDate,
                orderIndex: orderIndex,
                isGranular: true,
                isTombstone: false,
                payloadFingerprint: incomingPayload,
                recordTieBreaker: "~snapshot"
            )

            var latestRecord: GoalDefinitionRecord?
            var latestCandidate: GoalPersistenceCandidate?
            for record in storedGoalsByID[semanticID] ?? [] {
                let isTombstone = record.tombstoned ?? false
                let definition: GoalDefinition?
                if isTombstone {
                    definition = nil
                } else if let schedule = decode(GoalSchedule.self, from: record.scheduleData),
                          !record.createdOn.isEmpty {
                    definition = GoalDefinition(
                        id: goal.id,
                        title: record.title,
                        schedule: schedule,
                        createdOn: record.createdOn,
                        endsBefore: record.endsBefore,
                        impactsDaySuccess: record.impactsDaySuccess ?? true,
                        updatedAt: record.updatedAt
                    )
                } else {
                    continue
                }
                let payload = definition.map { encode($0).base64EncodedString() } ?? "~deleted"
                let candidate = GoalPersistenceCandidate(
                    definition: definition,
                    updatedAt: record.updatedAt ?? Self.legacyVersionDate,
                    orderIndex: record.orderIndex,
                    isGranular: true,
                    isTombstone: isTombstone,
                    payloadFingerprint: payload,
                    recordTieBreaker: record.recordID?.uuidString ?? ""
                )
                if let current = latestCandidate {
                    if shouldReplace(current, with: candidate) {
                        latestCandidate = candidate
                        latestRecord = record
                    }
                } else {
                    latestCandidate = candidate
                    latestRecord = record
                }
            }

            if let latestCandidate,
               !shouldReplace(latestCandidate, with: incoming),
               latestCandidate.definition != goal {
                // A newer (or deterministic equal-version winning) record is
                // already stored. Reload after this save will adopt it.
                continue
            }

            let record: GoalDefinitionRecord
            if let latestRecord {
                record = latestRecord
            } else {
                record = GoalDefinitionRecord(semanticID: semanticID)
                context.insert(record)
            }
            let scheduleData = encode(goal.schedule)
            if record.recordID == nil { record.recordID = UUID() }
            if record.semanticID != semanticID { record.semanticID = semanticID }
            if record.title != goal.title { record.title = goal.title }
            if record.scheduleData != scheduleData { record.scheduleData = scheduleData }
            if record.createdOn != goal.createdOn { record.createdOn = goal.createdOn }
            if record.endsBefore != goal.endsBefore { record.endsBefore = goal.endsBefore }
            if record.impactsDaySuccess != goal.impactsDaySuccess {
                record.impactsDaySuccess = goal.impactsDaySuccess
            }
            if record.orderIndex != orderIndex { record.orderIndex = orderIndex }
            if record.updatedAt != goal.updatedAt { record.updatedAt = goal.updatedAt }
            if record.tombstoned != false { record.tombstoned = false }
        }

        // Occurrence states follow the same additive upsert rule. A persisted
        // pending state is the undo tombstone and is never physically removed.
        let storedOccurrences = (try? context.fetch(FetchDescriptor<GoalOccurrenceRecord>())) ?? []
        let storedOccurrencesByID = Dictionary(
            grouping: storedOccurrences.filter { !$0.semanticID.isEmpty },
            by: \.semanticID
        )
        for (_, state) in snapshot.goalOverrides ?? [:] {
            let semanticID = "\(state.goalID.uuidString)|\(state.sourceDay)"
            let incomingPayload = encode(state).base64EncodedString()
            let incoming = OccurrencePersistenceCandidate(
                state: state,
                updatedAt: state.updatedAt ?? Self.legacyVersionDate,
                isGranular: true,
                isTombstone: false,
                payloadFingerprint: incomingPayload,
                recordTieBreaker: "~snapshot"
            )

            var latestRecord: GoalOccurrenceRecord?
            var latestCandidate: OccurrencePersistenceCandidate?
            for record in storedOccurrencesByID[semanticID] ?? [] {
                let isTombstone = record.tombstoned ?? false
                let storedState: GoalOccurrenceOverride?
                if isTombstone {
                    storedState = nil
                } else if let goalID = UUID(uuidString: record.goalID),
                          let status = GoalOccurrenceStatus(rawValue: record.statusRaw),
                          !record.sourceDay.isEmpty,
                          !record.displayDay.isEmpty {
                    storedState = GoalOccurrenceOverride(
                        goalID: goalID,
                        sourceDay: record.sourceDay,
                        displayDay: record.displayDay,
                        status: status,
                        updatedAt: record.updatedAt
                    )
                } else {
                    continue
                }
                let payload = storedState.map { encode($0).base64EncodedString() } ?? "~deleted"
                let candidate = OccurrencePersistenceCandidate(
                    state: storedState,
                    updatedAt: record.updatedAt ?? Self.legacyVersionDate,
                    isGranular: true,
                    isTombstone: isTombstone,
                    payloadFingerprint: payload,
                    recordTieBreaker: record.recordID?.uuidString ?? ""
                )
                if let current = latestCandidate {
                    if shouldReplace(current, with: candidate) {
                        latestCandidate = candidate
                        latestRecord = record
                    }
                } else {
                    latestCandidate = candidate
                    latestRecord = record
                }
            }

            if let latestCandidate,
               !shouldReplace(latestCandidate, with: incoming),
               latestCandidate.state != state {
                continue
            }

            let record: GoalOccurrenceRecord
            if let latestRecord {
                record = latestRecord
            } else {
                record = GoalOccurrenceRecord(semanticID: semanticID)
                context.insert(record)
            }
            if record.recordID == nil { record.recordID = UUID() }
            if record.semanticID != semanticID { record.semanticID = semanticID }
            let goalID = state.goalID.uuidString
            if record.goalID != goalID { record.goalID = goalID }
            if record.sourceDay != state.sourceDay { record.sourceDay = state.sourceDay }
            if record.displayDay != state.displayDay { record.displayDay = state.displayDay }
            if record.statusRaw != state.status.rawValue { record.statusRaw = state.status.rawValue }
            if record.updatedAt != state.updatedAt { record.updatedAt = state.updatedAt }
            if record.tombstoned != false { record.tombstoned = false }
        }

        if context.hasChanges { try? context.save() }

        // Rewriting an identical snapshot would still cost widget reloads on
        // every foreground and remote-change notification.
        if lastWidgetSnapshot != snapshot {
            SharedSnapshot.write(snapshot)
            lastWidgetSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func scheduleSave() {
        hasPendingSave = true
        saveTask?.cancel()
        saveGeneration &+= 1
        let generation = saveGeneration
        let snapshot = data
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.saveGeneration == generation else { return }
                self.persist(snapshot)
                self.hasPendingSave = false
                // Merge anything imported during the debounce. Granular
                // upserts never delete snapshot-absent records, so this also
                // adopts concurrently created goals without clobbering them.
                self.refreshFromCloud()
            }
        }
    }

    /// Re-reads the store (called on foreground and on CloudKit remote-change
    /// notifications). Skipped while a local edit is waiting to be saved so
    /// in-progress typing is never clobbered.
    func refreshFromCloud() {
        guard !hasPendingSave else {
            return
        }
        guard let fresh = loadFromStore() else { return }
        guard fresh != data else { return }
        isApplyingRemote = true
        data = fresh
        isApplyingRemote = false
        // Backfill legacy blobs that arrived after launch into granular
        // records. When nothing changed there is nothing to backfill.
        persist(fresh)
    }

    // MARK: - Dates

    func key(for date: Date) -> String {
        DayKey.key(for: date)
    }

    // MARK: - Rows

    func rows(on date: Date) -> [EntryRow] {
        data.rows(on: date)
    }

    @discardableResult
    func addRow(on date: Date) -> UUID {
        let row = EntryRow()
        data.days[key(for: date), default: []].append(row)
        return row.id
    }

    /// The row new input should go into: a trailing blank row is reused
    /// rather than piling up empty rows.
    func rowForNewEntry(on date: Date) -> UUID {
        if let last = rows(on: date).last, last.isBlank { return last.id }
        return addRow(on: date)
    }

    func deleteRow(_ rowID: UUID, on date: Date) {
        let k = key(for: date)
        data.days[k]?.removeAll { $0.id == rowID }
        if data.days[k]?.isEmpty == true {
            locallyDeletedDayKeys.insert(k)
            data.days.removeValue(forKey: k)
        }
    }

    func setValue(_ value: String, rowID: UUID, columnID: UUID, on date: Date) {
        let k = key(for: date)
        guard var rows = data.days[k],
              let idx = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[idx].values[columnID] = value
        data.days[k] = rows
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            if let startedOn = data.trackingStartedOn {
                if k < startedOn { data.trackingStartedOn = k }
            } else {
                data.trackingStartedOn = k
            }
        }
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

    /// Swaps a column with its neighbour; `offset` is -1 (left) or 1 (right).
    func moveColumn(_ columnID: UUID, by offset: Int) {
        guard let idx = data.columns.firstIndex(where: { $0.id == columnID }) else { return }
        let target = idx + offset
        guard data.columns.indices.contains(target) else { return }
        data.columns.swapAt(idx, target)
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

    // MARK: - Daily goals

    var goalDefinitions: [GoalDefinition] {
        data.goals ?? []
    }

    private var goalOverrideMap: [String: GoalOccurrenceOverride] {
        data.goalOverrides ?? [:]
    }

    private func goalOverrides(displayedOn dayKey: String) -> [String: GoalOccurrenceOverride] {
        if goalOverridesByDisplayDayCache == nil {
            var index: [String: [String: GoalOccurrenceOverride]] = [:]
            for (id, state) in goalOverrideMap {
                index[state.displayDay, default: [:]][id] = state
            }
            goalOverridesByDisplayDayCache = index
        }
        return goalOverridesByDisplayDayCache?[dayKey] ?? [:]
    }

    func addGoal(_ goal: GoalDefinition) {
        var goals = goalDefinitions
        goals.append(goal)
        data.goals = goals
        if let startedOn = data.trackingStartedOn {
            if goal.createdOn < startedOn { data.trackingStartedOn = goal.createdOn }
        } else {
            data.trackingStartedOn = goal.createdOn
        }
    }

    /// Applies edits to an existing goal definition. Schedule changes
    /// re-evaluate past days too — occurrence overrides survive by id.
    func updateGoal(_ goal: GoalDefinition) {
        var goals = goalDefinitions
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        var updated = goal
        updated.updatedAt = Date()
        goals[index] = updated
        data.goals = goals
        if let startedOn = data.trackingStartedOn {
            if updated.createdOn < startedOn { data.trackingStartedOn = updated.createdOn }
        } else {
            data.trackingStartedOn = updated.createdOn
        }
    }

    /// Removes a goal everywhere: from the working data, and via tombstones
    /// so CloudKit propagates the deletion instead of resurrecting it.
    func deleteGoal(_ goalID: UUID) {
        var goals = goalDefinitions
        goals.removeAll { $0.id == goalID }
        data.goals = goals.isEmpty ? nil : goals

        var overrides = goalOverrideMap
        overrides = overrides.filter { $0.value.goalID != goalID }
        data.goalOverrides = overrides.isEmpty ? nil : overrides

        tombstoneRecords(forGoal: goalID)
    }

    /// Marks the granular records for a goal (and all its occurrences) as
    /// tombstoned. A granular tombstone outranks legacy blob copies in the
    /// merge, so the deletion wins on every device.
    private func tombstoneRecords(forGoal goalID: UUID) {
        guard let context = container?.mainContext else { return }
        let semanticID = goalID.uuidString
        let now = Date()
        for record in (try? context.fetch(FetchDescriptor<GoalDefinitionRecord>())) ?? []
            where record.semanticID == semanticID {
            record.tombstoned = true
            record.updatedAt = now
            if record.recordID == nil { record.recordID = UUID() }
        }
        for record in (try? context.fetch(FetchDescriptor<GoalOccurrenceRecord>())) ?? []
            where record.goalID == semanticID {
            record.tombstoned = true
            record.updatedAt = now
            if record.recordID == nil { record.recordID = UUID() }
        }
        if context.hasChanges { try? context.save() }
    }

    /// Tombstones one occurrence record so a "back to pending" state doesn't
    /// linger as a stored row forever (pending is the default anyway).
    private func tombstoneOccurrenceRecord(semanticID: String) {
        guard let context = container?.mainContext else { return }
        let now = Date()
        for record in (try? context.fetch(FetchDescriptor<GoalOccurrenceRecord>())) ?? []
            where record.semanticID == semanticID {
            record.tombstoned = true
            record.updatedAt = now
            if record.recordID == nil { record.recordID = UUID() }
        }
        if context.hasChanges { try? context.save() }
    }

    func stopRepeatingGoal(_ goalID: UUID, after date: Date = Date()) {
        var goals = goalDefinitions
        guard let index = goals.firstIndex(where: { $0.id == goalID }),
              goals[index].schedule.kind != .oneTime,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return }
        let endsBefore = key(for: tomorrow)
        if let existingEnd = goals[index].endsBefore, existingEnd <= endsBefore { return }
        goals[index].endsBefore = endsBefore
        goals[index].updatedAt = Date()
        data.goals = goals
    }

    /// Materializes scheduled and deferred work for a date. A deferred
    /// occurrence keeps its original id, even when the same repeating goal
    /// also has a fresh occurrence on the destination day.
    func goalOccurrences(on date: Date) -> [GoalOccurrence] {
        let displayDay = key(for: date)
        return data.goalOccurrences(
            on: displayDay,
            deferredIn: goalOverrides(displayedOn: displayDay)
        )
    }

    func toggleGoalCompletion(_ occurrence: GoalOccurrence) {
        if occurrence.status == .completed {
            setOccurrencePending(occurrence)
        } else {
            var overrides = goalOverrideMap
            overrides[occurrence.id] = GoalOccurrenceOverride(
                goalID: occurrence.goal.id,
                sourceDay: occurrence.sourceDay,
                displayDay: occurrence.displayDay,
                status: .completed,
                updatedAt: Date()
            )
            data.goalOverrides = overrides
        }
    }

    /// Pending is the schedule's default state, so for an unmoved occurrence
    /// the override row is dropped (and its record tombstoned) instead of
    /// being stored forever. Deferred occurrences keep a pending override
    /// because it carries the display day.
    private func setOccurrencePending(_ occurrence: GoalOccurrence) {
        var overrides = goalOverrideMap
        if occurrence.wasDeferred {
            overrides[occurrence.id] = GoalOccurrenceOverride(
                goalID: occurrence.goal.id,
                sourceDay: occurrence.sourceDay,
                displayDay: occurrence.displayDay,
                status: .pending,
                updatedAt: Date()
            )
            data.goalOverrides = overrides
        } else {
            overrides.removeValue(forKey: occurrence.id)
            data.goalOverrides = overrides.isEmpty ? nil : overrides
            tombstoneOccurrenceRecord(semanticID: occurrence.id)
        }
    }

    func cancelGoalOccurrence(_ occurrence: GoalOccurrence) {
        var overrides = goalOverrideMap
        overrides[occurrence.id] = GoalOccurrenceOverride(
            goalID: occurrence.goal.id,
            sourceDay: occurrence.sourceDay,
            displayDay: occurrence.displayDay,
            status: .cancelled,
            updatedAt: Date()
        )
        data.goalOverrides = overrides
    }

    func restoreGoalOccurrence(_ occurrence: GoalOccurrence) {
        setOccurrencePending(occurrence)
    }

    func deferGoalOccurrence(_ occurrence: GoalOccurrence) {
        guard let currentDate = DayKey.date(from: occurrence.displayDay),
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) else { return }
        var overrides = goalOverrideMap
        overrides[occurrence.id] = GoalOccurrenceOverride(
            goalID: occurrence.goal.id,
            sourceDay: occurrence.sourceDay,
            displayDay: key(for: tomorrow),
            status: .pending,
            updatedAt: Date()
        )
        data.goalOverrides = overrides
    }

    // MARK: - Totals & goals

    func total(of column: ColumnDef, on date: Date) -> Double {
        data.total(of: column, on: date)
    }

    /// The day's medal, memoized. Grading itself lives in
    /// `AppData.dayAssessment` so the widget evaluates days identically.
    func dayAssessment(on date: Date) -> DayAssessment {
        let todayKey = DayKey.key(for: Date())
        if dayAssessmentCacheDay != todayKey {
            dayAssessmentCache.removeAll()
            dayAssessmentCacheDay = todayKey
        }
        let dayKey = key(for: date)
        if let cached = dayAssessmentCache[dayKey] { return cached }
        let assessment = data.dayAssessment(on: date, occurrences: goalOccurrences(on: date))
        dayAssessmentCache[dayKey] = assessment
        return assessment
    }

    /// True when the user logged food or completed any goal that day.
    func hasTrackedActivity(on date: Date) -> Bool {
        data.hasTrackedActivity(on: date, occurrences: goalOccurrences(on: date))
    }

    func isDaySuccessful(_ date: Date) -> Bool {
        dayAssessment(on: date).tier.countsAsSuccess
    }

    struct StreakInfo {
        var count: Int = 0
        /// Day keys whose monthly grace allowance covered them.
        var graceDays: Set<String> = []
        /// One semi-grace day in each month is bridged for free.
        var semiGraceDays: Set<String> = []
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

        // Grace can bridge gaps, so bound the walk at the first piece of
        // trackable history (food, a goal definition or a moved occurrence).
        let earliestLoggedKey = data.days
            .filter { _, rows in rows.contains { !$0.isBlank } }
            .keys.min()
        let earliestGoalKey = goalDefinitions.map(\.createdOn).min()
        let earliestOverrideKey = goalOverrideMap.values
            .flatMap { [$0.sourceDay, $0.displayDay] }
            .min()
        guard let earliestTrackedKey = [
            data.trackingStartedOn,
            earliestLoggedKey,
            earliestGoalKey,
            earliestOverrideKey
        ]
            .compactMap({ $0 }).min() else { return info }

        guard let earliestTrackedDate = DayKey.date(from: earliestTrackedKey) else { return info }
        let todayStart = cal.startOfDay(for: today)
        let yesterday = cal.date(byAdding: .day, value: -1, to: todayStart)!
        let cheat = cheatDaySet

        // Allocate the monthly allowances chronologically across all history,
        // independently of the current streak. An older streak break must not
        // reset the same calendar month's budget.
        var graceUsed: [String: Int] = [:]
        var semiGraceUsed: [String: Int] = [:]
        var assessmentsByDay: [String: DayAssessment] = [:]
        if earliestTrackedDate <= yesterday {
            var allocationDay = earliestTrackedDate
            while allocationDay <= yesterday {
                let dayKey = key(for: allocationDay)
                let assessment = dayAssessment(on: allocationDay)
                assessmentsByDay[dayKey] = assessment
                let tier = assessment.tier
                if !tier.countsAsSuccess,
                   tier != .unrated,
                   !cheat.contains(dayKey) {
                    let monthKey = String(dayKey.prefix(7))
                    if tier == .semiGrace, semiGraceUsed[monthKey, default: 0] < 1 {
                        semiGraceUsed[monthKey, default: 0] += 1
                        info.semiGraceDays.insert(dayKey)
                    } else if graceUsed[monthKey, default: 0] < graceDaysPerMonth {
                        graceUsed[monthKey, default: 0] += 1
                        info.graceDays.insert(dayKey)
                    }
                }
                allocationDay = cal.date(byAdding: .day, value: 1, to: allocationDay)!
            }
        }

        var day = todayStart
        // Today doesn't consume grace or break the streak while in progress.
        if dayAssessment(on: day).tier.countsAsSuccess {
            info.count += 1
        }
        day = cal.date(byAdding: .day, value: -1, to: day)!

        while key(for: day) >= earliestTrackedKey {
            let dayKey = key(for: day)
            let tier = (assessmentsByDay[dayKey] ?? dayAssessment(on: day)).tier
            if tier.countsAsSuccess {
                info.count += 1
            } else if cheat.contains(dayKey)
                        || tier == .unrated
                        || info.semiGraceDays.contains(dayKey)
                        || info.graceDays.contains(dayKey) {
                // Bridged or neutral — it does not add to the streak.
            } else {
                break
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
        saveGeneration &+= 1
        saveTask?.cancel()
        saveTask = nil
        hasPendingSave = false
        locallyDeletedDayKeys.removeAll()
        if let context = container?.mainContext {
            try? context.delete(model: DayRecord.self)
            try? context.delete(model: SettingsRecord.self)
            try? context.delete(model: GoalDefinitionRecord.self)
            try? context.delete(model: GoalOccurrenceRecord.self)
            try? context.save()
        }
        isApplyingRemote = true
        data = AppData.seeded()
        isApplyingRemote = false
        persist(data)
    }
}
