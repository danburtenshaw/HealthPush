import SwiftUI

// MARK: - ActivityHeatmapDay

/// A single cell in the 90-day activity heatmap.
struct ActivityHeatmapDay: Identifiable {
    let id = UUID()
    /// The calendar day this cell represents.
    let date: Date
    /// Number of successful syncs that day. Failures live in ``failureCount``.
    let successCount: Int
    /// Number of failed syncs that day — tints the cell red when > 0.
    let failureCount: Int

    /// Total activity count used for intensity bucketing.
    var total: Int {
        successCount + failureCount
    }
}

// MARK: - ActivityHeatmap

/// A GitHub-style 90-day activity heatmap. Laid out as 13 columns × 7 rows,
/// oldest cell top-left, today bottom-right, with summary stats underneath.
///
/// Accent-colored cells mean syncs succeeded; red tint means a failure landed
/// on that day. The card is the history screen's "is this app actually
/// running?" at-a-glance signal.
struct ActivityHeatmap: View {
    // MARK: Properties

    let days: [ActivityHeatmapDay]
    /// When set, the caller can react to taps on a specific day (e.g. filter
    /// the log list below). Pass nil for a non-interactive heatmap.
    var onDayTapped: ((ActivityHeatmapDay) -> Void)?
    /// Highlighted day (drawn with a ring). Use to reflect external filter state.
    var selectedDay: Date?

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
            header
            grid
            dateAxis
            Divider().opacity(0.5)
            statsRow
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
            Text("90-day activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer()
            Text(headerDateString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var grid: some View {
        // Pad the start so today is always the last cell in the grid.
        let emptyPadding = Self.columns * Self.rows - days.count
        let cells: [ActivityHeatmapDay?] = Array(repeating: nil, count: max(emptyPadding, 0))
            + days.map(Optional.init)

        return GeometryReader { geometry in
            let gap: CGFloat = 3
            // Cells size to fit both dimensions. The container sets its own
            // aspect ratio below, so both axes converge; taking min() here
            // guarantees we don't overflow vertically when the container is
            // slightly taller than the nominal ratio on any given device.
            let cellFromWidth = (geometry.size.width - CGFloat(Self.columns - 1) * gap) / CGFloat(Self.columns)
            let cellFromHeight = (geometry.size.height - CGFloat(Self.rows - 1) * gap) / CGFloat(Self.rows)
            let cell = max(min(cellFromWidth, cellFromHeight), 6)

            VStack(spacing: gap) {
                ForEach(0..<Self.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<Self.columns, id: \.self) { col in
                            // Column-major ordering: top-to-bottom, left-to-right.
                            let index = col * Self.rows + row
                            HeatmapCell(
                                day: cells.indices.contains(index) ? cells[index] : nil,
                                size: cell,
                                isSelected: cells.indices.contains(index)
                                    ? isSelected(cells[index])
                                    : false
                            )
                            .onTapGesture {
                                guard cells.indices.contains(index), let day = cells[index] else { return }
                                onDayTapped?(day)
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        // 13:7 column-to-row aspect ratio, plus a small extra slice for the
        // gap budget. Without this, the outer frame height was hard-coded
        // from an assumed 18pt cell size and the bottom row bled into the
        // "3 months ago / today" axis below on real device widths.
        .aspectRatio(CGFloat(Self.columns) / CGFloat(Self.rows), contentMode: .fit)
    }

    private var dateAxis: some View {
        HStack {
            Text("3 months ago")
            Spacer()
            Text("today")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
    }

    private var statsRow: some View {
        HStack(spacing: HP.Spacing.xxl) {
            stat(label: "Syncs", value: totalSyncs, tone: .accent)
            stat(label: "Active days", value: activeDayCount, tone: .accent)
            stat(label: "Failures", value: totalFailures, tone: totalFailures > 0 ? .error : .neutral)
        }
    }

    private func stat(label: String, value: Int, tone: StatTone) -> some View {
        VStack(alignment: .leading, spacing: HP.Spacing.xs) {
            HStack(spacing: HP.Spacing.xs) {
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }
            Text(value, format: .number)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private func isSelected(_ day: ActivityHeatmapDay?) -> Bool {
        guard let day, let selectedDay else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDay)
    }

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d · yyyy"
        return formatter.string(from: .now)
    }

    private var totalSyncs: Int {
        days.reduce(0) { $0 + $1.successCount }
    }

    private var totalFailures: Int {
        days.reduce(0) { $0 + $1.failureCount }
    }

    private var activeDayCount: Int {
        days.count(where: { $0.total > 0 })
    }

    private var accessibilityLabel: String {
        "90-day sync activity heatmap. \(totalSyncs) successful syncs across \(activeDayCount) active days. \(totalFailures) failures."
    }

    // MARK: Layout constants

    /// Columns in the heatmap grid. 90 days fits comfortably in 13 × 7 = 91 cells.
    private static let columns = 13
    private static let rows = 7
}

// MARK: - HeatmapCell

private struct HeatmapCell: View {
    let day: ActivityHeatmapDay?
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                // A single failure among many successes shouldn't repaint the
                // whole cell red — that overstates the day's health. Keep the
                // accent fill and put a small red corner marker so failures
                // are still discoverable at a glance.
                if let day, day.failureCount > 0, day.successCount > 0 {
                    failureMarker
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 1.5)
                }
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var failureMarker: some View {
        Circle()
            .fill(Color.red)
            .frame(width: max(size * 0.32, 4), height: max(size * 0.32, 4))
            .padding(1.5)
    }

    private var fill: AnyShapeStyle {
        guard let day else { return AnyShapeStyle(Color.clear) }

        // Only-failures day: paint red so the reader sees "this day was bad"
        // without relying on the marker alone.
        if day.successCount == 0 && day.failureCount > 0 {
            return AnyShapeStyle(Color.red.opacity(intensity(for: day.failureCount)))
        }
        if day.successCount == 0 {
            return AnyShapeStyle(Color.primary.opacity(0.06))
        }
        return AnyShapeStyle(Color.accentColor.opacity(intensity(for: day.successCount)))
    }

    /// Intensity buckets keep the heatmap readable when counts are noisy.
    private func intensity(for count: Int) -> Double {
        switch count {
        case 0: 0
        case 1...3: 0.25
        case 4...10: 0.45
        case 11...20: 0.65
        case 21...35: 0.85
        default: 1.0
        }
    }

    private var accessibilityLabel: String {
        guard let day else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let date = formatter.string(from: day.date)
        if day.failureCount > 0 && day.successCount > 0 {
            return "\(date): \(day.successCount) successful, \(day.failureCount) failed."
        }
        if day.failureCount > 0 {
            return "\(date): \(day.failureCount) failed."
        }
        if day.successCount == 0 {
            return "\(date): no syncs."
        }
        return "\(date): \(day.successCount) syncs."
    }
}

private enum StatTone {
    case accent
    case error
    case neutral

    var color: Color {
        switch self {
        case .accent: Color.accentColor
        case .error: .red
        case .neutral: .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    ActivityHeatmap(days: ActivityHeatmapDay.previewData)
        .padding()
        .background(Color(.systemGroupedBackground))
}

extension ActivityHeatmapDay {
    static var previewData: [ActivityHeatmapDay] {
        let calendar = Calendar.current
        return (0..<90).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -(89 - offset), to: .now) else { return nil }
            let successes = offset % 7 == 3 ? 0 : Int.random(in: 0...30)
            let failures = offset % 20 == 0 && offset > 0 ? 1 : 0
            return ActivityHeatmapDay(date: date, successCount: successes, failureCount: failures)
        }
    }
}
