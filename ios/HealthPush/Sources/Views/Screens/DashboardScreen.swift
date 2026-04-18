import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var lastSyncSucceeded = false
    @State private var nudgeDismissed = false
    @State private var showSyncSuccess = false
    /// When the user taps the dashboard's "Sync Needs Attention" nudge, we
    /// open the history sheet pre-pushed to that record's detail view.
    @State private var pendingHistoryRecordID: UUID?

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: HP.Spacing.xxl) {
                    if destinationManager.destinations.isEmpty {
                        // No destinations — guide the user to set one up
                        emptyDestinationsPrompt
                    } else {
                        // Status card — derives sync time and overdue status
                        // from per-destination timestamps, not AppState.lastSyncTime.
                        SyncStatusCard(
                            isSyncing: appState.isSyncing,
                            lastSyncTime: aggregateLastSyncFormatted,
                            dataPointsSyncedToday: appState.dataPointsSyncedToday,
                            totalSyncsCompleted: appState.totalSyncsCompleted,
                            isSyncOverdue: isAnyDestinationOverdue,
                            hasSyncIssues: latestIssueRecord != nil
                        )

                        // Single prioritized nudge slot replaces individual banners
                        if let nudge = activeNudge, !nudgeDismissed {
                            NudgeRow(
                                kind: nudge,
                                onAction: { handleNudgeAction(nudge) },
                                onSecondaryAction: { showingSyncHistory = true },
                                onDismiss: {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        nudgeDismissed = true
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        // Destinations section
                        destinationsSection

                        // Recent activity
                        if !recentSyncs.isEmpty {
                            recentActivitySection
                        }

                        // Trust footer
                        trustFooter
                    }
                }
                .padding(.top, HP.Spacing.md)
                .padding(.bottom, HP.Spacing.jumbo)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, HP.Spacing.xxl, for: .scrollContent)
            .sensoryFeedback(.success, trigger: lastSyncSucceeded)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HealthPush")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSyncHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Sync History")
                    .accessibilityHint("View past sync operations")
                }
            }
            .sheet(isPresented: $showingSyncHistory, onDismiss: { pendingHistoryRecordID = nil }) {
                SyncHistoryScreen(initialRecordID: pendingHistoryRecordID)
            }
            .sheet(isPresented: $showingDestinationPicker) {
                AddDestinationSheet { type in
                    switch type {
                    case .s3: showingAddS3 = true
                    case .homeAssistant: showingAddHA = true
                    }
                }
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
            .safeAreaInset(edge: .bottom) {
                if !destinationManager.destinations.isEmpty {
                    syncBottomBar
                }
            }
            .refreshable {
                // SwiftUI cancels the .refreshable task when view state thrash
                // (dynamic safeAreaInset, state-driven layout changes) invalidates
                // the refresh context. That cancellation propagates into
                // URLSession.data(for:) and aborts uploads mid-flight with
                // URLError.cancelled. Running performSync in an unstructured
                // child Task detaches it from refresh cancellation; awaiting
                // .value keeps the refresh spinner visible until the sync
                // actually finishes.
                await Task { await performSync() }.value
            }
            .onChange(of: activeNudge) {
                // Reset dismissal when the nudge kind changes
                nudgeDismissed = false
            }
            .onChange(of: appState.pendingFirstSync) {
                if appState.pendingFirstSync {
                    appState.pendingFirstSync = false
                    Task { await performSync() }
                }
            }
        }
    }

    // MARK: Nudge Logic

    /// The highest-priority nudge that applies right now, or nil.
    private var activeNudge: NudgeKind? {
        // Don't show nudges while syncing
        guard !appState.isSyncing else { return nil }

        // Priority 1: Sync failure
        if let record = latestIssueRecord {
            return .syncFailure(
                message: record.errorMessage
                    ?? "One or more destinations reported an error during the last sync.",
                recovery: record.failureCategory?.recoveryAction
            )
        }

        // Priority 2: No health data
        if appState.lastSyncHadNoData {
            return .noHealthData
        }

        // Priority 3: Background refresh disabled
        if !appState.isBackgroundRefreshAvailable {
            return .backgroundRefreshDisabled
        }

        // Priority 4: Setup incomplete
        if !appState.healthKitAuthorized || hasNeverSyncedDestination {
            return .setupIncomplete(
                healthKitAuthorized: appState.healthKitAuthorized,
                hasDestinations: !destinationManager.destinations.isEmpty,
                hasEverSynced: !hasNeverSyncedDestination
            )
        }

        return nil
    }

    private func handleNudgeAction(_ nudge: NudgeKind) {
        switch nudge {
        case .syncFailure:
            // Open the history sheet pre-pushed to the failed record's detail.
            // The detail view exposes the recovery action (e.g. "Set region to
            // us-east-1"), which takes the user from there to the destination
            // editor — keeping the failure context one tap away from the fix.
            if let record = latestIssueRecord {
                pendingHistoryRecordID = record.id
            }
            showingSyncHistory = true
        case .noHealthData:
            if let url = URL(string: "x-apple-health://") {
                UIApplication.shared.open(url)
            }
        case .backgroundRefreshDisabled:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                showingDestinationPicker = true
            } else if !healthKitAuthorized {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: Subviews

    private var syncBottomBar: some View {
        Group {
            if showSyncSuccess {
                // Brief success indicator
                HStack(spacing: HP.Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                    Text("Sync Complete")
                        .font(HP.Typography.sectionTitle)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.green, in: RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous))
            } else if appState.isSyncing {
                // Syncing state with per-destination progress
                VStack(spacing: HP.Spacing.sm) {
                    HStack(spacing: HP.Spacing.mdLg) {
                        ProgressView()
                            .tint(.white)
                        Text("Syncing...")
                            .font(HP.Typography.sectionTitle)
                            .foregroundStyle(.white)
                    }

                    if let progressText = aggregateSyncProgressText {
                        Text(progressText)
                            .font(HP.Typography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.gray, in: RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous))
            } else {
                // Idle state
                Button {
                    Task {
                        await performSync()
                    }
                } label: {
                    HStack(spacing: HP.Spacing.mdLg) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body.weight(.semibold))
                        Text("Sync Now")
                            .font(HP.Typography.sectionTitle)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous))
                    .foregroundStyle(.white)
                }
                .sensoryFeedback(.impact(flexibility: .solid), trigger: appState.isSyncing)
                .accessibilityLabel("Sync Now")
                .accessibilityHint("Sends health data to all enabled destinations")
            }
        }
        .padding(.horizontal, HP.Spacing.xl)
        .padding(.vertical, HP.Spacing.md)
        .background(.bar)
    }

    /// Aggregated progress text from all active destination syncs.
    private var aggregateSyncProgressText: String? {
        let entries = appState.syncStatusText.sorted(by: { $0.key < $1.key })
        guard !entries.isEmpty else { return nil }
        return entries.map { "\($0.key): \($0.value)" }.joined(separator: " | ")
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lg) {
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
                VStack(spacing: HP.Spacing.md) {
                    Button {
                        selectedConfig = config
                    } label: {
                        DestinationCard(config: config)
                    }
                    .buttonStyle(.plain)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.3)
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
                    .accessibilityHint("Double tap to edit \(config.name)")

                    if appState.isSyncing {
                        let progress = appState.syncProgress[config.name] ?? 0
                        let status = appState.syncStatusText[config.name] ?? "Waiting..."

                        VStack(spacing: HP.Spacing.xs) {
                            ProgressView(value: progress)
                                .tint(progress >= 1.0 ? .green : Color.accentColor)
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, HP.Spacing.xs)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(config.name) sync progress: \(status)")
                    }
                }
            }
        }
    }

    private var emptyDestinationsPrompt: some View {
        VStack(spacing: HP.Spacing.xxl) {
            Spacer()
                .frame(height: 40)

            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor.opacity(0.7))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: HP.Spacing.md) {
                Text("Welcome to HealthPush")
                    .font(.title2.weight(.semibold))

                Text("Connect a destination to start syncing your Apple Health data.")
                    .font(HP.Typography.cardBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HP.Spacing.xl)
            }

            Button {
                showingDestinationPicker = true
            } label: {
                HStack(spacing: HP.Spacing.mdLg) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Destination")
                        .font(HP.Typography.sectionTitle)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
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

            // Trust footer for empty state too
            trustFooter

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lg) {
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
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.3)
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
            }
        }
    }

    private var trustFooter: some View {
        VStack(spacing: HP.Spacing.sm) {
            Text("Open source \u{00B7} No backend \u{00B7} No telemetry")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Link(destination: URL(string: "https://github.com/danburtenshaw/HealthPush")!) {
                Text("View on GitHub")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel("View HealthPush on GitHub")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HP.Spacing.md)
    }

    // MARK: Actions

    @MainActor
    private func performSync() async {
        guard !appState.isSyncing else { return }
        appState.isSyncing = true
        appState.syncProgress = [:]
        appState.syncStatusText = [:]
        showSyncSuccess = false
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

        if result.failedDestinations == 0 && result.successfulDestinations > 0 {
            lastSyncSucceeded.toggle()
        }

        // Brief success indicator that fades after 3 seconds
        if result.failedDestinations == 0 {
            showSyncSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.3)) {
                    showSyncSuccess = false
                }
            }
        }

        // After a manual sync, schedule the next periodic safety-net task with
        // a fresh earliest begin date. (Foreground syncs don't go through the
        // BGTask handler, so it doesn't reschedule itself.)
        let minFrequency = destinationManager.destinations
            .filter(\.isEnabled)
            .map(\.syncFrequency)
            .min(by: { $0.timeInterval < $1.timeInterval })
            ?? .oneHour
        Task {
            await BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFrequency, force: true)
        }

        // Reload destinations to reflect updated state
        destinationManager.loadDestinations(modelContext: modelContext)
    }

    // MARK: Per-Destination Aggregate Status

    /// The most recent `lastSyncedAt` across all enabled destinations.
    private var aggregateLastSyncDate: Date? {
        destinationManager.destinations
            .filter(\.isEnabled)
            .compactMap(\.lastSyncedAt)
            .max()
    }

    /// Formatted string for the most recent sync time across all destinations.
    private var aggregateLastSyncFormatted: String {
        guard let date = aggregateLastSyncDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    /// Whether any enabled destination is overdue for a sync.
    ///
    /// A destination is considered overdue when its `nextSyncTime` (derived from
    /// `lastSyncedAt + syncFrequency`) is more than 30 minutes in the past.
    /// A destination that has never synced is also treated as overdue-like, but
    /// that state is handled separately by the "Not synced" status in `SyncStatusCard`.
    private var isAnyDestinationOverdue: Bool {
        let enabledDestinations = destinationManager.destinations.filter(\.isEnabled)
        guard !enabledDestinations.isEmpty else { return false }

        for destination in enabledDestinations {
            guard let nextSync = destination.nextSyncTime else {
                // Never synced — not overdue per se, but "Never" status covers this.
                continue
            }
            if Date.now > nextSync.addingTimeInterval(30 * 60) {
                return true
            }
        }
        return false
    }

    /// Whether any enabled destination has never been synced.
    private var hasNeverSyncedDestination: Bool {
        destinationManager.destinations
            .filter(\.isEnabled)
            .contains { $0.lastSyncedAt == nil }
    }

    /// For each enabled destination, check if its most recent sync record is a failure.
    /// Only show a nudge if the very latest record for any destination is a failure.
    /// This way, if a sync fails but a retry succeeds, the nudge disappears.
    private var latestIssueRecord: SyncRecord? {
        let enabledIDs = Set(destinationManager.destinations.filter(\.isEnabled).map(\.id))

        for destID in enabledIDs {
            guard let latestForDest = allSyncs.first(where: { $0.destinationID == destID }) else {
                continue
            }
            if latestForDest.status == .failure || latestForDest.status == .partialFailure {
                return latestForDest
            }
        }
        return nil
    }
}

