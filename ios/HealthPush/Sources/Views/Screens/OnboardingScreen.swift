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
    @State private var showingAddS3 = false
    @State private var showingAddHomeAssistant = false

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
            .sheet(isPresented: $showingAddS3) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                S3SetupScreen(mode: .create)
            }
            .sheet(isPresented: $showingAddHomeAssistant) {
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
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.95), Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 210)

                VStack(alignment: .leading, spacing: 14) {
                    Label("HealthPush", systemImage: "heart.text.clipboard.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Push your Apple Health data where you control it.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)

                    Text("No accounts. No subscriptions. No HealthPush cloud. Your iPhone sends data directly to the destinations you configure.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                trustPill("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
                trustPill("Local first", systemImage: "iphone")
                trustPill("No telemetry", systemImage: "lock.shield")
            }
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
        }
        .sectionCardStyle()
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your first destination")
                .font(.title3.weight(.semibold))

            checklistRow(
                title: "Add at least one destination",
                detail: "S3-compatible storage is the most direct export path today. Home Assistant is also available.",
                isComplete: !destinationManager.destinations.isEmpty
            )

            Button {
                showingAddS3 = true
            } label: {
                destinationOption(
                    title: "S3-Compatible Storage",
                    detail: "Recommended for MVP use. Direct export to AWS S3, MinIO, and other compatible endpoints with JSON or CSV output.",
                    systemImage: "externaldrive.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                showingAddHomeAssistant = true
            } label: {
                destinationOption(
                    title: "Home Assistant",
                    detail: "Best for dashboards and automations. Configure the custom integration, then paste the webhook URL.",
                    systemImage: "house.fill",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
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

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func destinationOption(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
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
