import SwiftData
import SwiftUI

// MARK: - SyncHistoryScreen

/// Screen displaying a chronological log of past sync operations with a stacked bar chart,
/// status filters, search, and tappable rows linking to detail views.
struct SyncHistoryScreen: View {
    // MARK: Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SyncRecord.timestamp, order: .reverse)
    private var syncRecords: [SyncRecord]

    /// If set, the screen pushes that record's detail view onto the navigation
    /// stack on first appearance. Used by the dashboard nudge so tapping
    /// "Review" lands on the failed record directly.
    var initialRecordID: UUID?

    @State private var selectedFilter: SyncHistoryFilter = .all
    @State private var selectedDestinationName: String?
    @State private var searchText = ""
    @State private var selectedChartDay: Date?
    @State private var navigationPath: [UUID] = []

    // MARK: Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            recordList
                .navigationTitle("Sync History")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if let initialRecordID, navigationPath.isEmpty {
                        navigationPath.append(initialRecordID)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    // MARK: Subviews

    private var recordList: some View {
        List {
            if !heatmapDays.isEmpty {
                heatmapSection
            }

            filterPillsSection

            // Day-filter affordance. Lives outside `recordList`'s conditional
            // sections so it stays reachable even when the selected day has
            // zero records — otherwise tapping a quiet cell would strand the
            // user with an empty list and no way back.
            if let selectedDay = selectedChartDay {
                selectedDayBanner(selectedDay)
            }

            if filteredRecords.isEmpty {
                emptyStateSection
            } else {
                ForEach(groupedByDate, id: \.key) { dateKey, records in
                    Section(dateKey) {
                        ForEach(records) { record in
                            NavigationLink(value: record.id) {
                                SyncRecordRow(record: record)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search by destination or error")
        .navigationDestination(for: UUID.self) { recordID in
            if let record = syncRecords.first(where: { $0.id == recordID }) {
                SyncRecordDetailView(record: record)
            }
        }
    }

    private var filterPillsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HP.Spacing.md) {
                    ForEach(SyncHistoryFilter.allCases) { filter in
                        FilterPill(
                            title: filter.displayName,
                            icon: filter.icon,
                            isActive: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedFilter = filter
                            }
                        }
                    }

                    // Per-destination pills appear only when there's more than
                    // one destination in the history — otherwise they're just
                    // noise duplicating the "All" state.
                    if destinationNames.count > 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 0.5, height: 20)
                            .padding(.horizontal, HP.Spacing.xs)

                        ForEach(destinationNames, id: \.self) { name in
                            FilterPill(
                                title: name,
                                icon: nil,
                                isActive: selectedDestinationName == name
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDestinationName = selectedDestinationName == name ? nil : name
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, HP.Spacing.xl)
                .padding(.vertical, HP.Spacing.sm)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// Distinct destination names present in the current record set, sorted so
    /// the pill order is stable across renders.
    private var destinationNames: [String] {
        Set(syncRecords.map(\.destinationName)).sorted()
    }

    private func selectedDayBanner(_ day: Date) -> some View {
        Section {
            Button {
                withAnimation { selectedChartDay = nil }
            } label: {
                HStack {
                    Label {
                        Text("Filtered to ") + Text(day, style: .date).fontWeight(.semibold)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    Spacer()
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .accessibilityHint("Removes the selected-day filter")
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "clock.arrow.circlepath")
            } description: {
                Text(emptyMessage)
            }
            .listRowBackground(Color.clear)
        }
    }

    private var emptyTitle: String {
        if selectedChartDay != nil { return "No Syncs That Day" }
        return "No Sync History"
    }

    private var emptyMessage: String {
        if selectedChartDay != nil {
            return "Tap the heatmap above to pick a different day, or clear the filter."
        }
        if selectedFilter == .all && searchText.isEmpty {
            return "Sync history will appear here after your first sync."
        }
        return "No syncs match the selected filter or search."
    }

    private var heatmapSection: some View {
        Section {
            ActivityHeatmap(
                days: heatmapDays,
                onDayTapped: { day in
                    withAnimation {
                        let startOfDay = Calendar.current.startOfDay(for: day.date)
                        selectedChartDay = selectedChartDay == startOfDay ? nil : startOfDay
                    }
                },
                selectedDay: selectedChartDay
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: Data

    private var filteredRecords: [SyncRecord] {
        var records: [SyncRecord] = switch selectedFilter {
        case .all:
            syncRecords
        case .success:
            // Treat deferred as informational success — the user took no action;
            // the next sync will pick up automatically.
            syncRecords.filter { $0.status == .success || $0.status == .deferred }
        case .failed:
            syncRecords.filter { $0.status == .failure || $0.status == .partialFailure }
        case .background:
            syncRecords.filter(\.isBackgroundSync)
        }

        if let name = selectedDestinationName {
            records = records.filter { $0.destinationName == name }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            records = records.filter { record in
                record.destinationName.lowercased().contains(query)
                    || (record.errorMessage?.lowercased().contains(query) ?? false)
            }
        }

        if let selectedDay = selectedChartDay {
            let calendar = Calendar.current
            records = records.filter { record in
                calendar.isDate(record.timestamp, inSameDayAs: selectedDay)
            }
        }

        return records
    }

    private var groupedByDate: [(key: String, value: [SyncRecord])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: filteredRecords) { record in
            formatter.string(from: record.timestamp)
        }

        return grouped
            .sorted { lhs, rhs in
                guard let lhsDate = lhs.value.first?.timestamp,
                      let rhsDate = rhs.value.first?.timestamp
                else {
                    return false
                }
                return lhsDate > rhsDate
            }
    }

    // MARK: Heatmap Data

    /// 90-day activity buckets used by ``ActivityHeatmap``. Oldest day first.
    ///
    /// The calendar walk runs unconditionally so the heatmap always renders a
    /// full 90-cell grid even on weeks without syncs — the empty cells are the
    /// point of a heatmap.
    private var heatmapDays: [ActivityHeatmapDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Bucket records by startOfDay so the lookup per day is O(1).
        var successByDay: [Date: Int] = [:]
        var failureByDay: [Date: Int] = [:]
        for record in syncRecords {
            let day = calendar.startOfDay(for: record.timestamp)
            switch record.status {
            case .success,
                 .deferred:
                successByDay[day, default: 0] += 1
            case .failure,
                 .partialFailure:
                failureByDay[day, default: 0] += 1
            case .inProgress:
                continue
            }
        }

        return (0..<90).compactMap { offset -> ActivityHeatmapDay? in
            guard let date = calendar.date(byAdding: .day, value: -(89 - offset), to: today) else {
                return nil
            }
            return ActivityHeatmapDay(
                date: date,
                successCount: successByDay[date] ?? 0,
                failureCount: failureByDay[date] ?? 0
            )
        }
    }
}

// MARK: - FilterPill

/// A horizontally-scrolling filter pill used on the sync history screen.
///
/// Active pills use the label's foreground color (high contrast against the
/// filled capsule), inactive pills use an ultra-thin material so they fade
/// behind the heatmap above without disappearing entirely.
private struct FilterPill: View {
    let title: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HP.Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, HP.Spacing.lgXl)
            .padding(.vertical, HP.Spacing.md)
            .background {
                Capsule().fill(isActive ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isActive ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .foregroundStyle(isActive ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - SyncHistoryFilter

private enum SyncHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failed
    case background

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .success: "Successful"
        case .failed: "Failed"
        case .background: "Background"
        }
    }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .success: "checkmark.circle"
        case .failed: "xmark.circle"
        case .background: "moon.fill"
        }
    }
}

// MARK: - SyncRecordRow

struct SyncRecordRow: View {
    let record: SyncRecord

    var body: some View {
        HStack(spacing: HP.Spacing.lg) {
            statusIcon

            VStack(alignment: .leading, spacing: HP.Spacing.xxs) {
                HStack(spacing: HP.Spacing.sm) {
                    Text(record.destinationName)
                        .font(.subheadline.weight(.medium))

                    if record.isBackgroundSync {
                        Text("BG")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }

                HStack(spacing: HP.Spacing.md) {
                    Text("\(record.dataPointCount) points")
                        .font(.caption.monospaced())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Text(formattedDuration)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(record.timestamp, style: .time)
                .font(.caption.monospaced())
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recordAccessibilityLabel)
        .padding(.vertical, HP.Spacing.xs)
    }

    // MARK: Helpers

    private var recordAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(record.destinationName)
        parts.append(statusAccessibilityDescription)
        parts.append("\(record.dataPointCount) data points")
        parts.append("duration \(formattedDuration)")
        if record.isBackgroundSync {
            parts.append("background sync")
        }
        return parts.joined(separator: ", ")
    }

    private var statusAccessibilityDescription: String {
        switch record.status {
        case .success: "successful"
        case .partialFailure: "partially failed"
        case .failure: "failed"
        case .inProgress: "in progress"
        case .deferred: "deferred"
        }
    }

    private var statusIcon: some View {
        Image(systemName: iconName)
            .font(.body.weight(.medium))
            .foregroundStyle(iconColor)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 28)
    }

    private var iconName: String {
        switch record.status {
        case .success: "checkmark.circle.fill"
        case .partialFailure: "exclamationmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .inProgress: "arrow.triangle.2.circlepath"
        case .deferred: "clock.arrow.circlepath"
        }
    }

    private var iconColor: Color {
        switch record.status {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
        case .inProgress: .blue
        // Deferred is informational, not a problem — use the secondary text
        // color so it reads as "neutral, will retry" rather than red/orange.
        case .deferred: .secondary
        }
    }

    private var formattedDuration: String {
        if record.duration < 1 {
            return "<1s"
        } else if record.duration < 60 {
            return "\(Int(record.duration))s"
        } else {
            let minutes = Int(record.duration) / 60
            let seconds = Int(record.duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Preview

#Preview {
    SyncHistoryScreen()
        .modelContainer(for: [SyncRecord.self], inMemory: true)
}
