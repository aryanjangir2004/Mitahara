import Foundation
import SwiftData

// CloudKit-backed SwiftData models. All properties have defaults and there are
// no unique constraints — both are CloudKit requirements. The flexible column
// schema lives inside encoded JSON blobs so the sync layer never needs to know
// about user-defined columns.

@Model
final class DayRecord {
    var dateKey: String = ""      // "yyyy-MM-dd"
    var rowsData: Data = Data()   // JSON-encoded [EntryRow]
    // Legacy migration source. New occurrence state writes use one
    // GoalOccurrenceRecord per semantic occurrence id.
    var goalOverridesData: Data = Data() // JSON-encoded occurrence states

    init(dateKey: String = "", rowsData: Data = Data(), goalOverridesData: Data = Data()) {
        self.dateKey = dateKey
        self.rowsData = rowsData
        self.goalOverridesData = goalOverridesData
    }
}

@Model
final class SettingsRecord {
    var columnsData: Data = Data()   // JSON-encoded [ColumnDef]
    var centerColumnID: UUID?
    var graceDaysPerMonth: Int?
    var cheatDays: [String]?
    var trackingStartedOn: String?
    // Legacy migration source. New goal writes use one GoalDefinitionRecord
    // per semantic goal id so unrelated goals cannot overwrite one another.
    var goalsData: Data = Data()     // JSON-encoded [GoalDefinition]

    init(
        columnsData: Data = Data(),
        centerColumnID: UUID? = nil,
        graceDaysPerMonth: Int? = nil,
        cheatDays: [String]? = nil,
        trackingStartedOn: String? = nil,
        goalsData: Data = Data()
    ) {
        self.columnsData = columnsData
        self.centerColumnID = centerColumnID
        self.graceDaysPerMonth = graceDaysPerMonth
        self.cheatDays = cheatDays
        self.trackingStartedOn = trackingStartedOn
        self.goalsData = goalsData
    }
}

/// A single goal definition stored independently for conflict isolation.
/// `semanticID` is intentionally not a SwiftData unique attribute because
/// CloudKit-backed models cannot use uniqueness constraints. Duplicate
/// physical records are merged by `updatedAt` when loading.
@Model
final class GoalDefinitionRecord {
    /// Physical-record tie breaker for deterministic duplicate merging.
    var recordID: UUID? = UUID()
    var semanticID: String = ""       // GoalDefinition.id.uuidString
    var title: String = ""
    var scheduleData: Data = Data()   // JSON-encoded GoalSchedule
    var createdOn: String = ""        // "yyyy-MM-dd"
    var endsBefore: String?
    var impactsDaySuccess: Bool? = true
    var orderIndex: Int?
    var updatedAt: Date?
    /// Reserved deletion tombstone. Retiring a repeating goal normally uses
    /// `endsBefore`, preserving its historical occurrences.
    var tombstoned: Bool? = false

    init(
        recordID: UUID? = UUID(),
        semanticID: String = "",
        title: String = "",
        scheduleData: Data = Data(),
        createdOn: String = "",
        endsBefore: String? = nil,
        impactsDaySuccess: Bool? = true,
        orderIndex: Int? = nil,
        updatedAt: Date? = nil,
        tombstoned: Bool? = false
    ) {
        self.recordID = recordID
        self.semanticID = semanticID
        self.title = title
        self.scheduleData = scheduleData
        self.createdOn = createdOn
        self.endsBefore = endsBefore
        self.impactsDaySuccess = impactsDaySuccess
        self.orderIndex = orderIndex
        self.updatedAt = updatedAt
        self.tombstoned = tombstoned
    }
}

/// A completion/cancellation/deferral override for one scheduled occurrence.
/// Pending is persisted too: it is the neutral tombstone that prevents an
/// older completed or cancelled state from being resurrected after sync.
@Model
final class GoalOccurrenceRecord {
    /// Physical-record tie breaker for deterministic duplicate merging.
    var recordID: UUID? = UUID()
    var semanticID: String = ""       // "goal UUID|source day"
    var goalID: String = ""           // GoalDefinition.id.uuidString
    var sourceDay: String = ""         // stable scheduled day
    var displayDay: String = ""        // changes when deferred
    var statusRaw: String = GoalOccurrenceStatus.pending.rawValue
    var updatedAt: Date?
    /// Reserved deletion tombstone. Normal restores use `statusRaw=pending`.
    var tombstoned: Bool? = false

    init(
        recordID: UUID? = UUID(),
        semanticID: String = "",
        goalID: String = "",
        sourceDay: String = "",
        displayDay: String = "",
        statusRaw: String = GoalOccurrenceStatus.pending.rawValue,
        updatedAt: Date? = nil,
        tombstoned: Bool? = false
    ) {
        self.recordID = recordID
        self.semanticID = semanticID
        self.goalID = goalID
        self.sourceDay = sourceDay
        self.displayDay = displayDay
        self.statusRaw = statusRaw
        self.updatedAt = updatedAt
        self.tombstoned = tombstoned
    }
}
