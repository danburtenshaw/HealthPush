import SwiftUI

// MARK: - MetricRow

/// A row displaying a health metric with its icon, name, and a toggle
/// for enabling/disabling sync of that metric.
struct MetricRow: View {
    // MARK: Properties

    let metric: HealthMetricType
    @Binding var isEnabled: Bool

    // MARK: Body

    var body: some View {
        HStack(spacing: 12) {
            // Metric icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: metric.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)

            // Metric info
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.displayName)
                    .font(.subheadline.weight(.medium))

                Text(metric.displayUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Spacer()

            // Toggle
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(.accentColor)
                .accessibilityLabel("\(metric.displayName), \(metric.category.rawValue)")
                .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
                .accessibilityHint(isEnabled ? "Double tap to stop syncing this metric" : "Double tap to start syncing this metric")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Helpers

    private var iconColor: Color {
        switch metric.category {
        case .activity: .orange
        case .body: .purple
        case .vitals: .red
        case .sleep: .indigo
        case .nutrition: .green
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        MetricRow(metric: .steps, isEnabled: .constant(true))
        MetricRow(metric: .heartRate, isEnabled: .constant(false))
        MetricRow(metric: .bodyMass, isEnabled: .constant(true))
        MetricRow(metric: .sleepAnalysis, isEnabled: .constant(true))
        MetricRow(metric: .dietaryWater, isEnabled: .constant(false))
    }
}
