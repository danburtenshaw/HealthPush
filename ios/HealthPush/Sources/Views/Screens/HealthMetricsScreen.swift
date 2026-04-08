import SwiftUI

// MARK: - HealthMetricsScreen

/// Screen for selecting which health data types to sync.
///
/// Metrics are grouped by category (Activity, Body, Vitals, Sleep, Nutrition)
/// with toggles for each individual metric and category-level select/deselect.
struct HealthMetricsScreen: View {
    // MARK: Properties

    @Binding var selectedMetrics: Set<HealthMetricType>
    @Environment(\.dismiss) private var dismiss
    @State private var expandedCategories: Set<HealthMetricCategory> = Set(HealthMetricCategory.allCases)

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                ForEach(HealthMetricCategory.allCases, id: \.self) { category in
                    Section {
                        let metrics = HealthMetricType.metrics(for: category)

                        if expandedCategories.contains(category) {
                            ForEach(metrics) { metric in
                                MetricRow(
                                    metric: metric,
                                    isEnabled: Binding(
                                        get: { selectedMetrics.contains(metric) },
                                        set: { isOn in
                                            if isOn {
                                                selectedMetrics.insert(metric)
                                            } else {
                                                selectedMetrics.remove(metric)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    } header: {
                        categoryHeader(for: category)
                    }
                }
            }
            .navigationTitle("Health Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Select All") { selectAll() }
                        Button("Deselect All") { deselectAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private func categoryHeader(for category: HealthMetricCategory) -> some View {
        let metrics = HealthMetricType.metrics(for: category)
        let selectedCount = metrics.count(where: { selectedMetrics.contains($0) })
        let isExpanded = expandedCategories.contains(category)

        Button {
            withAnimation(.snappy(duration: 0.25)) {
                if isExpanded {
                    expandedCategories.remove(category)
                } else {
                    expandedCategories.insert(category)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.symbolName)
                Text(category.rawValue)

                Text("\(selectedCount)/\(metrics.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                categoryToggleButton(for: category)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .textCase(nil)
        .accessibilityLabel("\(category.rawValue), \(selectedCount) of \(metrics.count) selected")
        .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to expand")
    }

    @ViewBuilder
    private func categoryToggleButton(for category: HealthMetricCategory) -> some View {
        let metrics = HealthMetricType.metrics(for: category)
        let allSelected = metrics.allSatisfy { selectedMetrics.contains($0) }

        Button(allSelected ? "Deselect" : "Select All") {
            if allSelected {
                for metric in metrics {
                    selectedMetrics.remove(metric)
                }
            } else {
                for metric in metrics {
                    selectedMetrics.insert(metric)
                }
            }
        }
        .font(.caption)
        .textCase(nil)
    }

    // MARK: Actions

    private func selectAll() {
        selectedMetrics = Set(HealthMetricType.allCases)
    }

    private func deselectAll() {
        selectedMetrics = []
    }
}

// MARK: - Preview

#Preview {
    HealthMetricsScreen(
        selectedMetrics: .constant(Set(HealthMetricType.allCases))
    )
}
