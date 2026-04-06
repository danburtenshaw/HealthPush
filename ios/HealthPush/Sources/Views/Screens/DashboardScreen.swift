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

    @Query(sort: \SyncRecord.timestamp, order: .reverse)
    private var allSyncs: [SyncRecord]

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
                            isSyncOverdue: appState.isSyncOverdue,
                            hasSyncIssues: latestIssueRecord != nil
                        )

                        if showSetupChecklist {
                            setupChecklistCard
                        }

                        if let latestIssueRecord, !appState.isSyncing {
                            syncIssueCard(record: latestIssueRecord)
                        }

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
                Button(DestinationType.s3.displayName) { showingAddS3 = true }
                Button("Home Assistant") { showingAddHA = true }
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

                Text("Connect a destination to start syncing your Apple Health data. S3-compatible storage is the most direct export path today, and Home Assistant is also available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                showingAddS3 = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.fill")
                    Text("Add S3 Storage")
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

            Button {
                appState.hasSeenOnboarding = false
            } label: {
                Text("Open Welcome Guide")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Button {
                showingDestinationPicker = true
            } label: {
                Text("Choose Another Destination")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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

    private var showSetupChecklist: Bool {
        !appState.healthKitAuthorized || appState.lastSyncTime == nil
    }

    private var latestIssueRecord: SyncRecord? {
        guard let latestRecord = allSyncs.first else { return nil }
        guard latestRecord.status == .failure || latestRecord.status == .partialFailure else {
            return nil
        }
        return latestRecord
    }

    private var setupChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Finish Setup", systemImage: "checklist")
                .font(.headline)

            checklistRow(
                title: "Health access",
                detail: appState.healthKitAuthorized ? "Apple Health permissions are configured." : "Grant access so HealthPush can read the metrics you select.",
                isComplete: appState.healthKitAuthorized
            )

            checklistRow(
                title: "First destination",
                detail: "\(destinationManager.destinations.count) configured",
                isComplete: !destinationManager.destinations.isEmpty
            )

            checklistRow(
                title: "First successful sync",
                detail: appState.lastSyncTime == nil ? "Run Sync Now once your destination is configured." : "Last completed \(appState.lastSyncTimeFormatted).",
                isComplete: appState.lastSyncTime != nil
            )

            HStack(spacing: 12) {
                Button("Welcome Guide") {
                    appState.hasSeenOnboarding = false
                }
                .buttonStyle(.bordered)

                Button("Add Destination") {
                    showingDestinationPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func syncIssueCard(record: SyncRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sync Needs Attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(record.errorMessage ?? "One or more destinations reported an error during the last sync.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            HStack(spacing: 12) {
                Button("View History") {
                    showingSyncHistory = true
                }
                .buttonStyle(.bordered)

                Button("Review Destinations") {
                    if let preferred = destinationManager.destinations.first(where: \.isEnabled) {
                        selectedConfig = preferred
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        }
    }

    private func checklistRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
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
