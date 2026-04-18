import SwiftData
import SwiftUI

// MARK: - S3SetupScreen

/// Configuration screen for setting up an S3-compatible destination.
///
/// Provides fields for bucket name, region, optional custom endpoint, access keys, path prefix,
/// export format, a floating connection test bar, and a metric picker.
struct S3SetupScreen: View {
    // MARK: Properties

    let mode: SetupMode

    @Environment(DestinationManager.self) private var destinationManager
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = DestinationType.s3.displayName
    @State private var bucketName = ""
    @State private var region = "us-east-1"
    @State private var customEndpoint = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var hasStoredAccessKeyID = false
    @State private var hasStoredSecretAccessKey = false
    @State private var pathPrefix = ""
    @State private var exportFormat: ExportFormat = .ndjson
    @State private var enabledMetrics: Set<HealthMetricType> = Set(HealthMetricType.allCases)
    @State private var syncFrequency: SyncFrequency = .oneHour
    @State private var syncStartDateOption: SyncStartDateOption = .last7Days
    @State private var syncStartDateCustom = Date.now.daysAgo(7)
    @State private var includeSourceMetadata = false
    @State private var isEnabled = true

    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var showingMetricPicker = false
    @State private var showingDeleteConfirmation = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                authenticationSection
                storageSection
                syncWindowSection
                metricsSection
                connectionTestSection

