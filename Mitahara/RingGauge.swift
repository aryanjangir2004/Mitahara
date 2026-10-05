import SwiftUI

/// One semicircular arc (180° sweep across the top).
struct SemiArcShape: Shape {
    var progress: Double
    var radiusInset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

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

struct RingGauge: View {
    let columns: [ColumnDef]          // numeric columns with a ring target, outermost first
    let totals: [UUID: Double]
    let centerColumn: ColumnDef?
    let animateIn: Bool
    /// Number of columns the center can show, and which one it shows now —
    /// drawn as page dots so tapping to switch is discoverable.
    var centerChoices = 1
    var centerIndex = 0

    private let strokeWidth: CGFloat = 16
    private let gap: CGFloat = 7

    private func progress(for column: ColumnDef) -> Double {
        guard let target = column.ringTarget, target > 0 else { return 0 }
        return (totals[column.id] ?? 0) / target
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .bottom) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    let inset = strokeWidth / 2 + CGFloat(index) * (strokeWidth + gap)
                    // Track
                    SemiArcShape(progress: 1, radiusInset: inset)
                        .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    // Progress
                    SemiArcShape(progress: animateIn ? progress(for: column) : 0, radiusInset: inset)
                        .stroke(
                            LinearGradient(
                                colors: [column.color.opacity(0.65), column.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .shadow(color: column.color.opacity(0.45), radius: 6)
                        .animation(
                            .spring(response: 1.0, dampingFraction: 0.85).delay(0.15 + Double(index) * 0.12),
                            value: animateIn
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: progress(for: column))
                }

                centerLabel
                    .padding(.bottom, 2)
                    .frame(maxWidth: size.width - 2 * CGFloat(columns.count) * (strokeWidth + gap) - 40)
            }
            .frame(width: size.width, height: size.height, alignment: .bottom)
        }
    }

    /// How far the center column is from its target, e.g. "500 left".
    private func remaining(for column: ColumnDef, total: Double) -> (text: String, color: Color)? {
        switch (column.minGoal, column.maxGoal) {
        case (nil, nil):
            return nil
        case let (lo?, nil):
            return total >= lo
                ? ("Target reached", .green)
                : ("\((lo - total).compactString) to go", .secondary)
        case let (lo, hi?):
            if let lo, total < lo {
                return ("\((lo - total).compactString) to go", .secondary)
            }
            return total <= hi
                ? ("\((hi - total).compactString) left", .secondary)
                : ("\((total - hi).compactString) over", Color(red: 1, green: 0.42, blue: 0.42))
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let column = centerColumn {
            let total = totals[column.id] ?? 0
            VStack(spacing: 2) {
                Text(total.compactString)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(column.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(column.color)
                if let remaining = remaining(for: column, total: total) {
                    Text(remaining.text)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(remaining.color)
                        .contentTransition(.numericText())
                }
                if centerChoices > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<centerChoices, id: \.self) { i in
                            Circle()
                                .fill(Color.white.opacity(i == centerIndex ? 0.8 : 0.22))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.top, 4)
                    .accessibilityHidden(true)
                }
            }
        } else {
            Text("Add a number column")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
