import SwiftData
import SwiftUI

// MARK: - SetupMode

/// Whether the setup screen is creating a new destination or editing an existing one.
enum SetupMode: Identifiable {
    case create
    case edit(DestinationConfig)

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(config): config.id.uuidString
        }
    }
}

// MARK: - HomeAssistantSetupScreen

/// Configuration screen for setting up a Home Assistant destination.
///
/// Provides fields for the HA webhook URL and optional webhook secret, a connection
/// test button with visual feedback, and a metric picker.
struct HomeAssistantSetupScreen: View {
    // MARK: Properties

    let mode: SetupMode

    @Environment(DestinationManager.self) private var destinationManager
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Home Assistant"
    @State private var baseURL = ""
    @State private var apiToken = ""
    @State private var hasStoredSecret = false
    @State private var removeStoredSecret = false
    @State private var enabledMetrics: Set<HealthMetricType> = Set(HealthMetricType.allCases)
    @State private var syncFrequency: SyncFrequency = .oneHour
    @State private var isEnabled = true

    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?
    @State private var showingMetricPicker = false
    @State private var showingDeleteConfirmation = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                authenticationSection
                testConnectionSection
                syncSection
                metricsSection

                if isEditing {
                    enabledSection
                    dangerZoneSection
                }
            }
            .navigationTitle(isEditing ? "Edit Destination" : "Add Home Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .onAppear { loadExistingConfig() }
            .sheet(isPresented: $showingMetricPicker) {
                HealthMetricsScreen(selectedMetrics: $enabledMetrics)
            }
            .alert("Delete Destination", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) { deleteDestination() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove this destination and stop all syncing to it.")
            }
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section {
            LabeledContent {
                TextField("My Home Assistant", text: $name)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Name", systemImage: "tag.fill")
            }

            TextField("Webhook URL", text: $baseURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Connection")
        } footer: {
            Text("Paste the webhook URL shown during HealthPush integration setup in Home Assistant.")
        }
    }

    private var authenticationSection: some View {
        Section {
            LabeledContent {
                SecureField(
                    hasStoredSecret && apiToken.isEmpty ? "Saved in Keychain" : "Webhook secret (optional)",
                    text: $apiToken
                )
                .multilineTextAlignment(.trailing)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            } label: {
                Label("Secret", systemImage: "lock.fill")
            }

            if isEditing && hasStoredSecret {
                Toggle(isOn: $removeStoredSecret) {
                    Label("Remove Saved Secret", systemImage: "trash")
                }
                .tint(.red)
            }
        } header: {
            Text("Security")
        } footer: {
            Text(securityFooterText)
        }
    }

    private var testConnectionSection: some View {
        Section {
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if isTesting {
                        ProgressView()
                    } else if let testResult {
                        testResultIndicator(testResult)
                    }
                }
            }
            .disabled(isTesting || baseURL.isEmpty)
            .accessibilityLabel(testConnectionAccessibilityLabel)
            .accessibilityHint(isTesting ? "" : "Verifies the webhook URL and secret are correct")
        }
    }

    private var syncSection: some View {
        Section {
            Picker(selection: $syncFrequency) {
                ForEach(SyncFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            } label: {
                Label("Sync Frequency", systemImage: "clock.fill")
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("How often to sync data to this destination. Background sync timing is approximate.")
        }
    }

    private var metricsSection: some View {
        Section {
            Button {
                showingMetricPicker = true
            } label: {
                HStack {
                    Label("Health Metrics", systemImage: "heart.text.square.fill")
                    Spacer()
                    Text("\(enabledMetrics.count) of \(HealthMetricType.allCases.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
            .accessibilityLabel("Health Metrics")
            .accessibilityValue("\(enabledMetrics.count) of \(HealthMetricType.allCases.count) selected")
            .accessibilityHint("Opens the metric picker")
        } header: {
            Text("Data")
        } footer: {
            if enabledMetrics.isEmpty {
                Text("Select at least one health metric to sync.")
                    .foregroundStyle(.red)
            } else {
                Text("Choose which health metrics to sync to this destination.")
            }
        }
    }

    private var enabledSection: some View {
        Section {
            Toggle(isOn: $isEnabled) {
                Label("Enabled", systemImage: "power")
            }
        } footer: {
            Text("Disable this destination to temporarily stop syncing without removing it.")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Destination", systemImage: "trash.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func testResultIndicator(_ result: ConnectionTestResult) -> some View {
        switch result {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failure(message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    private var testConnectionAccessibilityLabel: String {
        if isTesting {
            return "Testing connection"
        }
        if let testResult {
            switch testResult {
            case .success:
                return "Test Connection, passed"
            case let .failure(message):
                return "Test Connection, failed: \(message)"
            }
        }
        return "Test Connection"
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !enabledMetrics.isEmpty
    }

    // MARK: Data Loading

    private func loadExistingConfig() {
        guard case let .edit(config) = mode else { return }
        name = config.name
        baseURL = config.baseURL
        apiToken = ""
        hasStoredSecret = (try? config.hasStoredAPIToken) ?? !config.apiToken.isEmpty
        removeStoredSecret = false
        enabledMetrics = config.enabledMetrics
        syncFrequency = config.syncFrequency
        isEnabled = config.isEnabled
    }

    // MARK: Actions

    private func save() {
        let trimmedURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespaces)

        do {
            switch mode {
            case .create:
                _ = try destinationManager.createHomeAssistantDestination(
                    name: trimmedName,
                    baseURL: trimmedURL,
                    apiToken: trimmedToken,
                    enabledMetrics: enabledMetrics,
                    syncFrequency: syncFrequency,
                    modelContext: modelContext
                )

            case let .edit(config):
                config.name = trimmedName
                config.baseURL = trimmedURL
                if removeStoredSecret && trimmedToken.isEmpty {
                    try config.deleteStoredAPIToken()
                } else if !trimmedToken.isEmpty {
                    config.apiToken = trimmedToken
                }
                config.enabledMetrics = enabledMetrics
                config.syncFrequency = syncFrequency
                config.isEnabled = isEnabled
                try destinationManager.updateDestination(config, modelContext: modelContext)
            }
        } catch {
            appState.setError(error.localizedDescription)
            return
        }

        Task {
            do {
                try await syncEngine.requestHealthKitAuthorization(for: enabledMetrics)
                appState.healthKitAuthorized = true
            } catch {
                appState.healthKitAuthorized = false
                appState.setError(error.localizedDescription, showAlert: true)
            }
            dismiss()
        }
    }

    private func deleteDestination() {
        guard case let .edit(config) = mode else { return }
        do {
            try destinationManager.deleteDestination(config, modelContext: modelContext)
        } catch {
            appState.setError(error.localizedDescription)
            return
        }
        dismiss()
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil

        let effectiveToken: String = if !apiToken.trimmingCharacters(in: .whitespaces).isEmpty {
            apiToken.trimmingCharacters(in: .whitespaces)
        } else if case let .edit(config) = mode, !removeStoredSecret {
            (try? config.resolvedAPIToken) ?? ""
        } else {
            ""
        }

        let tempConfig = DestinationConfig(
            name: name,
            destinationType: .homeAssistant,
            baseURL: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
            apiToken: effectiveToken
        )

        do {
            let destination = try HomeAssistantDestination(
                config: tempConfig,
                migrateSecretsIfNeeded: false
            )
            let success = try await destination.testConnection()
            testResult = success ? .success : .failure("Test returned false")
        } catch {
            testResult = .failure(error.localizedDescription)
        }

        isTesting = false
    }

    private var securityFooterText: String {
        if !apiToken.trimmingCharacters(in: .whitespaces).isEmpty {
            return "This value will replace the currently saved secret when you save."
        }
        if isEditing && hasStoredSecret {
            if removeStoredSecret {
                return "The saved secret will be removed when you save. Leave this field empty if the webhook does not require a secret."
            }
            return "A secret is already stored in Keychain. Leave this field empty to keep it, or enter a new one to replace it."
        }
        return "If you set a webhook secret during integration setup, enter it here."
    }
}

// MARK: - ConnectionTestResult

private enum ConnectionTestResult {
    case success
    case failure(String)
}

// MARK: - Preview

#Preview("Create") {
    HomeAssistantSetupScreen(mode: .create)
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
