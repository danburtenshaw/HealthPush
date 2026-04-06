import SwiftUI
import SwiftData

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
                }
            }
            .confirmationDialog("Add Destination", isPresented: $showingDestinationPicker) {
                Button("Home Assistant") { showingAddSheet = true }
                Button("Amazon S3") { showingAddS3Sheet = true }
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var destinationList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(destinationManager.destinations, id: \.id) { config in
                    Button {
                        selectedConfig = config
                    } label: {
                        DestinationCard(config: config)
                    }
                    .buttonStyle(.plain)
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
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