                if isEditing {
                    enabledSection
                    dangerZoneSection
                }
            }
            .navigationTitle(isEditing ? "Edit Destination" : "Add S3 Storage")
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
                TextField("My S3 Bucket", text: $name)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("Name", systemImage: "tag.fill")
            }

            LabeledContent {
                HStack(spacing: HP.Spacing.sm) {
                    TextField("my-health-data", text: $bucketName)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !bucketName.isEmpty {
                        fieldValidationIcon(isValid: S3TypeConfig.validateBucketName(bucketName) == nil)
                    }
                }
            } label: {
                Label("Bucket", systemImage: "externaldrive.fill")
            }

            LabeledContent {
                HStack(spacing: HP.Spacing.sm) {
                    TextField("Optional", text: $customEndpoint)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    if !customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty {
                        fieldValidationIcon(isValid: S3Client.validateEndpoint(customEndpoint) == nil)
                    }
                }
            } label: {
                Label("Endpoint", systemImage: "network")
            }

            if normalizedEndpoint.isEmpty {
                Picker(selection: $region) {
                    ForEach(Self.awsRegions, id: \.id) { region in
                        Text(region.name).tag(region.id)
                    }
                } label: {
                    Label("Region", systemImage: "globe")
                }
            } else {
                LabeledContent {
                    TextField("us-east-1", text: $region)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    Label("Region", systemImage: "globe")
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            if let error = S3TypeConfig.validateBucketName(bucketName), !bucketName.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
            } else if let error = endpointValidationError {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Text(connectionFooterText)
            }
        }
    }

    private var authenticationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: HP.Spacing.sm) {
                Text("Access Key ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(
                    hasStoredAccessKeyID && accessKeyID.isEmpty ? "Saved in Keychain" : "AKIA...",
                    text: $accessKeyID
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .fontDesign(.monospaced)
            }
            .padding(.vertical, HP.Spacing.xxs)

            VStack(alignment: .leading, spacing: HP.Spacing.sm) {
                Text("Secret Access Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField(
                    hasStoredSecretAccessKey && secretAccessKey.isEmpty ? "Saved in Keychain" : "Secret access key",
                    text: $secretAccessKey
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .fontDesign(.monospaced)
            }
            .padding(.vertical, HP.Spacing.xxs)
        } header: {
            Text("Authentication")
        } footer: {
            Text(authenticationFooterText)
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: HP.Spacing.sm) {
                    TextField("health/data", text: $pathPrefix)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !pathPrefix.isEmpty {
                        fieldValidationIcon(isValid: S3TypeConfig.validatePathPrefix(pathPrefix) == nil)
                    }
                }
            } label: {
                Label("Path Prefix", systemImage: "folder.fill")
            }

            Picker(selection: $exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            } label: {
                Label("Format", systemImage: "doc.text.fill")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Storage")
        } footer: {
            if let error = S3TypeConfig.validatePathPrefix(pathPrefix) {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Text("\(exportFormat.subtitle). Files stored as \(examplePath).")
            }
        }
    }

    private var syncWindowSection: some View {
        Section {
            Picker(selection: $syncFrequency) {
                ForEach(SyncFrequency.allCases) { freq in
                    Text(freq.displayName).tag(freq)
                }
            } label: {
                Label("Sync Frequency", systemImage: "clock.fill")
            }

            Picker(selection: $syncStartDateOption) {
                ForEach(SyncStartDateOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            } label: {
                Label("Sync From", systemImage: "calendar")
            }

            if syncStartDateOption == .custom {
                DatePicker(
                    "Start Date",
                    selection: $syncStartDateCustom,
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
        } header: {
            Text("Sync Window")
        } footer: {
            Text(
                "How far back to sync health data. Changing this triggers a full re-sync. After that, only the last 3 days are re-checked each time."
            )
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
                .disabled(!isTestConnectionEnabled)

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
            Text("Verify your bucket and credentials are working before saving.")
        }
        .accessibilityLabel(connectionTestAccessibilityLabel)
    }

    // MARK: Helpers

    /// A small validation icon shown inline next to form fields.
    @ViewBuilder
    private func fieldValidationIcon(isValid: Bool) -> some View {
        Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(isValid ? .green : .red)
            .font(.subheadline)
            .accessibilityLabel(isValid ? "Valid" : "Invalid")
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

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && S3TypeConfig.validateBucketName(bucketName) == nil
            && !bucketName.isEmpty
            && endpointValidationError == nil
            && !trimmedRegion.isEmpty
            && hasValidAccessKeyID
            && hasValidSecretAccessKey
            && S3TypeConfig.validatePathPrefix(pathPrefix) == nil
            && !enabledMetrics.isEmpty
    }

    private var isTestConnectionEnabled: Bool {
        !bucketName.isEmpty
            && hasValidAccessKeyID
            && hasValidSecretAccessKey
            && endpointValidationError == nil
            && !trimmedRegion.isEmpty
    }

    private var examplePath: String {
        let prefix = pathPrefix.isEmpty ? "" : "\(pathPrefix)/"
        return "\(prefix)v1/heart_rate/2026/04/03/data.\(exportFormat.fileExtension)"
    }

    // MARK: Data Loading

    private func loadExistingConfig() {
        guard case let .edit(config) = mode else { return }
        name = config.name
        if let s3Config = try? config.s3Config {
            bucketName = s3Config.bucket
            region = s3Config.region.isEmpty ? "us-east-1" : s3Config.region
            customEndpoint = s3Config.endpoint
            pathPrefix = s3Config.pathPrefix
            exportFormat = s3Config.exportFormat
            syncStartDateOption = s3Config.syncStartDateOption
            syncStartDateCustom = s3Config.syncStartDateCustom ?? Date.now.daysAgo(7)
        }
        accessKeyID = ""
        secretAccessKey = ""
        hasStoredAccessKeyID = config.credentialKeys[CredentialField.accessKeyID] != nil
        hasStoredSecretAccessKey = config.credentialKeys[CredentialField.secretAccessKey] != nil
        enabledMetrics = config.enabledMetrics
        syncFrequency = config.syncFrequency
        includeSourceMetadata = config.includeSourceMetadata
        isEnabled = config.isEnabled
    }

    // MARK: Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBucket = bucketName.trimmingCharacters(in: .whitespaces).lowercased()
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEndpoint = S3Client.normalizedEndpoint(customEndpoint)
        let trimmedAccessKey = accessKeyID.trimmingCharacters(in: .whitespaces)
        let trimmedSecretKey = secretAccessKey.trimmingCharacters(in: .whitespaces)
        let trimmedPrefix = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        do {
            switch mode {
            case .create:
                let typeConfig = TypeSpecificConfig.s3(S3TypeConfig(
                    bucket: trimmedBucket,
                    region: trimmedRegion,
                    endpoint: normalizedEndpoint,
                    pathPrefix: trimmedPrefix,
                    exportFormatRaw: exportFormat.rawValue,
                    syncStartDateOptionRaw: syncStartDateOption.rawValue,
                    syncStartDateCustom: syncStartDateOption == .custom ? syncStartDateCustom : nil
                ))
                let credentials: [String: String] = [
                    CredentialField.accessKeyID: trimmedAccessKey,
                    CredentialField.secretAccessKey: trimmedSecretKey
                ]
                let newConfig = try destinationManager.createDestination(
                    name: trimmedName,
                    type: .s3,
                    typeConfig: typeConfig,
                    credentials: credentials,
                    enabledMetrics: enabledMetrics,
                    syncFrequency: syncFrequency,
                    modelContext: modelContext
                )
                newConfig.includeSourceMetadata = includeSourceMetadata

            case let .edit(config):
                let currentS3Config = try? config.s3Config
                let startDateChanged = currentS3Config?.syncStartDateOption != syncStartDateOption
                    || (syncStartDateOption == .custom && currentS3Config?.syncStartDateCustom != syncStartDateCustom)

                config.name = trimmedName
                try config.setTypeConfig(.s3(S3TypeConfig(
                    bucket: trimmedBucket,
                    region: trimmedRegion,
                    endpoint: normalizedEndpoint,
                    pathPrefix: trimmedPrefix,
                    exportFormatRaw: exportFormat.rawValue,
                    syncStartDateOptionRaw: syncStartDateOption.rawValue,
                    syncStartDateCustom: syncStartDateOption == .custom ? syncStartDateCustom : nil
                )))
                if !trimmedAccessKey.isEmpty {
                    try config.setCredential(trimmedAccessKey, for: CredentialField.accessKeyID)
                }
                if !trimmedSecretKey.isEmpty {
                    try config.setCredential(trimmedSecretKey, for: CredentialField.secretAccessKey)
                }
                config.enabledMetrics = enabledMetrics
                config.syncFrequency = syncFrequency
                config.includeSourceMetadata = includeSourceMetadata
                config.isEnabled = isEnabled

                if startDateChanged {
                    config.needsFullSync = true
                }

                try destinationManager.updateDestination(config, modelContext: modelContext)
            }
        } catch {
            appState.setError(error.localizedDescription)
            return
        }

        let isCreating = !isEditing
        Task {
            do {
                try await syncEngine.requestHealthKitAuthorization(for: enabledMetrics)
                appState.healthKitAuthorized = true
            } catch {
                appState.healthKitAuthorized = false
                appState.setError(error.localizedDescription, showAlert: true)
            }
            if isCreating {
                appState.pendingFirstSync = true
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

        let effectiveAccessKeyID: String = if !accessKeyID.trimmingCharacters(in: .whitespaces).isEmpty {
            accessKeyID.trimmingCharacters(in: .whitespaces)
        } else if case let .edit(config) = mode {
            (try? config.credential(for: CredentialField.accessKeyID)) ?? ""
        } else {
            ""
        }

        let effectiveSecretAccessKey: String = if !secretAccessKey.trimmingCharacters(in: .whitespaces).isEmpty {
            secretAccessKey.trimmingCharacters(in: .whitespaces)
        } else if case let .edit(config) = mode {
            (try? config.credential(for: CredentialField.secretAccessKey)) ?? ""
        } else {
            ""
        }

        let client = S3Client(
            bucket: bucketName.trimmingCharacters(in: .whitespaces).lowercased(),
            region: trimmedRegion,
            accessKeyID: effectiveAccessKeyID,
            secretAccessKey: effectiveSecretAccessKey,
            endpointOverride: normalizedEndpoint
        )

        do {
            let success = try await client.testConnection()
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

    private var hasValidAccessKeyID: Bool {
        let trimmed = accessKeyID.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty || (isEditing && hasStoredAccessKeyID)
    }

    private var hasValidSecretAccessKey: Bool {
        let trimmed = secretAccessKey.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty || (isEditing && hasStoredSecretAccessKey)
    }

    private var normalizedEndpoint: String {
        S3Client.normalizedEndpoint(customEndpoint)
    }

    private var endpointValidationError: String? {
        S3Client.validateEndpoint(customEndpoint)
    }

    private var trimmedRegion: String {
        region.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authenticationFooterText: String {
        if isEditing && (hasStoredAccessKeyID || hasStoredSecretAccessKey) {
            return "Credentials are already stored in Keychain. Leave fields empty to keep them, or enter replacements to rotate them."
        }
        return "Credentials need read and write access to the bucket. AWS IAM keys work for S3, and compatible systems usually provide equivalent access keys."
    }

    private var connectionFooterText: String {
        if normalizedEndpoint.isEmpty {
            return "Leave the endpoint blank to use AWS S3. Bucket names still follow S3 naming rules."
        }

        return "Use a full endpoint such as https://s3.example.com or http://192.168.1.10:9000 for MinIO and other S3-compatible storage."
    }

    // MARK: AWS Regions

    private static let awsRegions: [(id: String, name: String)] = [
        ("us-east-1", "US East (N. Virginia)"),
        ("us-east-2", "US East (Ohio)"),
        ("us-west-1", "US West (N. California)"),
        ("us-west-2", "US West (Oregon)"),
        ("af-south-1", "Africa (Cape Town)"),
        ("ap-east-1", "Asia Pacific (Hong Kong)"),
        ("ap-south-1", "Asia Pacific (Mumbai)"),
        ("ap-south-2", "Asia Pacific (Hyderabad)"),
        ("ap-southeast-1", "Asia Pacific (Singapore)"),
        ("ap-southeast-2", "Asia Pacific (Sydney)"),
        ("ap-northeast-1", "Asia Pacific (Tokyo)"),
        ("ap-northeast-2", "Asia Pacific (Seoul)"),
        ("ap-northeast-3", "Asia Pacific (Osaka)"),
        ("ca-central-1", "Canada (Central)"),
        ("eu-central-1", "Europe (Frankfurt)"),
        ("eu-west-1", "Europe (Ireland)"),
        ("eu-west-2", "Europe (London)"),
        ("eu-west-3", "Europe (Paris)"),
        ("eu-north-1", "Europe (Stockholm)"),
        ("eu-south-1", "Europe (Milan)"),
        ("me-south-1", "Middle East (Bahrain)"),
        ("me-central-1", "Middle East (UAE)"),
        ("sa-east-1", "South America (Sao Paulo)")
    ]
}

// MARK: - ConnectionTestState

/// Tracks the visual state of the floating connection test bar.
private enum ConnectionTestState {
    case idle
    case testing
    case success
    case failure(String)
}

// MARK: - Preview

#Preview("Create") {
    S3SetupScreen(mode: .create)
        .environment(DestinationManager())
        .environment(AppState())
        .environment(SyncEngine())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
