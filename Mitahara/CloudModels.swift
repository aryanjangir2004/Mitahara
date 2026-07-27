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

    init(dateKey: String = "", rowsData: Data = Data()) {
        self.dateKey = dateKey
        self.rowsData = rowsData
    }
}

@Model
final class SettingsRecord {
    var columnsData: Data = Data()   // JSON-encoded [ColumnDef]
    var centerColumnID: UUID?
    var graceDaysPerMonth: Int?
    var cheatDays: [String]?

    init(columnsData: Data = Data(), centerColumnID: UUID? = nil, graceDaysPerMonth: Int? = nil, cheatDays: [String]? = nil) {
        self.columnsData = columnsData
        self.centerColumnID = centerColumnID
        self.graceDaysPerMonth = graceDaysPerMonth
        self.cheatDays = cheatDays
    }
}
