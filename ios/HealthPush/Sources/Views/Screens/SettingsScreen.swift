import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SettingsScreen

/// App settings screen with sync frequency, data retention, and about info.
struct SettingsScreen: View {
    // MARK: Properties

    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(DestinationManager.self) private var destinationManager
    @Environment(\.modelContext) private var modelContext

    @State private var showingSyncHistory = false
    @State private var showingResetConfirmation = false
    @State private var showingEraseConfirmation = false
    @State private var eraseConfirmationText = ""

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                backgroundSyncSection
                healthKitSection
                onboardingSection
                dataSection
                aboutSection
                eraseSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingSyncHistory) {
                SyncHistoryScreen()
            }
            .alert("Reset Sync Data", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) { resetSyncData() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(
                    "This will clear all sync history and HealthKit anchors, forcing a full re-sync. Your destination configurations will be preserved."
                )
            }
            .alert("Erase All Data", isPresented: $showingEraseConfirmation) {
                TextField("Type ERASE to confirm", text: $eraseConfirmationText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Erase Everything", role: .destructive) {
                    eraseAllData()
                }
                .disabled(eraseConfirmationText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("ERASE") != .orderedSame)
                Button("Cancel", role: .cancel) {
                    eraseConfirmationText = ""
                }
            } message: {
                Text(
                    "This will permanently delete all destinations, credentials, sync history, and settings. This cannot be undone."
                )
            }
        }
    }

    // MARK: Sections

    private var backgroundSyncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: HP.Spacing.lg) {
                Label("How Background Sync Works", systemImage: "info.circle")
                    .font(HP.Typography.cardTitle)

                VStack(alignment: .leading, spacing: HP.Spacing.sm) {
                    bulletRow(
                        icon: "applewatch",
                        text: "HealthKit delivery — syncs when new health data arrives from Apple Watch or other sources"
                    )
                    bulletRow(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Scheduled refresh — iOS runs background tasks at system-optimal times"
                    )
                    bulletRow(
                        icon: "lock.shield",
                        text: "Health data is encrypted when locked — syncs only run while the device is unlocked"
                    )
                }
            }

            VStack(alignment: .leading, spacing: HP.Spacing.lg) {
                Label("Tips", systemImage: "lightbulb.fill")
                    .font(HP.Typography.cardTitle)

                VStack(alignment: .leading, spacing: HP.Spacing.sm) {
                    bulletRow(icon: "xmark.app", text: "Force-quitting the app disables ALL background sync until you reopen it")
                    bulletRow(icon: "battery.25percent", text: "Low Power Mode reduces background sync opportunities")
                    bulletRow(icon: "clock", text: "The sync frequency you set is a minimum interval — iOS controls exact timing")
                }
            }

            if !appState.isBackgroundRefreshAvailable {
                VStack(alignment: .leading, spacing: HP.Spacing.md) {
                    Label("Background App Refresh is Off", systemImage: "exclamationmark.triangle.fill")
                        .font(HP.Typography.cardTitle)
                        .foregroundStyle(.orange)

                    Text("Background syncs will not run. Turn on Background App Refresh in Settings, or disable Low Power Mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .accessibilityHint("Opens iOS Settings to enable Background App Refresh")
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

            Button {
                if let url = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Health App", systemImage: "heart.text.clipboard")
            }
            .tint(.primary)
        } header: {
            Text("HealthKit")
        } footer: {
            Text(
                "HealthPush needs permission to read your health data. To change which data types are shared, open the Health app and go to Sharing > Apps > HealthPush."
            )
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
            .accessibilityHint("Clears all sync history and forces a full re-sync")
        } header: {
            Text("Data")
        }
    }

    private var onboardingSection: some View {
        Section {
            Button {
                appState.hasSeenOnboarding = false
            } label: {
                Label("Show Welcome Guide", systemImage: "sparkles.rectangle.stack.fill")
            }
            .tint(.primary)
        } header: {
            Text("Getting Started")
        } footer: {
            Text("Replay the welcome flow to review privacy notes, Health access, and destination setup.")
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
                        .accessibilityHidden(true)
                }
            }
            .tint(.primary)
            .accessibilityHint("Opens in Safari")

            LabeledContent {
                Text("MIT")
                    .foregroundStyle(.secondary)
            } label: {
                Label("License", systemImage: "doc.text.fill")
            }
        } header: {
            Text("About")
        } footer: {
            Text("HealthPush is open source. Your health data is never shared with third parties.\n\nDestination configurations are included in your iPhone's encrypted iCloud backup. Credentials (API keys, tokens) are stored in the Keychain and do not sync via backup \u{2014} you'll re-enter them if you restore to a new device.")
        }
    }

    private var eraseSection: some View {
        Section {
            Button(role: .destructive) {
                eraseConfirmationText = ""
                showingEraseConfirmation = true
            } label: {
                Label("Erase All HealthPush Data", systemImage: "trash.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityHint("Permanently deletes all destinations, credentials, sync history, and settings")
        } header: {
            Text("Danger Zone")
        } footer: {
            Text(
                "Permanently removes all data including destination credentials stored in the Keychain. You will need to set up HealthPush again from scratch."
            )
        }
    }

    // MARK: Bindings

    /// Creates a binding for the data retention computed property on AppState.
    private var dataRetentionBinding: Binding<Int> {
        Binding(
            get: { appState.dataRetentionDays },
            set: { appState.dataRetentionDays = $0 }
        )
    }

    // MARK: Helpers

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: HP.Spacing.md) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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

    private func eraseAllData() {
        BackgroundSyncScheduler.shared.cancelAllTasks()
        destinationManager.eraseAll(modelContext: modelContext, appState: appState)
        eraseConfirmationText = ""
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
        appState.hasEverSyncedData = false
    }
}

// MARK: - Preview

#Preview {
    SettingsScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [SyncRecord.self, DestinationConfig.self], inMemory: true)
}
