import SwiftUI

// MARK: - DataPointsSparkline

/// A 7-day activity card showing total data points synced per day, with today's
/// total called out in monospaced tnum and a comparison pill against the weekly
/// average. Bars use the accent color for today and a muted fill for prior days.
///
/// The card is the Dashboard's at-a-glance "Is sync alive?" signal — a filled
/// rightmost bar means data went somewhere today; a thin stub means the sync
/// ran but carried little new data; a missing bar means a gap.
struct DataPointsSparkline: View {
    // MARK: Properties

    /// Points per day, oldest-first. Must have exactly 7 entries for the label row.
    let dailyTotals: [Int]
    /// Weekday labels, oldest-first (e.g. `["Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"]`).
    let weekdayLabels: [String]

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
            header
            chart
            labelRow
        }
        .padding(HP.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: HP.Spacing.xs) {
                Text("Data points synced")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                HStack(alignment: .firstTextBaseline, spacing: HP.Spacing.md) {
                    Text(todayValue, format: .number)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: todayValue)

                    Text("today")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: HP.Spacing.lg)

            comparisonPill
        }
    }

    @ViewBuilder
    private var comparisonPill: some View {
        if let delta = percentVsAverage {
            let isUp = delta >= 0
            Label(
                "\(isUp ? "+" : "")\(delta)% vs avg",
                systemImage: isUp ? "arrow.up.right" : "arrow.down.right"
            )
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isUp ? Color.green : Color.secondary)
            .padding(.horizontal, HP.Spacing.md)
            .padding(.vertical, HP.Spacing.xs)
            .background {
                Capsule().fill((isUp ? Color.green : Color.secondary).opacity(0.12))
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            let barCount = max(dailyTotals.count, 1)
            let gap: CGFloat = 6
            let totalGap = CGFloat(barCount - 1) * gap
            let barWidth = max((geometry.size.width - totalGap) / CGFloat(barCount), 2)
            let maxValue = max(dailyTotals.max() ?? 0, 1)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(dailyTotals.enumerated()), id: \.offset) { index, value in
                    bar(for: value, maxValue: maxValue, isToday: index == dailyTotals.count - 1)
                        .frame(width: barWidth)
                }
            }
            .frame(height: geometry.size.height, alignment: .bottom)
        }
        .frame(height: 64)
    }

    private func bar(for value: Int, maxValue: Int, isToday: Bool) -> some View {
        let proportion = CGFloat(value) / CGFloat(maxValue)
        return GeometryReader { geometry in
            let height = max(geometry.size.height * proportion, 2)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isToday ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var labelRow: some View {
        HStack {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Computed

    private var todayValue: Int {
        dailyTotals.last ?? 0
    }

    /// Percent change of today's count vs the average of the prior 6 days, or
    /// nil when there isn't enough history to compare against.
    private var percentVsAverage: Int? {
        guard dailyTotals.count >= 2 else { return nil }
        let history = dailyTotals.dropLast()
        guard !history.isEmpty else { return nil }
        let average = Double(history.reduce(0, +)) / Double(history.count)
        guard average > 0 else { return nil }
        let delta = (Double(todayValue) - average) / average * 100
        return Int(delta.rounded())
    }

    private var accessibilityLabel: String {
        var parts = ["\(todayValue) data points synced today."]
        if let delta = percentVsAverage {
            parts.append("\(delta >= 0 ? "Up" : "Down") \(abs(delta)) percent versus the weekly average.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Preview

#Preview {
    VStack {
        DataPointsSparkline(
            dailyTotals: [1284, 1492, 1350, 1610, 980, 1725, 1523],
            weekdayLabels: ["Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"]
        )
        DataPointsSparkline(
            dailyTotals: [0, 0, 0, 0, 0, 0, 0],
            weekdayLabels: ["Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Thu"]
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
