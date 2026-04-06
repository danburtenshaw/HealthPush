import SwiftUI
import SwiftData

// MARK: - DashboardScreen

/// The main screen showing sync status, quick stats, destinations, and a sync button.
struct DashboardScreen: View {

    // MARK: Properties

    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(DestinationManager.self) private var destinationManager
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<SyncRecord> { $0.statusRaw == "success" },
        sort: \SyncRecord.timestamp,
        order: .reverse
    )
    private var recentSyncs: [SyncRecord]

    @State private var showingSyncHistory = false
    @State private var showingDestinationPicker = false
    @State private var showingAddHA = false
    @State private var showingAddS3 = false
    @State private var selectedConfig: DestinationConfig?

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if destinationManager.destinations.isEmpty {
                        // No destinations — guide the user to set one up
                        emptyDestinationsPrompt
                    } else {
                        // Status card
                        SyncStatusCard(
                            isSyncing: appState.isSyncing,
                            lastSyncTime: appState.lastSyncTimeFormatted,
                            dataPointsSyncedToday: appState.dataPointsSyncedToday,
                            totalSyncsCompleted: appState.totalSyncsCompleted,
                            isSyncOverdue: appState.isSyncOverdue
                        )

                        // Sync Now button
                        syncNowButton

                        // Destinations section
                        destinationsSection

                        // Recent activity
                        if !recentSyncs.isEmpty {
                            recentActivitySection
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HealthPush")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSyncHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingSyncHistory) {
                SyncHistoryScreen()
            }
            .confirmationDialog("Add Destination", isPresented: $showingDestinationPicker) {
                Button("Home Assistant") { showingAddHA = true }
                Button("Amazon S3") { showingAddS3 = true }
            }
            .sheet(isPresented: $showingAddHA) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                HomeAssistantSetupScreen(mode: .create)
            }
            .sheet(isPresented: $showingAddS3) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                S3SetupScreen(mode: .create)
            }
            .sheet(item: $selectedConfig) { config in
                if config.destinationType == .s3 {
                    S3SetupScreen(mode: .edit(config))
                } else {
                    HomeAssistantSetupScreen(mode: .edit(config))
                }
            }
            .refreshable {
                await performSync()
            }
        }
    }

    // MARK: Subviews

    private var syncNowButton: some View {
        Button {
            Task {
                await performSync()
            }
        } label: {
            HStack(spacing: 10) {
                if appState.isSyncing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                }

                Text(appState.isSyncing ? "Syncing..." : "Sync Now")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(appState.isSyncing ? Color.gray : Color.accentColor)
            }
            .foregroundStyle(.white)
        }
        .disabled(appState.isSyncing)
        .sensoryFeedback(.impact(flexibility: .solid), trigger: appState.isSyncing)
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Destinations")
                    .font(.title3.weight(.semibold))
                Spacer()
                NavigationLink {
                    DestinationsScreen()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                }
            }

            ForEach(destinationManager.destinations, id: \.id) { config in
                VStack(spacing: 8) {
                    Button {
                        selectedConfig = config
                    } label: {
                        DestinationCard(config: config)
                    }
                    .buttonStyle(.plain)

                    if appState.isSyncing {
                        let progress = appState.syncProgress[config.name] ?? 0
                        let status = appState.syncStatusText[config.name] ?? "Waiting..."

                        VStack(spacing: 4) {
                            ProgressView(value: progress)
                                .tint(progress >= 1.0 ? .green : Color.accentColor)
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    private var emptyDestinationsPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 40)

            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor.opacity(0.7))

            VStack(spacing: 8) {
                Text("Welcome to HealthPush")
                    .font(.title2.weight(.semibold))

                Text("Connect a destination to start syncing your Apple Health data. Your data stays on your device until you choose where to send it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                showingDestinationPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Destination")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                }
                .foregroundStyle(.white)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("View All") {
                    showingSyncHistory = true
                }
                .font(.subheadline)
            }

            ForEach(recentSyncs.prefix(3)) { record in
                RecentSyncRow(record: record)
            }
        }
    }

    // MARK: Actions

    @MainActor
    private func performSync() async {
        guard !appState.isSyncing else { return }
        appState.isSyncing = true
        appState.syncProgress = [:]
        appState.syncStatusText = [:]
        defer {
            appState.isSyncing = false
            appState.syncProgress = [:]
            appState.syncStatusText = [:]
        }

        let result = await syncEngine.performSync(
            modelContext: modelContext
        ) { name, progress in
            appState.syncProgress[name] = progress
            let pct = Int(progress * 100)
            appState.syncStatusText[name] = pct < 100 ? "Syncing \(pct)%" : "Done"
        }
        appState.recordSyncResult(result)

        // Re-schedule background tasks with fresh earliest begin date
        let minFrequency = destinationManager.destinations
            .filter(\.isEnabled)
            .map(\.syncFrequency)
            .min(by: { $0.timeInterval < $1.timeInterval })
            ?? .oneHour
        BackgroundSyncScheduler.shared.scheduleRefreshTask(frequency: minFrequency)
        BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFrequency)

        // Reload destinations to reflect updated state
        destinationManager.loadDestinations(modelContext: modelContext)
    }
}

// MARK: - RecentSyncRow

private struct RecentSyncRow: View {

    let record: SyncRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.body.weight(.medium))
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.destinationName)
                    .font(.subheadline.weight(.medium))

                Text("\(record.dataPointCount) data points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.timestamp, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private var statusIcon: String {
        switch record.status {
        case .success: return "checkmark.circle.fill"
        case .partialFailure: return "exclamationmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .inProgress: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .success: return .green
        case .partialFailure: return .orange
        case .failure: return .red
        case .inProgress: return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [SyncRecord.self, DestinationConfig.self], inMemory: true)
}
