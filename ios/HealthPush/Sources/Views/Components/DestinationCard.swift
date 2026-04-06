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

                if !config.baseURL.isEmpty {
                    Text(sanitizedURL)
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
    }

    // MARK: Helpers

    private var iconBackgroundColor: Color {
        switch config.destinationType {
        case .homeAssistant: return .blue
        case .s3: return .orange
        }
    }

    /// Shows a sanitized summary of the destination address.
    private var sanitizedURL: String {
        switch config.destinationType {
        case .homeAssistant:
            guard let url = URL(string: config.baseURL) else { return config.baseURL }
            if let host = url.host() {
                let scheme = url.scheme ?? "http"
                let port = url.port.map { ":\($0)" } ?? ""
                return "\(scheme)://\(host)\(port)"
            }
            return config.baseURL
        case .s3:
            let prefix = config.s3PathPrefix.isEmpty ? "" : "/\(config.s3PathPrefix)"
            return "s3://\(config.baseURL)\(prefix)"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        DestinationCard(config: {
            let c = DestinationConfig(
                name: "Home Assistant",
                destinationType: .homeAssistant,
                baseURL: "http://homeassistant.local:8123",
                apiToken: "abc123"
            )
            return c
        }())

        DestinationCard(config: {
            let c = DestinationConfig(
                name: "Office HA",
                destinationType: .homeAssistant,
                baseURL: "https://ha.example.com",
                apiToken: "xyz"
            )
            c.isEnabled = false
            return c
        }())
    }
    .padding()
}
