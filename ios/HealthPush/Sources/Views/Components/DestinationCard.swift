import SwiftUI

// MARK: - DestinationCard

/// A card displaying a destination's name, type, and connection status.
struct DestinationCard: View {
    // MARK: Properties

    let config: DestinationConfig

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            // Destination icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconBackgroundColor.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: config.destinationType.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconBackgroundColor)
            }

            // Destination info
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.headline)

                if config.needsReauth {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Credentials needed")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Credentials needed. Tap to re-enter.")
                }

                HStack(spacing: 6) {
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

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
    @ViewBuilder
    private var syncSummaryView: some View {
        if config.needsFullSync {
            if config.lastSyncedAt == nil {
                Text("Initial sync pending")
            } else {
                Text("Full re-sync queued")
            }
        } else if let lastSyncedAt = config.lastSyncedAt {
            Text("Last synced ") + Text(lastSyncedAt, style: .relative) + Text(" ago")
        } else {
            Text("Ready for first sync")
        }
    }

    /// Static string version of the sync summary for accessibility labels.
    private var syncSummary: String {
        if config.needsFullSync {
            if config.lastSyncedAt == nil {
                return "Initial sync pending"
            }
            return "Full re-sync queued"
        }

        if let lastSyncedAt = config.lastSyncedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last synced \(formatter.localizedString(for: lastSyncedAt, relativeTo: .now))"
        }

        return "Ready for first sync"
    }

    private var syncSummaryColor: Color {
        config.needsFullSync ? .orange : .secondary
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
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
