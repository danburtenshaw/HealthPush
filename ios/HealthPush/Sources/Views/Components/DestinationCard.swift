import SwiftUI

// MARK: - DestinationCard

/// A card displaying a destination's name, type, and connection status.
struct DestinationCard: View {
    // MARK: Properties

    let config: DestinationConfig

    // MARK: Body

    var body: some View {
        HStack(spacing: HP.Spacing.lgXl) {
            // Destination icon
            ZStack {
                RoundedRectangle(cornerRadius: HP.Radius.md, style: .continuous)
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: config.destinationType.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconBackgroundColor)
                    .symbolRenderingMode(.hierarchical)
            }

            // Destination info
            VStack(alignment: .leading, spacing: HP.Spacing.xs) {
                Text(config.name)
                    .font(HP.Typography.sectionTitle)

                if config.needsReauth {
                    HStack(spacing: HP.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                        Text("Credentials needed")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Credentials needed. Tap to re-enter.")
                }

                HStack(spacing: HP.Spacing.sm) {
                    Circle()
                        .fill(config.isEnabled ? .green : .gray)
                        .frame(width: 8, height: 8)

                    Text(config.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("  \(config.enabledMetrics.count) metrics")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: HP.Spacing.sm) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text(config.syncFrequency.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let nextSync = config.nextSyncTime {
                        if nextSync < Date.now {
                            Text("  Overdue")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("  Next: \(nextSync, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Next sync: \(nextSync.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }

                syncSummaryView
                    .font(.caption2)
                    .foregroundStyle(syncSummaryColor)

                if let urlText = sanitizedURL, !urlText.isEmpty {
                    Text(urlText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(HP.Spacing.xl)
        .background {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Helpers

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append("\(config.name), \(config.destinationType.displayName).")
        if config.needsReauth {
            parts.append("Credentials needed.")
        }
        parts.append(config.isEnabled ? "Enabled" : "Disabled")
        parts.append("\(config.enabledMetrics.count) metrics.")
        parts.append("Frequency: \(config.syncFrequency.displayName).")
        if let nextSync = config.nextSyncTime {
            if nextSync < Date.now {
                parts.append("Next sync overdue.")
            }
        }
        parts.append(syncSummary + ".")
        return parts.joined(separator: " ")
    }

    private var iconBackgroundColor: Color {
        switch config.destinationType {
        case .homeAssistant: .blue
        case .s3: .orange
        }
    }

    /// Shows a sanitized summary of the destination address.
    private var sanitizedURL: String? {
        switch config.destinationType {
        case .homeAssistant:
            guard let haConfig = try? config.homeAssistantConfig else { return nil }
            let urlString = haConfig.webhookURL
            guard !urlString.isEmpty else { return nil }
            guard let url = URL(string: urlString) else { return urlString }
            if let host = url.host() {
                let scheme = url.scheme ?? "http"
                let port = url.port.map { ":\($0)" } ?? ""
                return "\(scheme)://\(host)\(port)"
            }
            return urlString
        case .s3:
            guard let s3Config = try? config.s3Config else { return nil }
            let prefix = s3Config.pathPrefix.isEmpty ? "" : "/\(s3Config.pathPrefix)"
            if !s3Config.endpoint.isEmpty {
                let endpoint = S3Client.normalizedEndpoint(s3Config.endpoint)
                return "\(endpoint)/\(s3Config.bucket)\(prefix)"
            }
            return "s3://\(s3Config.bucket)\(prefix)"
        }
    }

    /// A view that shows the sync summary with live-updating relative timestamps.
    /// Uses `Text(date, style: .relative)` so the displayed time updates automatically.
    ///
    /// Priority: check `lastSyncedAt` first. If a destination has synced before, always
    /// show the relative time. Only show "Waiting for first sync" when `lastSyncedAt` is nil.
    /// This prevents a stale "Initial sync pending" label from lingering when SwiftData
    /// has not yet propagated the `needsFullSync = false` change through the view hierarchy.
    @ViewBuilder
    private var syncSummaryView: some View {
        if let lastSyncedAt = config.lastSyncedAt {
            if config.needsFullSync {
                // Has synced before but a full re-sync is queued
                HStack(spacing: 4) {
                    Text("Re-sync queued")
                    Text("\u{00B7}")
                    (Text("last ") + Text(lastSyncedAt, style: .relative) + Text(" ago"))
                }
                .accessibilityLabel("Re-sync queued. Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                (Text("Last synced ") + Text(lastSyncedAt, style: .relative) + Text(" ago"))
                    .accessibilityLabel("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
            }
        } else {
            Text("Waiting for first sync")
        }
    }

    /// Static string version of the sync summary for accessibility labels.
    private var syncSummary: String {
        if let lastSyncedAt = config.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            if config.needsFullSync {
                return "Re-sync queued, last synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: .now))"
            }
            return "Last synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: .now))"
        }

        return "Waiting for first sync"
    }

    private var syncSummaryColor: Color {
        if config.lastSyncedAt == nil {
            return .orange
        }
        return config.needsFullSync ? .orange : .secondary
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: HP.Spacing.lg) {
        DestinationCard(config: DestinationConfig(
            name: "Home Assistant",
            destinationType: .homeAssistant,
            typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: "http://homeassistant.local:8123"))
        ))

        DestinationCard(config: {
            let c = DestinationConfig(
                name: "Office HA",
                destinationType: .homeAssistant,
                typeConfig: .homeAssistant(HomeAssistantTypeConfig(webhookURL: "https://ha.example.com"))
            )
            c.isEnabled = false
            return c
        }())
    }
    .padding()
}
