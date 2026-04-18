import SwiftUI

// MARK: - TrustStrip

/// A three-cell compact status spine — Last sync · Next sync · Destinations —
/// that gives the user a single glance answer to "is HealthPush working?".
///
/// The strip is intentionally dense: labels are uppercase captions, values are
/// monospaced so numbers don't jitter when they update every few seconds, and
/// every value is paired with a status dot so the healthy/unhealthy read stays
/// pre-attentive even if the user doesn't read the text.
struct TrustStrip: View {
    // MARK: Properties

    let lastSyncDate: Date?
    let nextSyncDate: Date?
    let destinationCount: Int
    let healthyCount: Int
    let isSyncing: Bool
    let hasIssues: Bool

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            cell(
                label: "Last sync",
                dot: lastSyncDotStyle,
                value: lastSyncValue
            )
            divider
            cell(
                label: "Next sync",
                icon: "clock",
                value: nextSyncValue
            )
            divider
            cell(
                label: "Destinations",
                dot: allHealthy ? .success : .failure,
                value: healthValue
            )
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Cells

    private func cell(label: String, dot: DotStyle? = nil, icon: String? = nil, value: String) -> some View {
        VStack(alignment: .leading, spacing: HP.Spacing.sm) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(spacing: HP.Spacing.sm) {
                if let dot {
                    StatusDot(style: dot, pulsing: isSyncing && label == "Last sync")
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(.footnote, design: .monospaced, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HP.Spacing.lgXl)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
            .padding(.vertical, HP.Spacing.md)
    }

    // MARK: Computed display

    private var allHealthy: Bool {
        !hasIssues && healthyCount == destinationCount && destinationCount > 0
    }

    private var lastSyncDotStyle: DotStyle {
        if isSyncing { return .active }
        if hasIssues { return .failure }
        guard lastSyncDate != nil else { return .idle }
        return .success
    }

    private var lastSyncValue: String {
        if isSyncing { return "now" }
        guard let date = lastSyncDate else { return "never" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private var nextSyncValue: String {
        guard let date = nextSyncDate, destinationCount > 0 else { return "—" }
        if date <= .now { return "due" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    private var healthValue: String {
        guard destinationCount > 0 else { return "none" }
        return "\(healthyCount)/\(destinationCount) healthy"
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        parts.append("Last sync \(lastSyncValue).")
        parts.append("Next sync \(nextSyncValue).")
        parts.append(destinationCount == 0 ? "No destinations configured." : "\(healthyCount) of \(destinationCount) destinations healthy.")
        return parts.joined(separator: " ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - StatusDot

enum DotStyle {
    case success
    case failure
    case active
    case idle

    var color: Color {
        switch self {
        case .success: .green
        case .failure: .red
        case .active: .blue
        case .idle: .secondary
        }
    }
}

/// A small color dot used inline with labels and values. Pulses gently when
/// the system is actively doing work.
struct StatusDot: View {
    let style: DotStyle
    var pulsing = false
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(style.color)
            .frame(width: size, height: size)
            .overlay {
                if pulsing {
                    Circle()
                        .stroke(style.color.opacity(0.5), lineWidth: 1)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulsing)
                        .onAppear {
                            pulseScale = 2.2
                            pulseOpacity = 0
                        }
                }
            }
    }

    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 1
}

// MARK: - Preview

#Preview {
    VStack(spacing: HP.Spacing.xl) {
        TrustStrip(
            lastSyncDate: Date().addingTimeInterval(-240),
            nextSyncDate: Date().addingTimeInterval(3360),
            destinationCount: 2,
            healthyCount: 2,
            isSyncing: false,
            hasIssues: false
        )

        TrustStrip(
            lastSyncDate: Date().addingTimeInterval(-540),
            nextSyncDate: Date().addingTimeInterval(3060),
            destinationCount: 2,
            healthyCount: 1,
            isSyncing: false,
            hasIssues: true
        )

        TrustStrip(
            lastSyncDate: nil,
            nextSyncDate: nil,
            destinationCount: 0,
            healthyCount: 0,
            isSyncing: true,
            hasIssues: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
