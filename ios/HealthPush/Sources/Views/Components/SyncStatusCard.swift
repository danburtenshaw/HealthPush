import SwiftUI

// MARK: - SyncStatusCard

/// A prominent card that displays the current sync status, last sync time,
/// and next scheduled sync with animated visual feedback.
struct SyncStatusCard: View {

    // MARK: Properties

    let isSyncing: Bool
    let lastSyncTime: String
    let dataPointsSyncedToday: Int
    let totalSyncsCompleted: Int
    var isSyncOverdue: Bool = false
    var hasSyncIssues: Bool = false

    @State private var pulseScale: CGFloat = 1.0

    // MARK: Body

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Stats grid
            HStack(spacing: 0) {
                StatItem(
                    title: "Last Sync",
                    value: lastSyncTime,
                    icon: "clock.arrow.circlepath"
                )

                Divider()
                    .frame(height: 40)


                StatItem(
                    title: "Points Today",
                    value: "\(dataPointsSyncedToday)",
                    icon: "chart.bar.fill"
                )

                Divider()
                    .frame(height: 40)

                StatItem(
                    title: "Total Syncs",
                    value: "\(totalSyncsCompleted)",
                    icon: "checkmark.circle.fill"
                )
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    statusColor.opacity(0.3),
                    lineWidth: 1
                )
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 44, height: 44)

            if isSyncing {
                Circle()
                    .fill(statusColor.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true)
                        ) {
                            pulseScale = 1.4
                        }
                    }
                    .onDisappear {
                        pulseScale = 1.0
                    }

                ProgressView()
                    .tint(statusColor)
            } else {
                Image(systemName: statusIconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }

    // MARK: Computed Properties

    private var statusTitle: String {
        if isSyncing {
            return "Syncing..."
        }
        if hasSyncIssues { return "Needs Attention" }
        if lastSyncTime == "Never" { return "Ready to Sync" }
        if isSyncOverdue { return "Sync Delayed" }
        return "Up to Date"
    }

    private var statusSubtitle: String {
        if isSyncing {
            return "Sending health data to destinations"
        }
        if hasSyncIssues {
            return "Some destinations need review before the next sync"
        }
        if lastSyncTime == "Never" {
            return "Tap Sync Now to get started"
        }
        if isSyncOverdue {
            return "iOS deferred the background sync. Last synced \(lastSyncTime)"
        }
        return "Last synced \(lastSyncTime)"
    }

    private var statusColor: Color {
        if isSyncing { return .blue }
        if hasSyncIssues { return .orange }
        if lastSyncTime == "Never" { return .orange }
        if isSyncOverdue { return .orange }
        return .green
    }

    private var statusIconName: String {
        if hasSyncIssues { return "exclamationmark.triangle.fill" }
        if lastSyncTime == "Never" { return "arrow.triangle.2.circlepath" }
        if isSyncOverdue { return "exclamationmark.arrow.circlepath" }
        return "checkmark.circle.fill"
    }
}

// MARK: - StatItem

/// A small stat display used within the SyncStatusCard.
private struct StatItem: View {

    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SyncStatusCard(
            isSyncing: false,
            lastSyncTime: "5 min ago",
            dataPointsSyncedToday: 42,
            totalSyncsCompleted: 128
        )

        SyncStatusCard(
            isSyncing: true,
            lastSyncTime: "5 min ago",
            dataPointsSyncedToday: 42,
            totalSyncsCompleted: 128
        )

        SyncStatusCard(
            isSyncing: false,
            lastSyncTime: "Never",
            dataPointsSyncedToday: 0,
            totalSyncsCompleted: 0
        )
    }
    .padding()
}
