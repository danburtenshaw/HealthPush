import SwiftUI
import SwiftData

// MARK: - SettingsScreen

/// App settings screen with sync frequency, data retention, and about info.
struct SettingsScreen: View {

    // MARK: Properties

    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext

    @State private var showingSyncHistory = false
    @State private var showingResetConfirmation = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                syncSection
                backgroundSyncSection
                healthKitSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSyncHistory) {
                SyncHistoryScreen()
            }
            .alert("Reset Sync Data", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) { resetSyncData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all sync history and HealthKit anchors, forcing a full re-sync. Your destination configurations will be preserved.")
            }
        }
    }

    // MARK: Sections

    private var syncSection: some View {
        Section {
            Toggle(isOn: syncOnAppOpenBinding) {
                Label("Sync on App Open", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Sync frequency is configured per destination. Background sync timing is approximate — iOS may delay tasks based on system conditions.")
        }
    }

    private var backgroundSyncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("How Background Sync Works", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    bulletRow(icon: "applewatch", text: "HealthKit delivery — syncs when new health data arrives from Apple Watch or other sources")
                    bulletRow(icon: "arrow.triangle.2.circlepath", text: "Scheduled refresh — iOS runs background tasks at system-optimal times")
                    bulletRow(icon: "lock.shield", text: "Health data is encrypted when locked — syncs only run while the device is unlocked")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Tips", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    bulletRow(icon: "xmark.app", text: "Force-quitting the app disables ALL background sync until you reopen it")
                    bulletRow(icon: "battery.25percent", text: "Low Power Mode reduces background sync opportunities")
                    bulletRow(icon: "clock", text: "The sync frequency you set is a minimum interval — iOS controls exact timing")
                }
            }
        } header: {
            Text("Background Sync")
        }
    }

    private var healthKitSection: some View {
        Section {
            Button {
                Task { await requestHealthKitAuth() }
            } label: {
                Label("Review HealthKit Access", systemImage: "heart.fill")
            }
            .tint(.primary)
        } header: {
            Text("HealthKit")
        } footer: {
            Text("HealthPush needs permission to read your health data. You can manage individual data types in the Health app.")
        }
    }

    private var dataSection: some View {
        Section {
            Picker(selection: dataRetentionBinding) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            } label: {
                Label("Keep Sync History", systemImage: "calendar")
            }

            Button {
                showingSyncHistory = true
            } label: {
                Label("View Sync History", systemImage: "clock.arrow.circlepath")
            }
            .tint(.primary)

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("Reset Sync Data", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Data")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            } label: {
                Label("Version", systemImage: "info.circle.fill")
            }

            Link(destination: URL(string: "https://github.com/danburtenshaw/HealthPush")!) {
                HStack {
                    Label("GitHub Repository", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)

            LabeledContent {
                Text("MIT")
                    .foregroundStyle(.secondary)
            } label: {
                Label("License", systemImage: "doc.text.fill")
            }
        } header: {
            Text("About")
        } footer: {
            Text("HealthPush is open source. Your health data is never shared with third parties.")
        }
    }

    // MARK: Bindings

    /// Creates a binding for the sync-on-app-open computed property on AppState.
    private var syncOnAppOpenBinding: Binding<Bool> {
        Binding(
            get: { appState.syncOnAppOpen },
            set: { appState.syncOnAppOpen = $0 }
        )
    }

    /// Creates a binding for the data retention computed property on AppState.
    private var dataRetentionBinding: Binding<Int> {
        Binding(
            get: { appState.dataRetentionDays },
            set: { appState.dataRetentionDays = $0 }
        )
    }

    // MARK: Helpers

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Computed Properties

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Actions

    private func requestHealthKitAuth() async {
        do {
            try await syncEngine.requestHealthKitAuthorization(for: Set(HealthMetricType.allCases))
            appState.healthKitAuthorized = true
        } catch {
            appState.setError(error.localizedDescription)
        }
    }

    private func resetSyncData() {
        do {
            // Delete all sync records and clear destination-level sync cursors.
            try modelContext.delete(model: SyncRecord.self)

            let destinations = try modelContext.fetch(FetchDescriptor<DestinationConfig>())
            for destination in destinations {
                destination.lastSyncedAt = nil
                destination.needsFullSync = true
                destination.modifiedAt = .now
            }

            try modelContext.save()
        } catch {
            appState.setError("Failed to reset sync state: \(error.localizedDescription)")
            return
        }

        Task {
            await syncEngine.resetAnchors()
        }

        UserDefaults.standard.removeObject(forKey: "last_sync_time")
        UserDefaults.standard.removeObject(forKey: "next_scheduled_sync_time")
        UserDefaults.standard.removeObject(forKey: "total_syncs_completed")
        appState.dataPointsSyncedToday = 0
        appState.lastSyncTime = nil
        appState.lastSyncResult = nil
        appState.totalSyncsCompleted = 0
    }
}

// MARK: - Preview

#Preview {
    SettingsScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .modelContainer(for: [SyncRecord.self, DestinationConfig.self], inMemory: true)
}
