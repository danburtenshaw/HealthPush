import SwiftUI
import SwiftData

// MARK: - OnboardingScreen

/// First-run onboarding flow focused on trust, permissions, and activation.
struct OnboardingScreen: View {

    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(DestinationManager.self) private var destinationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var requestingHealthAccess = false
    @State private var showingAddDestination = false
    @State private var showingSetupS3 = false
    @State private var showingSetupHomeAssistant = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    activationSection
                    destinationSection
                    footerActions
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        finishOnboarding()
                    }
                }
            }
            .sheet(isPresented: $showingAddDestination) {
                AddDestinationSheet { type in
                    switch type {
                    case .s3: showingSetupS3 = true
                    case .homeAssistant: showingSetupHomeAssistant = true
                    }
                }
            }
            .sheet(isPresented: $showingSetupS3) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                S3SetupScreen(mode: .create)
            }
            .sheet(isPresented: $showingSetupHomeAssistant) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                HomeAssistantSetupScreen(mode: .create)
            }
            .onChange(of: destinationManager.destinations.count) { _, count in
                if count > 0 {
                    finishOnboarding()
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Label("HealthPush", systemImage: "heart.text.clipboard.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Push your Apple Health data where you control it.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No accounts. No subscriptions. No HealthPush cloud. Your iPhone sends data directly to the destinations you configure.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.95), Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                trustPill("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
                trustPill("Local first", systemImage: "iphone")
                trustPill("No telemetry", systemImage: "lock.shield")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open source. Local first. No telemetry.")
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before your first sync")
                .font(.title3.weight(.semibold))

            checklistRow(
                title: "Grant Apple Health access",
                detail: "HealthPush only reads the metrics you approve.",
                isComplete: appState.healthKitAuthorized
            )

            Button {
                Task { await requestHealthAccess() }
            } label: {
                HStack {
                    Label(
                        appState.healthKitAuthorized ? "Health Access Granted" : "Review Health Access",
                        systemImage: appState.healthKitAuthorized ? "checkmark.circle.fill" : "heart.fill"
                    )
                    Spacer()
                    if requestingHealthAccess {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(requestingHealthAccess)
            .accessibilityLabel(appState.healthKitAuthorized ? "Health Access Granted" : "Review Health Access")
            .accessibilityHint(appState.healthKitAuthorized ? "" : "Opens the Apple Health permissions dialog")
        }
        .sectionCardStyle()
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up a destination")
                .font(.title3.weight(.semibold))

            checklistRow(
                title: "Add at least one destination",
                detail: "Choose where your health data goes — S3 storage, Home Assistant, and more.",
                isComplete: !destinationManager.destinations.isEmpty
            )

            Button {
                showingAddDestination = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Destination")
                            .font(.headline)
                        Text("Pick from available destination types")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Destination")
            .accessibilityHint("Opens destination type picker")
        }
        .sectionCardStyle()
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You can revisit this guide from Settings at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                finishOnboarding()
            } label: {
                Text(destinationManager.destinations.isEmpty ? "Continue to App" : "Go to Dashboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Closes the welcome guide")
        }
    }

    private func trustPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private func checklistRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isComplete ? "complete" : "incomplete"). \(detail)")
    }

    private func requestHealthAccess() async {
        requestingHealthAccess = true
        defer { requestingHealthAccess = false }

        do {
            try await syncEngine.requestHealthKitAuthorization(for: Set(HealthMetricType.allCases))
            appState.healthKitAuthorized = true
        } catch {
            appState.healthKitAuthorized = false
            appState.setError(error.localizedDescription)
        }
    }

    private func finishOnboarding() {
        appState.hasSeenOnboarding = true
        dismiss()
    }
}

// MARK: - SectionCardStyle

private extension View {
    func sectionCardStyle() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

#Preview {
    OnboardingScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
