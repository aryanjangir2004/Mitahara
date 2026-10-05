import SwiftUI
import WidgetKit

struct KrecWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ColumnsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallRingsView(entry: entry)
        case .systemMedium:
            MediumLinesView(entry: entry)
        default:
            LargeGaugeView(entry: entry)
        }
    }
}

// MARK: - Medal helpers

extension ColumnsEntry {
    /// Whether the day has anything medal-worthy to show at all.
    var showsMedal: Bool {
        isCheatDay || tier != .unrated
    }

    /// The widget always grades today, which is still running — so an
    /// unmet day reads as a neutral "no medal yet", not a red miss (same
    /// as the app's top-bar chip).
    var medalSymbol: String {
        if isCheatDay { return "star.fill" }
        return tier == .missed ? "medal" : tier.symbol
    }

    var medalColor: Color {
        if isCheatDay { return .orange }
        return tier == .missed ? .white.opacity(0.45) : tier.color
    }

    var medalTitle: String {
        if isCheatDay { return "Cheat day" }
        switch tier {
        case .gold: return "Gold day"
        case .silver: return "Silver day"
        case .bronze: return "Bronze day"
        case .semiGrace: return "Semi-grace"
        case .missed: return "No medal yet"
        case .unrated: return "Open day"
        }
    }
}

// MARK: - Shared arc shape

struct WidgetArcShape: Shape {
    var progress: Double
    var radiusInset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2, rect.height) - radiusInset
        guard radius > 0, progress > 0 else { return path }
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(180 + 180 * min(progress, 1)),
            clockwise: false
        )
        return path
    }
}

private struct RingsStack: View {
    let columns: [WidgetColumn]
    let strokeWidth: CGFloat
    let gap: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                let inset = strokeWidth / 2 + CGFloat(index) * (strokeWidth + gap)
                WidgetArcShape(progress: 1, radiusInset: inset)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                WidgetArcShape(progress: column.fraction, radiusInset: inset)
                    .stroke(
                        column.def.color,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
            }
        }
    }
}

// MARK: - Small: rings + one number

struct SmallRingsView: View {
    let entry: ColumnsEntry

    private var ringColumns: [WidgetColumn] {
        Array(entry.columns.filter { $0.def.ringTarget != nil }.prefix(3))
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let stroke = side * 0.08
            let gap = side * 0.03
            // Free radius inside the innermost ring — the number must fit here.
            let innerRadius = side / 2 - CGFloat(max(ringColumns.count, 1)) * (stroke + gap)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    RingsStack(columns: ringColumns, strokeWidth: stroke, gap: gap)
                    if let center = entry.center {
                        VStack(spacing: -1) {
                            Text(center.total.compactString)
                                .font(.system(size: innerRadius * 0.55, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                            Text(center.def.name)
                                .font(.system(size: max(innerRadius * 0.22, 8), weight: .semibold, design: .rounded))
                                .foregroundStyle(center.def.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: max(innerRadius * 1.75, 44))
                    }
                }
                .frame(width: side, height: side * 0.56)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topTrailing) {
                if entry.showsMedal {
                    Image(systemName: entry.medalSymbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(entry.medalColor)
                }
            }
        }
    }
}

// MARK: - Medium: lines with totals

struct MediumLinesView: View {
    let entry: ColumnsEntry

    var body: some View {
        HStack(spacing: 14) {
            linesStack

            if entry.showsMedal || entry.goalsTotal > 0 {
                VStack(spacing: 3) {
                    Image(systemName: entry.medalSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(entry.medalColor)
                    if entry.goalsTotal > 0 {
                        Text("\(entry.goalsDone)/\(entry.goalsTotal)")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36)
            }
        }
    }

    private var linesStack: some View {
        VStack(spacing: 12) {
            ForEach(entry.columns.prefix(3)) { column in
                HStack(spacing: 10) {
                    Text(column.def.name)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(column.def.color)
                                .frame(width: max(geo.size.width * column.fraction, column.fraction > 0 ? 10 : 0))
                        }
                    }
                    .frame(height: 10)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(column.total.compactString)
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(column.def.goalText)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 66, alignment: .trailing)
                    .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Large: gauge on top, totals below

struct LargeGaugeView: View {
    let entry: ColumnsEntry

    private var ringColumns: [WidgetColumn] {
        Array(entry.columns.filter { $0.def.ringTarget != nil }.prefix(5))
    }

    var body: some View {
        VStack(spacing: 12) {
            if entry.showsMedal || entry.goalsTotal > 0 {
                HStack(spacing: 7) {
                    Image(systemName: entry.medalSymbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(entry.medalColor)
                    Text(entry.medalTitle)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if entry.goalsTotal > 0 {
                        Text("\(entry.goalsDone)/\(entry.goalsTotal) goals")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ZStack(alignment: .bottom) {
                RingsStack(columns: ringColumns, strokeWidth: 11, gap: 5)
                if let center = entry.center {
                    VStack(spacing: 0) {
                        Text(center.total.compactString)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(center.def.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(center.def.color)
                    }
                    .padding(.horizontal, 60)
                }
            }
            .frame(height: 118)

            VStack(spacing: 8) {
                ForEach(entry.columns.prefix(6)) { column in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(column.def.color)
                            .frame(width: 7, height: 7)
                        Text(column.def.name)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(column.def.goalText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(column.total.compactString)
                            .font(.system(.callout, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        if let met = (column.def.hasGoal && column.def.countsInSuccess)
                            ? (entry.hasTrackedActivity && column.def.isMet(total: column.total) == true)
                            : nil {
                            Image(systemName: met ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.caption)
                                .foregroundStyle(met ? .green : .secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
