import SwiftUI
import SwiftData

// MARK: - SyncHistoryScreen

/// Screen displaying a chronological log of past sync operations with status, counts, and errors.
struct SyncHistoryScreen: View {

    // MARK: Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SyncRecord.timestamp, order: .reverse)
    private var syncRecords: [SyncRecord]

    @State private var selectedFilter: SyncHistoryFilter = .all

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
                }
            }
        }
    }

    // MARK: Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sync History", systemImage: "clock.arrow.circlepath")
        } description: {
            if selectedFilter == .all {
                Text("Sync history will appear here after your first sync.")
            } else {
                Text("No syncs match the selected filter.")
            }
        }
    }

    private var recordList: some View {
        List {
            ForEach(groupedByDate, id: \.key) { dateKey, records in
                Section(dateKey) {
                    ForEach(records) { record in
                        SyncRecordRow(record: record)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Data

    private var filteredRecords: [SyncRecord] {
        switch selectedFilter {
        case .all:
            return syncRecords
        case .success:
            return syncRecords.filter { $0.status == .success }
        case .failed:
            return syncRecords.filter { $0.status == .failure || $0.status == .partialFailure }
        case .background:
            return syncRecords.filter(\.isBackgroundSync)
        }
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
                      let rhsDate = rhs.value.first?.timestamp else {
                    return false
                }
                return lhsDate > rhsDate
            }
    }
}

// MARK: - SyncHistoryFilter

private enum SyncHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case failed
    case background

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .success: return "Successful"
        case .failed: return "Failed"
        case .background: return "Background"
        }
    }

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .success: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .background: return "moon.fill"
        }
    }
}

// MARK: - SyncRecordRow

private struct SyncRecordRow: View {

    let record: SyncRecord

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main row
            HStack(spacing: 12) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
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

                    HStack(spacing: 8) {
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

            // Error detail (expandable)
            if let errorMessage = record.errorMessage {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)

                        Text(isExpanded ? errorMessage : "Tap to see error details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 1)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private var statusIcon: some View {
        Image(systemName: iconName)
            .font(.body.weight(.medium))
            .foregroundStyle(iconColor)
            .frame(width: 28)
    }

    private var iconName: String {
        switch record.status {
        case .success: return "checkmark.circle.fill"
        case .partialFailure: return "exclamationmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        }
    }

    private var iconColor: Color {
        switch record.status {
        case .success: return .green
        case .partialFailure: return .orange
        case .failure: return .red
        case .inProgress: return .blue
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
