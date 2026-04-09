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
            DestinationConfig.self
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
        BackgroundSyncScheduler.shared.registerTasks { @MainActor in
            let context = ModelContext(container)
            let engine = SyncEngine()
            let result = await engine.performSync(modelContext: context, isBackground: true)
            let success = result.failedDestinations == 0
            if success {
                UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "last_sync_time")
            }
            return success
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

        // Schedule background sync using the most frequent destination's interval
        let minFrequency = destinationManager.destinations
            .filter(\.isEnabled)
            .map(\.syncFrequency)
            .min(by: { $0.timeInterval < $1.timeInterval })
            ?? .oneHour
        BackgroundSyncScheduler.shared.scheduleRefreshTask(frequency: minFrequency)
        BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFrequency)

        // Enable HealthKit background delivery for all metrics across enabled destinations
        let allEnabledMetrics = destinationManager.destinations
            .filter(\.isEnabled)
            .reduce(into: Set<HealthMetricType>()) { $0.formUnion($1.enabledMetrics) }

        if !allEnabledMetrics.isEmpty {
            Task {
                await syncEngine.enableBackgroundDelivery(for: allEnabledMetrics) {
                    await BackgroundSyncScheduler.shared.handleObserverUpdate()
                }
            }
        }

        // Re-register observers and re-schedule tasks when destinations change
        destinationManager.onDestinationsChanged = { [destinationManager, syncEngine] in
            let allMetrics = destinationManager.destinations
                .filter(\.isEnabled)
                .reduce(into: Set<HealthMetricType>()) { $0.formUnion($1.enabledMetrics) }

            let minFreq = destinationManager.destinations
                .filter(\.isEnabled)
                .map(\.syncFrequency)
                .min(by: { $0.timeInterval < $1.timeInterval })
                ?? .oneHour

            BackgroundSyncScheduler.shared.scheduleRefreshTask(frequency: minFreq)
            BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFreq)

            if !allMetrics.isEmpty {
                Task {
                    await syncEngine.enableBackgroundDelivery(for: allMetrics) {
                        await BackgroundSyncScheduler.shared.handleObserverUpdate()
                    }
                }
            }
        }

        // Clean up old sync records
        cleanupOldRecords(modelContext: context)
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
            if newPhase == .background {
                let minFrequency = destinationManager.destinations
                    .filter(\.isEnabled)
                    .map(\.syncFrequency)
                    .min(by: { $0.timeInterval < $1.timeInterval })
                    ?? .oneHour
                BackgroundSyncScheduler.shared.scheduleRefreshTask(frequency: minFrequency)
                BackgroundSyncScheduler.shared.scheduleProcessingTask(frequency: minFrequency)
            }
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
