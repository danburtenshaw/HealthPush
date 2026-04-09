import SwiftUI

// MARK: - SyncRecordDetailView

/// Detail screen showing full information about a single sync record.
///
/// Displays destination name and icon, timestamp, duration, status, data point count,
/// background/foreground indicator, error details, failure category, recovery actions,
/// and a button to copy a formatted error report to the clipboard.
struct SyncRecordDetailView: View {
    // MARK: Properties

    let record: SyncRecord

    @Environment(\.dismiss) private var dismiss
    @State private var showCopiedConfirmation = false

    // MARK: Body

    var body: some View {
        List {
            destinationSection
            timingSection
            statusSection

            if record.errorMessage != nil || record.failureCategory != nil {
                errorSection
            }

            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sync Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var destinationSection: some View {
        Section {
            HStack(spacing: HP.Spacing.lg) {
                Image(systemName: destinationIcon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: HP.Spacing.xxs) {
                    Text(record.destinationName)
                        .font(HP.Typography.sectionTitle)

                    HStack(spacing: HP.Spacing.sm) {
                        if record.isBackgroundSync {
                            Label("Background", systemImage: "moon.fill")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        } else {
                            Label("Foreground", systemImage: "hand.tap.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, HP.Spacing.xs)
        }
    }

    private var timingSection: some View {
        Section("Timing") {
            LabeledContent {
                VStack(alignment: .trailing, spacing: HP.Spacing.xxs) {
                    Text(record.timestamp, style: .date)
                    Text(record.timestamp, style: .time)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("Timestamp", systemImage: "calendar.badge.clock")
            }

            LabeledContent {
                Text(record.timestamp, style: .relative)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Relative", systemImage: "clock")
            }

            LabeledContent {
                Text(formattedDuration)
            } label: {
                Label("Duration", systemImage: "stopwatch")
            }
        }
    }

    private var statusSection: some View {
        Section("Result") {
            HStack(spacing: HP.Spacing.md) {
                Label("Status", systemImage: "flag")
                Spacer()
                statusBadge
            }

            LabeledContent {
                Text("\(record.dataPointCount)")
                    .monospacedDigit()
            } label: {
                Label("Data Points", systemImage: "number")
            }

            if let partialSuccess = record.partialSuccessCount,
               let partialFailure = record.partialFailureCount
            {
                LabeledContent {
                    Text("\(partialSuccess) succeeded, \(partialFailure) failed")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Breakdown", systemImage: "chart.bar")
                }
            }
        }
    }

    private var errorSection: some View {
        Section("Error Details") {
            if let errorMessage = record.errorMessage {
                VStack(alignment: .leading, spacing: HP.Spacing.md) {
                    Label("Message", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)

                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, HP.Spacing.xs)
            }

            if let failure = record.failureCategory {
                VStack(alignment: .leading, spacing: HP.Spacing.md) {
                    Label("Category", systemImage: "tag")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: HP.Spacing.sm) {
                        Image(systemName: failureCategoryIcon(failure))
                            .foregroundStyle(failureCategoryColor(failure))
                        Text(failureCategoryLabel(failure))
                            .font(.subheadline)
                    }

                    Text(failureCategoryExplanation(failure))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, HP.Spacing.xs)
            }

            if let recovery = record.failureCategory?.recoveryAction {
                VStack(alignment: .leading, spacing: HP.Spacing.md) {
                    Label("Recovery", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)

                    Text(recovery.guidance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        // The recovery action button navigates the user toward fixing the issue.
                        // In a future iteration this could open the destination settings directly.
                    } label: {
                        Label(recovery.buttonTitle, systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, HP.Spacing.xs)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                copyErrorReport()
            } label: {
                Label(
                    showCopiedConfirmation ? "Copied" : "Copy Error Report",
                    systemImage: showCopiedConfirmation ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(showCopiedConfirmation)
            .accessibilityLabel("Copy Error Report")
            .accessibilityHint("Copies a formatted text block with sync details to the clipboard")
        }
    }

    // MARK: Helpers

    private var statusBadge: some View {
        HStack(spacing: HP.Spacing.xs) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)
                .symbolRenderingMode(.hierarchical)
            Text(statusLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, HP.Spacing.md)
        .padding(.vertical, HP.Spacing.xs)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusIconName: String {
        switch record.status {
        case .success: "checkmark.circle.fill"
        case .partialFailure: "exclamationmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .inProgress: "arrow.triangle.2.circlepath"
        }
    }

    private var statusLabel: String {
        switch record.status {
        case .success: "Success"
        case .partialFailure: "Partial"
        case .failure: "Failed"
        case .inProgress: "In Progress"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
        case .inProgress: .blue
        }
    }

    private var destinationIcon: String {
        // Infer the destination icon from the name. Falls back to a generic icon.
        let lowered = record.destinationName.lowercased()
        if lowered.contains("home assistant") || lowered.contains("ha") {
            return "house.fill"
        } else if lowered.contains("s3") || lowered.contains("storage") || lowered.contains("bucket") {
            return "cloud.fill"
        }
        return "arrow.up.circle.fill"
    }

    private var formattedDuration: String {
        if record.duration < 0.1 {
            return "<0.1s"
        } else if record.duration < 10 {
            return String(format: "%.1fs", record.duration)
        } else if record.duration < 60 {
            return "\(Int(record.duration))s"
        } else {
            let minutes = Int(record.duration) / 60
            let seconds = Int(record.duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }

    private func failureCategoryIcon(_ failure: SyncFailure) -> String {
        switch failure {
        case .transient: "arrow.clockwise.circle"
        case .permanent: "xmark.octagon"
        case .partial: "exclamationmark.triangle"
        }
    }

    private func failureCategoryColor(_ failure: SyncFailure) -> Color {
        switch failure {
        case .transient: .yellow
        case .permanent: .red
        case .partial: .orange
        }
    }

    private func failureCategoryLabel(_ failure: SyncFailure) -> String {
        switch failure {
        case .transient: "Transient"
        case .permanent: "Permanent"
        case .partial: "Partial Failure"
        }
    }

    private func failureCategoryExplanation(_ failure: SyncFailure) -> String {
        switch failure {
        case .transient:
            return "This error is temporary and will be retried automatically on the next sync. Common causes include network timeouts, server errors, or intermittent connectivity."
        case .permanent:
            return "This error requires your intervention to resolve. The sync will not be retried until the underlying issue is fixed."
        case let .partial(successes, failures, _):
            return "\(successes) destination(s) succeeded and \(failures) failed. The next sync will retry the failed destinations."
        }
    }

    private func copyErrorReport() {
        var report = """
        HealthPush Sync Report
        ----------------------
        Destination: \(record.destinationName)
        Timestamp: \(record.timestamp.formatted(date: .complete, time: .standard))
        Duration: \(formattedDuration)
        Status: \(statusLabel)
        Data Points: \(record.dataPointCount)
        Sync Type: \(record.isBackgroundSync ? "Background" : "Foreground")
        """

        if let errorMessage = record.errorMessage {
            report += "\nError: \(errorMessage)"
        }

        if let failure = record.failureCategory {
            report += "\nFailure Category: \(failureCategoryLabel(failure))"
            if let recovery = failure.recoveryAction {
                report += "\nRecovery: \(recovery.guidance)"
            }
        }

        UIPasteboard.general.string = report
        withAnimation {
            showCopiedConfirmation = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                showCopiedConfirmation = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SyncRecordDetailView(
            record: SyncRecord(
                destinationName: "Home Assistant",
                destinationID: UUID(),
                timestamp: .now.addingTimeInterval(-3600),
                duration: 4.2,
                dataPointCount: 142,
                status: .failure,
                errorMessage: "HTTP error 401: Unauthorized access to webhook endpoint.",
                isBackgroundSync: true
            )
        )
    }
}
