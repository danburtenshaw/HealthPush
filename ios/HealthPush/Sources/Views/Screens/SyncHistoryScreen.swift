import Charts
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

    @State private var selectedFilter: SyncHistoryFilter = .all
    @State private var searchText = ""
    @State private var selectedChartDay: Date?

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("Sync History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(SyncHistoryFilter.allCases) { filter in
                                Label(filter.displayName, systemImage: filter.icon)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter == .all
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                    .accessibilityLabel("Filter")
                    .accessibilityValue(selectedFilter.displayName)
                    .accessibilityHint("Filter sync history by status")
                }
            }
        }
    }

    // MARK: Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sync History", systemImage: "clock.arrow.circlepath")
        } description: {
            if selectedFilter == .all && searchText.isEmpty {
                Text("Sync history will appear here after your first sync.")
            } else {
                Text("No syncs match the selected filter or search.")
            }
        }
    }

    private var recordList: some View {
        List {
            if !chartData.isEmpty {
                chartSection
            }

            if selectedChartDay != nil {
                Section {
                    Button {
                        withAnimation { selectedChartDay = nil }
                    } label: {
                        Label("Clear Day Filter", systemImage: "xmark.circle")
                    }
                }
            }

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
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search by destination or error")
        .navigationDestination(for: UUID.self) { recordID in
            if let record = syncRecords.first(where: { $0.id == recordID }) {
                SyncRecordDetailView(record: record)
            }
        }
    }

    private var chartSection: some View {
        Section("Syncs Per Day") {
            Chart(chartData) { entry in
                BarMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Count", entry.count)
                )
                .foregroundStyle(by: .value("Destination", entry.destinationName))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handleChartTap(at: location, proxy: proxy, geometry: geometry)
                        }
                }
            }
            .frame(height: 200)
            .padding(.vertical, HP.Spacing.xs)
            .accessibilityLabel("Stacked bar chart showing syncs per day by destination")
        }
    }

    // MARK: Chart Interaction

    private func handleChartTap(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let plotFrame = geometry[proxy.plotFrame!]
        let relativeX = location.x - plotFrame.origin.x

        guard let tappedDate: Date = proxy.value(atX: relativeX) else { return }
        let calendar = Calendar.current
        let tappedDay = calendar.startOfDay(for: tappedDate)

        withAnimation {
            if selectedChartDay == tappedDay {
                selectedChartDay = nil
            } else {
                selectedChartDay = tappedDay
            }
        }
    }

    // MARK: Data

    private var filteredRecords: [SyncRecord] {
        var records: [SyncRecord]
        switch selectedFilter {
        case .all:
            records = syncRecords
        case .success:
            records = syncRecords.filter { $0.status == .success }
        case .failed:
            records = syncRecords.filter { $0.status == .failure || $0.status == .partialFailure }
        case .background:
            records = syncRecords.filter(\.isBackgroundSync)
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

    // MARK: Chart Data

    private var chartData: [SyncChartEntry] {
        let calendar = Calendar.current

        // Only chart the last 7 days of records
        let sevenDaysAgo = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: .now) ?? .now)
        let recentRecords = syncRecords.filter { $0.timestamp >= sevenDaysAgo }

        guard !recentRecords.isEmpty else { return [] }

        let grouped = Dictionary(grouping: recentRecords) { record -> String in
            let day = calendar.startOfDay(for: record.timestamp)
            return "\(day.timeIntervalSince1970)|\(record.destinationName)"
        }

        return grouped.map { _, records in
            let first = records[0]
            let day = calendar.startOfDay(for: first.timestamp)
            return SyncChartEntry(
                date: day,
                destinationName: first.destinationName,
                count: records.count
            )
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - SyncChartEntry

/// A single data point for the sync history chart.
struct SyncChartEntry: Identifiable {
    let date: Date
    let destinationName: String
    let count: Int

    var id: String {
        "\(date.timeIntervalSince1970)-\(destinationName)"
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
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(record.timestamp, style: .time)
                .font(.caption)
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
        }
    }

    private var iconColor: Color {
        switch record.status {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
        case .inProgress: .blue
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
