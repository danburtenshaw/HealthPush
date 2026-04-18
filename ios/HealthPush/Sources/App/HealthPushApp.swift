import SwiftData
import SwiftUI

// MARK: - HealthPushApp

/// The main entry point for the HealthPush application.
///
/// This struct configures the SwiftData model container, registers background tasks,
/// and sets up the root view hierarchy with shared state objects.
@main
struct HealthPushApp: App {
    // MARK: Properties

    @State private var appState = AppState()
    @State private var syncEngine = SyncEngine()
    @State private var destinationManager = DestinationManager()

    private let modelContainer: ModelContainer

    // MARK: Initialization

    init() {
        // Configure SwiftData
        let schema = Schema([
            SyncRecord.self,
            DestinationConfig.self,
            MetricSyncAnchor.self
        ])
        let modelConfiguration = ModelConfiguration(
            "HealthPush",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }

        // Register background tasks
        registerBackgroundTasks()
    }

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(syncEngine)
                .environment(destinationManager)
                .onAppear {
                    onAppLaunch()
                }
        }
        .modelContainer(modelContainer)
    }

    // MARK: Background Tasks

    private func registerBackgroundTasks() {
        let container = modelContainer
        let appState = appState
        let destinationManager = destinationManager
        let syncEngine = syncEngine
        BackgroundSyncScheduler.shared.registerTasks { @MainActor (deadline: Date?, isBackground: Bool) -> Bool in
            // Use the main context so SwiftData changes (lastSyncedAt, needsFullSync)
            // are visible to the UI immediately. Using a separate ModelContext would
            // cause the dashboard to show stale data until the contexts merge.
            let context = container.mainContext
            let result = await syncEngine.performSync(
                modelContext: context,
                isAutomatic: true,
                isBackground: isBackground,
                deadline: deadline
            )
            appState.recordSyncResult(result)
            destinationManager.loadDestinations(modelContext: context)

            // If we ran out of background time before finishing every destination,
            // request a quicker retry so the user doesn't wait a full interval to
            // see the rest of the data flow.
            if result.deferredDestinations > 0 {
                BackgroundSyncScheduler.shared.scheduleQuickRetry()
            }

            // Real failures (not deferrals) determine whether to mark the BGTask
            // as successful — deferred runs always count as success because
            // we made the right call.
            return result.failedDestinations == 0
        }
    }

    @MainActor
    private func onAppLaunch() {
        // Give the background scheduler access to the single isSyncing source of truth
        BackgroundSyncScheduler.shared.configure(appState: appState)

        // Sweep orphaned Keychain items left behind by a previous installation.
        // Keychain items with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly survive
        // app deletion, so we clean them up on the first launch of a fresh install.
        let hasCompletedFirstLaunch = UserDefaults.standard.bool(forKey: "has_completed_first_launch")
        if !hasCompletedFirstLaunch {
            try? KeychainService.deleteAllServiceItems()
            UserDefaults.standard.set(true, forKey: "has_completed_first_launch")
        }

        // Hydrate stored properties from UserDefaults (background syncs may have updated them)
        appState.refreshFromUserDefaults()

        // Load destinations
        let context = modelContainer.mainContext
        destinationManager.loadDestinations(modelContext: context)

        // Schedule the periodic safety-net BGProcessingTask using the most
        // frequent destination's interval. The HKObserverQuery push path
        // (registered below) is what actually delivers timely syncs — this
        // task is the fallback for periods between observer events.
        let minFrequency = currentMinFrequency()
        Task {
            await BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFrequency)
        }

        // Enable HealthKit background delivery for all metrics across enabled destinations
        let allEnabledMetrics = destinationManager.destinations
            .filter(\.isEnabled)
            .reduce(into: Set<HealthMetricType>()) { $0.formUnion($1.enabledMetrics) }

        if !allEnabledMetrics.isEmpty {
            Task {
                await BackgroundSyncScheduler.shared.withObserversSuppressed {
                    await syncEngine.enableBackgroundDelivery(for: allEnabledMetrics) {
                        await BackgroundSyncScheduler.shared.handleObserverUpdate()
                    }
                }
            }
        }

        // Re-register observers when destinations change. We don't reschedule
        // the BGProcessingTask here — the existing pending request still has
        // the right cadence, and re-submitting would reset the clock.
        destinationManager.onDestinationsChanged = { [destinationManager, syncEngine] in
            let allMetrics = destinationManager.destinations
                .filter(\.isEnabled)
                .reduce(into: Set<HealthMetricType>()) { $0.formUnion($1.enabledMetrics) }

            // Only re-submit the BGProcessingTask if frequency actually changed.
            let newFreq = destinationManager.destinations
                .filter(\.isEnabled)
                .map(\.syncFrequency)
                .min(by: { $0.timeInterval < $1.timeInterval })
                ?? .oneHour

            if newFreq != BackgroundSyncScheduler.shared.lastScheduledFrequency {
                Task {
                    await BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: newFreq, force: true)
                }
            }

            if !allMetrics.isEmpty {
                Task {
                    await BackgroundSyncScheduler.shared.withObserversSuppressed {
                        await syncEngine.enableBackgroundDelivery(for: allMetrics) {
                            await BackgroundSyncScheduler.shared.handleObserverUpdate()
                        }
                    }
                }
            }
        }

        // Clean up old sync records
        cleanupOldRecords(modelContext: context)
    }

    /// Returns the most-frequent sync interval across all enabled destinations,
    /// defaulting to one hour when there are none.
    @MainActor
    private func currentMinFrequency() -> SyncFrequency {
        destinationManager.destinations
            .filter(\.isEnabled)
            .map(\.syncFrequency)
            .min(by: { $0.timeInterval < $1.timeInterval })
            ?? .oneHour
    }

    @MainActor
    private func performForegroundSync(modelContext: ModelContext) async {
        guard !appState.isSyncing else { return }
        appState.isSyncing = true

        let result = await syncEngine.performSync(modelContext: modelContext)
        appState.recordSyncResult(result)

        appState.isSyncing = false
    }

    @MainActor
    private func cleanupOldRecords(modelContext: ModelContext) {
        let retentionDays = appState.dataRetentionDays
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: .now
        ) else { return }

        let descriptor = FetchDescriptor<SyncRecord>(
            predicate: #Predicate<SyncRecord> { record in
                record.timestamp < cutoffDate
            }
        )

        do {
            let oldRecords = try modelContext.fetch(descriptor)
            for record in oldRecords {
                modelContext.delete(record)
            }
            if !oldRecords.isEmpty {
                try modelContext.save()
            }
        } catch {
            // Non-critical; log and continue
        }
    }
}

// MARK: - ContentView

/// Root content view with tab-based navigation.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(DestinationManager.self) private var destinationManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState

        TabView {
            DashboardScreen()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.clipboard")
                }

            DestinationsScreen()
                .tabItem {
                    Label("Destinations", systemImage: "arrow.triangle.branch")
                }

            SettingsScreen()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.accentColor)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingScreen()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.refreshFromUserDefaults()
            }
            // Note: we deliberately do NOT re-submit the BGProcessingTask on
            // every background entry. Re-submitting resets `earliestBeginDate`
            // and is the chief cause of erratic intervals in production. The
            // task handler reschedules itself when it runs.
        }
        .alert("Error", isPresented: $appState.showingError) {
            Button("OK") {
                appState.clearError()
            }
        } message: {
            Text(appState.lastError ?? "An unknown error occurred.")
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !appState.hasSeenOnboarding },
            set: { isPresented in
                if !isPresented {
                    appState.hasSeenOnboarding = true
                }
            }
        )
    }
}
