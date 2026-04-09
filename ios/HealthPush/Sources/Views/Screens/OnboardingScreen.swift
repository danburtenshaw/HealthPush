import SwiftData
import SwiftUI

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
    @State private var trustPillsAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HP.Spacing.xxxl) {
                    heroSection
                    dataPreviewSection
                    activationSection
                    destinationSection
                    footerActions
                }
                .padding(.horizontal, HP.Spacing.xxl)
                .padding(.top, HP.Spacing.xxxl)
                .padding(.bottom, HP.Spacing.jumbo)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        VStack(alignment: .leading, spacing: HP.Spacing.xl) {
            VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
                Label("HealthPush", systemImage: "heart.text.clipboard.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Push your Apple Health data where you control it.")
                    .font(HP.Typography.heroTitle)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "No accounts. No subscriptions. No HealthPush cloud. Your iPhone sends data directly to the destinations you configure."
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HP.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HP.Radius.hero, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.95), Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .accessibilityElement(children: .combine)

            HStack(spacing: HP.Spacing.lg) {
                trustPill("Open source", systemImage: "chevron.left.forwardslash.chevron.right")
                trustPill("Local first", systemImage: "iphone")
                trustPill("No telemetry", systemImage: "lock.shield")
            }
            .symbolEffect(.bounce, value: trustPillsAppeared)
            .onAppear { trustPillsAppeared = true }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open source. Local first. No telemetry.")
        }
    }

    private var dataPreviewSection: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
            VStack(alignment: .leading, spacing: HP.Spacing.mdLg) {
                Label("What HealthPush reads", systemImage: "heart.text.clipboard")
                    .font(.subheadline.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)

                Text("Steps \u{00B7} Heart Rate \u{00B7} Sleep \u{00B7} Weight \u{00B7} Blood Pressure \u{00B7} and 18 more")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: HP.Spacing.mdLg) {
                Label("What it never touches", systemImage: "hand.raised.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text("Location \u{00B7} Notes \u{00B7} Photos \u{00B7} Contacts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(HP.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: HP.Radius.section, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What HealthPush reads: Steps, Heart Rate, Sleep, Weight, Blood Pressure, and 18 more. What it never touches: Location, Notes, Photos, Contacts.")
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
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
                .padding(.horizontal, HP.Spacing.xl)
                .padding(.vertical, HP.Spacing.lgXl)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: HP.Radius.sheet, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(requestingHealthAccess)
            .accessibilityLabel(appState.healthKitAuthorized ? "Health Access Granted" : "Review Health Access")
            .accessibilityHint(appState.healthKitAuthorized ? "" : "Opens the Apple Health permissions dialog")
        }
        .sectionCardStyle()
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lgXl) {
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
                HStack(spacing: HP.Spacing.lgXl) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: HP.Spacing.xxs) {
                        Text("Add Destination")
                            .font(HP.Typography.sectionTitle)
                        Text("Pick from available destination types")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(HP.Spacing.xl)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: HP.Radius.sheet, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add Destination")
            .accessibilityHint("Opens destination type picker")
        }
        .sectionCardStyle()
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: HP.Spacing.lg) {
            Text("You can revisit this guide from Settings at any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                finishOnboarding()
            } label: {
                Text(destinationManager.destinations.isEmpty ? "Continue to App" : "Go to Dashboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: HP.Radius.sheet, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Closes the welcome guide")
        }
    }

    private func trustPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HP.Spacing.lg)
            .padding(.vertical, HP.Spacing.md)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private func checklistRow(title: String, detail: String, isComplete: Bool) -> some View {
        HStack(alignment: .top, spacing: HP.Spacing.lg) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isComplete ? Color.green : Color.secondary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HP.Spacing.xs) {
                Text(title)
                    .font(HP.Typography.sectionTitle)
                Text(detail)
                    .font(HP.Typography.cardBody)
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
        padding(HP.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: HP.Radius.section, style: .continuous))
    }
}

#Preview {
    OnboardingScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
