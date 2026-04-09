import SwiftData
import SwiftUI

// MARK: - DestinationsScreen

/// Screen listing all configured sync destinations with options to add, edit, or delete.
struct DestinationsScreen: View {
    // MARK: Properties

    @Environment(DestinationManager.self) private var destinationManager
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddSheet = false
    @State private var showingAddS3Sheet = false
    @State private var showingDestinationPicker = false
    @State private var selectedConfig: DestinationConfig?

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if destinationManager.destinations.isEmpty {
                    emptyState
                } else {
                    destinationList
                }
            }
            .navigationTitle("Destinations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDestinationPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add Destination")
                    .accessibilityHint("Choose a destination type to add")
                }
            }
            .sheet(isPresented: $showingDestinationPicker) {
                AddDestinationSheet { type in
                    switch type {
                    case .s3: showingAddS3Sheet = true
                    case .homeAssistant: showingAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                HomeAssistantSetupScreen(mode: .create)
            }
            .sheet(isPresented: $showingAddS3Sheet) {
                destinationManager.loadDestinations(modelContext: modelContext)
            } content: {
                S3SetupScreen(mode: .create)
            }
            .sheet(item: $selectedConfig) { config in
                if config.destinationType == .s3 {
                    S3SetupScreen(mode: .edit(config))
                } else {
                    HomeAssistantSetupScreen(mode: .edit(config))
                }
            }
        }
    }

    // MARK: Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Destinations", systemImage: "arrow.triangle.branch")
        } description: {
            Text("Add a destination to start syncing your Apple Health data.")
        } actions: {
            Button {
                showingDestinationPicker = true
            } label: {
                Text("Add Destination")
                    .font(.headline)
                    .padding(.horizontal, HP.Spacing.xxl)
                    .padding(.vertical, HP.Spacing.mdLg)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var destinationList: some View {
        ScrollView {
            LazyVStack(spacing: HP.Spacing.lg) {
                ForEach(destinationManager.destinations, id: \.id) { config in
                    Button {
                        selectedConfig = config
                    } label: {
                        DestinationCard(config: config)
                    }
                    .buttonStyle(.plain)
                    .scrollTransition { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.3)
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                    }
                    .accessibilityHint("Double tap to edit, long press for more options")
                    .contextMenu {
                        Button {
                            selectedConfig = config
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            config.isEnabled.toggle()
                            do {
                                try destinationManager.updateDestination(config, modelContext: modelContext)
                            } catch {
                                config.isEnabled.toggle()
                                appState.setError(error.localizedDescription)
                            }
                        } label: {
                            Label(
                                config.isEnabled ? "Disable" : "Enable",
                                systemImage: config.isEnabled ? "pause.circle" : "play.circle"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            do {
                                try destinationManager.deleteDestination(config, modelContext: modelContext)
                            } catch {
                                appState.setError(error.localizedDescription)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, HP.Spacing.xl)
            .padding(.top, HP.Spacing.md)
            .padding(.bottom, HP.Spacing.jumbo)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview

#Preview {
    DestinationsScreen()
        .environment(AppState())
        .environment(DestinationManager())
        .modelContainer(for: [DestinationConfig.self], inMemory: true)
}
