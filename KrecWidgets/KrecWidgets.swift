import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration intent (long-press → Edit Widget)

struct ColumnEntity: AppEntity {
    var id: UUID
    var name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Column"
    static let defaultQuery = ColumnQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ColumnQuery: EntityQuery {
    private func all() -> [ColumnEntity] {
        (SharedSnapshot.read()?.numericColumns ?? []).map {
            ColumnEntity(id: $0.id, name: $0.name)
        }
    }

    func entities(for identifiers: [UUID]) async throws -> [ColumnEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ColumnEntity] {
        all()
    }
}

struct KrecWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Krec"
    static let description = IntentDescription("Choose which columns to show.")

    @Parameter(title: "Columns to show")
    var columns: [ColumnEntity]?

    @Parameter(title: "Center number")
    var center: ColumnEntity?
}

// MARK: - Timeline

struct WidgetColumn: Identifiable {
    let def: ColumnDef
    let total: Double
    var id: UUID { def.id }

    var fraction: Double {
        guard let target = def.ringTarget, target > 0 else { return 0 }
        return min(total / target, 1)
    }
}

struct ColumnsEntry: TimelineEntry {
    let date: Date
    let columns: [WidgetColumn]
    let centerID: UUID?

    var center: WidgetColumn? {
        columns.first { $0.id == centerID } ?? columns.first
    }

    static var placeholder: ColumnsEntry {
        let kcal = ColumnDef(name: "Kcal", type: .number, minGoal: nil, maxGoal: 2000, colorHex: "FF9F0A")
        let protein = ColumnDef(name: "Protein", type: .number, minGoal: 100, maxGoal: nil, colorHex: "FF375F")
        return ColumnsEntry(
            date: Date(),
            columns: [
                WidgetColumn(def: kcal, total: 1450),
                WidgetColumn(def: protein, total: 82),
            ],
            centerID: kcal.id
        )
    }
}

struct Provider: AppIntentTimelineProvider {
    private func entry(for configuration: KrecWidgetIntent) -> ColumnsEntry {
        guard let snapshot = SharedSnapshot.read() else { return .placeholder }
        let numeric = snapshot.numericColumns

        let chosen: [ColumnDef]
        if let selected = configuration.columns, !selected.isEmpty {
            chosen = selected.compactMap { entity in numeric.first { $0.id == entity.id } }
        } else {
            chosen = numeric
        }

        let now = Date()
        let dayKey = DayKey.key(for: now)
        let columns = chosen.map {
            WidgetColumn(def: $0.resolved(on: dayKey), total: snapshot.total(of: $0, on: now))
        }
        let centerID = configuration.center.flatMap { entity in
            columns.first { $0.id == entity.id }?.id
        }
        return ColumnsEntry(date: now, columns: columns, centerID: centerID)
    }

    func placeholder(in context: Context) -> ColumnsEntry {
        .placeholder
    }

    func snapshot(for configuration: KrecWidgetIntent, in context: Context) async -> ColumnsEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: KrecWidgetIntent, in context: Context) async -> Timeline<ColumnsEntry> {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
        return Timeline(entries: [entry(for: configuration)], policy: .after(midnight))
    }
}

// MARK: - Widget

struct KrecWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "KrecWidget",
            intent: KrecWidgetIntent.self,
            provider: Provider()
        ) { entry in
            KrecWidgetView(entry: entry)
                .containerBackground(Color.black, for: .widget)
        }
        .configurationDisplayName("Krec")
        .description("Your rings and daily totals.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct KrecWidgetsBundle: WidgetBundle {
    var body: some Widget {
        KrecWidget()
    }
}
