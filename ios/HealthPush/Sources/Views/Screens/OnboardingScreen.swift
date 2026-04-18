import SwiftData
import SwiftUI

// MARK: - OnboardingScreen

/// First-run onboarding as a progressive 3-step flow.
///
/// Each step follows the same rhythm — progress bar, visual, large title,
/// body copy, primary CTA, skip — so the user always knows where they are
/// and how to move forward. The visuals are the main differentiator:
/// a data-flow diagram on step one, permission tiles on step two, and
/// destination picker tiles on step three.
struct OnboardingScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(DestinationManager.self) private var destinationManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .flow
    @State private var requestingHealthAccess = false
    @State private var showingAddDestination = false
    @State private var showingSetupS3 = false
    @State private var showingSetupHomeAssistant = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, HP.Spacing.xxxl)
                    .padding(.top, HP.Spacing.xl)

                TabView(selection: $step) {
                    flowStep.tag(Step.flow)
                    permissionsStep.tag(Step.permissions)
                    destinationStep.tag(Step.destination)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: step)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { finishOnboarding() }
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
                if count > 0 { finishOnboarding() }
            }
        }
    }

    // MARK: Progress bar

    private var progressBar: some View {
        HStack(spacing: HP.Spacing.sm) {
            ForEach(Step.allCases) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.primary : Color.primary.opacity(0.12))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    // MARK: Step 1 — Data flow

    private var flowStep: some View {
        StepScaffold(
            visual: AnyView(DataFlowVisual()),
            title: "Your health data.\nYour servers.",
            message: "HealthPush reads from Apple Health and pushes to destinations you control. Nothing routes through a HealthPush backend. No accounts, no subscriptions.",
            primaryTitle: "Begin setup",
            onPrimary: { advance() }
        )
    }

    // MARK: Step 2 — Permissions

    private var permissionsStep: some View {
        StepScaffold(
            visual: AnyView(PermissionTiles(
                healthGranted: appState.healthKitAuthorized,
                backgroundOn: appState.isBackgroundRefreshAvailable
            )),
            title: "Two permissions.\nThen you're done.",
            message: "HealthKit lets HealthPush read your metrics — only the ones you approve. Background App Refresh keeps syncs running while the phone is locked.",
            primaryTitle: appState.healthKitAuthorized ? "Continue" : "Grant Apple Health access",
            onPrimary: {
                if appState.healthKitAuthorized {
                    advance()
                } else {
                    Task { await requestHealthAccess() }
                }
            },
            secondary: requestingHealthAccess ? AnyView(ProgressView()) : nil
        )
    }

    // MARK: Step 3 — Destination

    private var destinationStep: some View {
        StepScaffold(
            visual: AnyView(DestinationTiles()),
            title: "Pick a destination.",
            message: "Home Assistant is the fastest path if you already have a local instance. S3 (or any S3-compatible bucket) is the best archive. Add more anytime from the dashboard.",
            primaryTitle: "Add destination",
            onPrimary: { showingAddDestination = true }
        )
    }

    // MARK: Actions

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(.easeInOut(duration: 0.25)) { step = next }
    }

    private func requestHealthAccess() async {
        requestingHealthAccess = true
        defer { requestingHealthAccess = false }

        do {
            try await syncEngine.requestHealthKitAuthorization(for: Set(HealthMetricType.allCases))
            appState.healthKitAuthorized = true
            advance()
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

// MARK: - Step

private enum Step: Int, CaseIterable, Identifiable, Hashable {
    case flow
    case permissions
    case destination

    var id: Int {
        rawValue
    }

    var next: Step? {
        Step(rawValue: rawValue + 1)
    }
}

// MARK: - StepScaffold

/// A shared layout for each onboarding step: visual on top, large title,
/// body, then a pinned CTA. Keeping the rhythm constant across steps reduces
/// cognitive load — the user trusts where the "next" button will be.
private struct StepScaffold: View {
    let visual: AnyView
    let title: String
    let message: String
    let primaryTitle: String
    let onPrimary: () -> Void
    var secondary: AnyView?

    var body: some View {
        VStack(spacing: HP.Spacing.xxxl) {
            ScrollView {
                VStack(alignment: .leading, spacing: HP.Spacing.xxxl) {
                    visual
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .padding(.top, HP.Spacing.xl)

                    VStack(alignment: .leading, spacing: HP.Spacing.lg) {
                        Text(title)
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .kerning(-0.8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, HP.Spacing.xxxl)
                .padding(.bottom, HP.Spacing.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: HP.Spacing.lg) {
                if let secondary {
                    secondary
                }
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: HP.Radius.sheet, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, HP.Spacing.xxxl)
            .padding(.bottom, HP.Spacing.xxl)
        }
    }
}

// MARK: - DataFlowVisual

/// Diagram: iPhone on the left, dashed HTTPS arrow, user's server on the right.
/// Reinforces the "direct delivery, no backend" message from step one's body.
private struct DataFlowVisual: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let primary = scheme == .dark ? Color.white : Color.black
            let muted = primary.opacity(0.5)

            // iPhone outline
            let phoneWidth: CGFloat = 70
            let phoneHeight: CGFloat = 118
            let phoneX: CGFloat = size.width * 0.12
            let phoneY: CGFloat = (size.height - phoneHeight) / 2

            let phone = RoundedRectangle(cornerRadius: 14, style: .continuous)
                .path(in: CGRect(x: phoneX, y: phoneY, width: phoneWidth, height: phoneHeight))
            context.stroke(phone, with: .color(primary), lineWidth: 1.5)

            // iPhone screen
            let screen = RoundedRectangle(cornerRadius: 6, style: .continuous)
                .path(in: CGRect(x: phoneX + 6, y: phoneY + 10, width: phoneWidth - 12, height: phoneHeight - 20))
            context.fill(screen, with: .color(Color.accentColor.opacity(0.14)))

            // Heartbeat line inside phone
            var heartbeat = Path()
            let hx = phoneX + 12
            let hy = phoneY + phoneHeight / 2
            heartbeat.move(to: CGPoint(x: hx, y: hy))
            heartbeat.addLine(to: CGPoint(x: hx + 8, y: hy))
            heartbeat.addLine(to: CGPoint(x: hx + 14, y: hy - 12))
            heartbeat.addLine(to: CGPoint(x: hx + 20, y: hy + 16))
            heartbeat.addLine(to: CGPoint(x: hx + 26, y: hy - 6))
            heartbeat.addLine(to: CGPoint(x: hx + 32, y: hy))
            heartbeat.addLine(to: CGPoint(x: hx + 46, y: hy))
            context.stroke(heartbeat, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Server box on right
            let serverWidth: CGFloat = 84
            let serverHeight: CGFloat = 96
            let serverX = size.width - serverWidth - size.width * 0.12
            let serverY = (size.height - serverHeight) / 2

            let server = RoundedRectangle(cornerRadius: 10, style: .continuous)
                .path(in: CGRect(x: serverX, y: serverY, width: serverWidth, height: serverHeight))
            context.fill(server, with: .color(primary))

            // Server LEDs
            let accent = Color.accentColor
            let ledWidth = serverWidth - 24
            context.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: serverX + 12, y: serverY + 18, width: ledWidth, height: 6)),
                with: .color(accent)
            )
            context.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: serverX + 12, y: serverY + 32, width: ledWidth, height: 6)),
                with: .color(Color.white.opacity(0.35))
            )
            context.fill(
                RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: serverX + 12, y: serverY + 46, width: ledWidth - 16, height: 6)),
                with: .color(Color.white.opacity(0.35))
            )
            let statusDot = Circle().path(in: CGRect(x: serverX + serverWidth - 16, y: serverY + serverHeight - 16, width: 6, height: 6))
            context.fill(statusDot, with: .color(.green))

            // Dashed arrow between them
            let arrowStart = CGPoint(x: phoneX + phoneWidth + 6, y: size.height / 2)
            let arrowEnd = CGPoint(x: serverX - 6, y: size.height / 2)
            var arrow = Path()
            arrow.move(to: arrowStart)
            arrow.addLine(to: CGPoint(x: arrowEnd.x - 2, y: arrowEnd.y))
            context.stroke(arrow, with: .color(primary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
            var arrowHead = Path()
            arrowHead.move(to: CGPoint(x: arrowEnd.x - 8, y: arrowEnd.y - 4))
            arrowHead.addLine(to: arrowEnd)
            arrowHead.addLine(to: CGPoint(x: arrowEnd.x - 8, y: arrowEnd.y + 4))
            context.stroke(arrowHead, with: .color(primary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Labels
            let iphoneLabel = Text("IPHONE")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(muted)
            context.draw(iphoneLabel, at: CGPoint(x: phoneX + phoneWidth / 2, y: phoneY + phoneHeight + 14), anchor: .center)

            let httpsLabel = Text("HTTPS")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(muted)
            context.draw(httpsLabel, at: CGPoint(x: (arrowStart.x + arrowEnd.x) / 2, y: arrowStart.y - 12), anchor: .center)

            let serverLabel = Text("YOUR SERVER")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(muted)
            context.draw(serverLabel, at: CGPoint(x: serverX + serverWidth / 2, y: serverY + serverHeight + 14), anchor: .center)
        }
        .accessibilityLabel("Diagram showing data flowing directly from iPhone over HTTPS to your own server.")
    }
}

// MARK: - PermissionTiles

private struct PermissionTiles: View {
    let healthGranted: Bool
    let backgroundOn: Bool

    var body: some View {
        VStack(spacing: HP.Spacing.lg) {
            Tile(
                icon: "heart.fill",
                iconColor: .white,
                iconBackground: Color.red,
                title: "Apple Health",
                subtitle: "Read metrics you approve",
                granted: healthGranted
            )
            Tile(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .white,
                iconBackground: Color.accentColor,
                title: "Background Refresh",
                subtitle: "Syncs run while locked",
                granted: backgroundOn
            )
        }
        .padding(.horizontal, HP.Spacing.xl)
    }
}

private struct Tile: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String
    let granted: Bool

    var body: some View {
        HStack(spacing: HP.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                    .fill(iconBackground)
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: HP.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
            }
        }
        .padding(HP.Spacing.lgXl)
        .background {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

// MARK: - DestinationTiles

/// Four destination icons arranged in a row, with the first one scaled up to
/// signal the recommended starting point.
private struct DestinationTiles: View {
    private struct Item: Identifiable {
        let id = UUID()
        let systemImage: String
        let label: String
        let featured: Bool
    }

    private let items: [Item] = [
        Item(systemImage: "house.fill", label: "Home Assistant", featured: true),
        Item(systemImage: "externaldrive.fill", label: "S3", featured: false),
        Item(systemImage: "network", label: "Webhook", featured: false),
        Item(systemImage: "antenna.radiowaves.left.and.right", label: "MQTT", featured: false)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: HP.Spacing.lg) {
            ForEach(items) { item in
                VStack(spacing: HP.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: item.featured ? 78 : 64, height: item.featured ? 78 : 64)
                            .overlay {
                                RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                            .shadow(
                                color: .black.opacity(item.featured ? 0.12 : 0),
                                radius: item.featured ? 14 : 0,
                                y: item.featured ? 6 : 0
                            )

                        Image(systemName: item.systemImage)
                            .font(.system(size: item.featured ? 26 : 20, weight: .semibold))
                            .foregroundStyle(item.featured ? Color.accentColor : .primary)
                            .symbolRenderingMode(.hierarchical)
                    }

                    Text(item.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.featured ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, HP.Spacing.xl)
    }
}

// MARK: - Preview

#Preview {
    OnboardingScreen()
        .environment(AppState())
        .environment(SyncEngine())
        .environment(DestinationManager())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