// MARK: - RecentSyncRow

private struct RecentSyncRow: View {
    let record: SyncRecord

    var body: some View {
        HStack(spacing: HP.Spacing.lg) {
            Image(systemName: statusIcon)
                .font(.body.weight(.medium))
                .foregroundStyle(statusColor)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, isActive: record.status == .inProgress)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: HP.Spacing.xxs) {
                Text(record.destinationName)
                    .font(.subheadline.weight(.medium))

                Text("\(record.dataPointCount) data points")
                    .font(HP.Typography.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: record.dataPointCount)
            }

            Spacer()

            Text(record.timestamp, style: .relative)
                .font(HP.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, HP.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fullAccessibilityLabel)
    }

    private var fullAccessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let absoluteDate = formatter.string(from: record.timestamp)
        return "\(record.destinationName), \(statusDescription), \(record.dataPointCount) data points, \(absoluteDate)"
    }

    private var statusDescription: String {
        switch record.status {
        case .success: "successful"
        case .partialFailure: "partially failed"
        case .failure: "failed"
        case .inProgress: "in progress"
        case .deferred: "deferred"
        }
    }

    private var statusIcon: String {
        switch record.status {
        case .success: "checkmark.circle.fill"
        case .partialFailure: "exclamationmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .inProgress: "arrow.triangle.2.circlepath"
        case .deferred: "clock.arrow.circlepath"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .success: .green
        case .partialFailure: .orange
        case .failure: .red
        case .inProgress: .blue
        case .deferred: .secondary
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
