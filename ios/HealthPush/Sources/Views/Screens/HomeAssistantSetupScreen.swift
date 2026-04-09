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
/// Provides fields for the HA webhook URL and optional webhook secret, a floating
/// connection test bar with visual feedback, and a metric picker.
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
    @State private var includeSourceMetadata = false
    @State private var isEnabled = true

    @State private var connectionTestState: HAConnectionTestState = .idle
    @State private var showingMetricPicker = false
    @State private var showingDeleteConfirmation = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                authenticationSection
                syncSection
                metricsSection
                connectionTestSection

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
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
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

            HStack(spacing: HP.Spacing.sm) {
                TextField("Webhook URL", text: $baseURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !baseURL.trimmingCharacters(in: .whitespaces).isEmpty {
                    webhookValidationIcon
                }
            }

            if case let .invalid(message) = urlValidation, !message.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if urlValidation.isHTTP {
                Label(
                    "Insecure connection \u{2014} only use on trusted networks",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .listRowBackground(Color.orange.opacity(0.1))
            }
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

            Toggle(isOn: $includeSourceMetadata) {
                Label("Include Source Info", systemImage: "info.circle")
            }
        } header: {
            Text("Data")
        } footer: {
            if enabledMetrics.isEmpty {
                Text("Select at least one health metric to sync.")
                    .foregroundStyle(.red)
            } else if includeSourceMetadata {
                Text("Exports include which app or device recorded each measurement.")
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

    // MARK: Connection Test Section

    private var connectionTestSection: some View {
        Section {
            switch connectionTestState {
            case .idle:
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Test Connection")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(baseURL.trimmingCharacters(in: .whitespaces).isEmpty)

            case .testing:
                HStack(spacing: HP.Spacing.mdLg) {
                    Spacer()
                    ProgressView()
                    Text("Testing...")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

            case .success:
                HStack(spacing: HP.Spacing.md) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolRenderingMode(.hierarchical)
                    Text("Connected")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .transition(.opacity)

            case let .failure(message):
                HStack(spacing: HP.Spacing.md) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        } footer: {
            Text("Verify your webhook URL is reachable before saving.")
        }
        .accessibilityLabel(connectionTestAccessibilityLabel)
    }

    // MARK: Helpers

    /// Inline validation icon for the webhook URL field.
    @ViewBuilder
    private var webhookValidationIcon: some View {
        if urlValidation.isAcceptable {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
                .accessibilityLabel("Valid")
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .accessibilityLabel("Invalid")
        }
    }

    private var connectionTestAccessibilityLabel: String {
        switch connectionTestState {
        case .idle:
            return "Test Connection"
        case .testing:
            return "Testing connection"
        case .success:
            return "Connection test passed"
        case let .failure(message):
            return "Connection test failed: \(message)"
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var urlValidation: URLValidationResult {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .invalid("") }
        return URLValidator.validateWebhookURL(trimmed)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && urlValidation.isAcceptable
            && !enabledMetrics.isEmpty
    }

    // MARK: Data Loading

    private func loadExistingConfig() {
        guard case let .edit(config) = mode else { return }
        name = config.name
        if let haConfig = try? config.homeAssistantConfig {
            baseURL = haConfig.webhookURL
        }
        apiToken = ""
        hasStoredSecret = config.credentialKeys[CredentialField.webhookSecret] != nil
        removeStoredSecret = false
        enabledMetrics = config.enabledMetrics
        syncFrequency = config.syncFrequency
        includeSourceMetadata = config.includeSourceMetadata
        isEnabled = config.isEnabled
    }

    // MARK: Actions

    private func save() {
        let trimmedURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespaces)

        let validation = URLValidator.validateWebhookURL(trimmedURL)
        guard validation.isAcceptable else {
            appState.setError(validation.errorMessage ?? "Invalid URL")
            return
        }

        do {
            switch mode {
            case .create:
                let typeConfig = TypeSpecificConfig.homeAssistant(
                    HomeAssistantTypeConfig(webhookURL: trimmedURL)
                )
                var credentials: [String: String] = [:]
                if !trimmedToken.isEmpty {
                    credentials[CredentialField.webhookSecret] = trimmedToken
                }
                let newConfig = try destinationManager.createDestination(
                    name: trimmedName,
                    type: .homeAssistant,
                    typeConfig: typeConfig,
                    credentials: credentials,
                    enabledMetrics: enabledMetrics,
                    syncFrequency: syncFrequency,
                    modelContext: modelContext
                )
                newConfig.includeSourceMetadata = includeSourceMetadata

            case let .edit(config):
                config.name = trimmedName
                try config.setTypeConfig(.homeAssistant(
                    HomeAssistantTypeConfig(webhookURL: trimmedURL)
                ))
                if removeStoredSecret && trimmedToken.isEmpty {
                    try config.deleteCredential(for: CredentialField.webhookSecret)
                } else if !trimmedToken.isEmpty {
                    try config.setCredential(trimmedToken, for: CredentialField.webhookSecret)
                }
                config.enabledMetrics = enabledMetrics
                config.syncFrequency = syncFrequency
                config.includeSourceMetadata = includeSourceMetadata
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
        connectionTestState = .testing

        let effectiveToken: String = if !apiToken.trimmingCharacters(in: .whitespaces).isEmpty {
            apiToken.trimmingCharacters(in: .whitespaces)
        } else if case let .edit(config) = mode, !removeStoredSecret {
            (try? config.credential(for: CredentialField.webhookSecret)) ?? ""
        } else {
            ""
        }

        let destination = HomeAssistantDestination(
            webhookURL: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
            webhookSecret: effectiveToken
        )

        do {
            let success = try await destination.testConnection()
            if success {
                withAnimation { connectionTestState = .success }
                try? await Task.sleep(for: .seconds(3))
                if case .success = connectionTestState {
                    withAnimation { connectionTestState = .idle }
                }
            } else {
                withAnimation { connectionTestState = .failure("Test returned false") }
            }
        } catch {
            withAnimation { connectionTestState = .failure(error.localizedDescription) }
        }
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

// MARK: - HAConnectionTestState

/// Tracks the visual state of the floating connection test bar for HA setup.
private enum HAConnectionTestState {
    case idle
    case testing
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
