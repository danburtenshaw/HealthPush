import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - NudgeKind

/// The prioritized set of nudges the dashboard can show.
/// Only the highest-priority applicable nudge is visible at a time.
enum NudgeKind: Equatable {
    /// Priority 1: The most recent sync failed with recovery guidance.
    case syncFailure(message: String, recovery: SyncFailure.RecoveryAction?)
    /// Priority 2: A sync completed but delivered no health data (likely permissions).
    case noHealthData
    /// Priority 3: Background App Refresh is disabled or unavailable.
    case backgroundRefreshDisabled
    /// Priority 4: Setup is incomplete (no destination, no HealthKit auth, or never synced).
    case setupIncomplete(healthKitAuthorized: Bool, hasDestinations: Bool, hasEverSynced: Bool)
}

// MARK: - NudgeRow

/// A single, prioritized notification row that shows the most important
/// action item. Only one nudge is visible at a time.
///
/// Priority order (highest first):
/// 1. Sync failure with recovery action
/// 2. No health data synced (permissions issue)
/// 3. Background refresh disabled
/// 4. Setup checklist incomplete (no destination, no HealthKit auth, never synced)
struct NudgeRow: View {
    // MARK: Properties

    let kind: NudgeKind

    /// Called when the user taps the primary action button.
    var onAction: (() -> Void)?

    /// Called when the user taps a secondary action (e.g. "View History" on sync failure).
    var onSecondaryAction: (() -> Void)?

    /// Called when the user dismisses an informational nudge.
    var onDismiss: (() -> Void)?

    // MARK: Body

    var body: some View {
        HStack(spacing: HP.Spacing.lgXl) {
            // Accent sidebar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor)
                .frame(width: 4)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            // Title + Subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Action / dismiss area
            if let buttonLabel = actionButtonLabel {
                Button(action: { onAction?() }) {
                    Text(buttonLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, HP.Spacing.mdLg)
                        .padding(.vertical, HP.Spacing.sm)
                        .background(accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(accentColor)
                }
                .accessibilityHint(actionAccessibilityHint)
            }

            if isDismissible {
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, HP.Spacing.lg)
        .padding(.horizontal, HP.Spacing.lgXl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .fill(accentColor.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: HP.Radius.card, style: .continuous)
                .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: Display Properties

    private var title: String {
        switch kind {
        case .syncFailure:
            "Sync Needs Attention"
        case .noHealthData:
            "No Health Data Synced"
        case .backgroundRefreshDisabled:
            "Background Sync Unavailable"
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                "Add a Destination"
            } else if !healthKitAuthorized {
                "Grant Health Access"
            } else {
                "Run Your First Sync"
            }
        }
    }

    private var subtitle: String {
        switch kind {
        case let .syncFailure(message, _):
            message
        case .noHealthData:
            "Check Apple Health permissions for HealthPush."
        case .backgroundRefreshDisabled:
            "Background App Refresh is off or Low Power Mode is active."
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                "Connect a destination to start syncing health data."
            } else if !healthKitAuthorized {
                "HealthPush needs permission to read your health metrics."
            } else {
                "Tap Sync Now to send health data to your destinations."
            }
        }
    }

    private var iconName: String {
        switch kind {
        case .syncFailure:
            "exclamationmark.triangle.fill"
        case .noHealthData:
            "heart.slash"
        case .backgroundRefreshDisabled:
            "arrow.triangle.2.circlepath.circle"
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                "plus.circle"
            } else if !healthKitAuthorized {
                "heart.fill"
            } else {
                "arrow.triangle.2.circlepath"
            }
        }
    }

    private var accentColor: Color {
        switch kind {
        case .syncFailure:
            .orange
        case .noHealthData:
            .orange
        case .backgroundRefreshDisabled:
            .yellow
        case .setupIncomplete:
            .blue
        }
    }

    private var actionButtonLabel: String? {
        switch kind {
        case .syncFailure:
            // Always "Review" — the recovery's specific call-to-action (e.g.
            // "Set region to us-east-1") is shown in the sync record detail
            // view, which has more space and more context.
            "Review"
        case .noHealthData:
            "Open Health"
        case .backgroundRefreshDisabled:
            "Settings"
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                "Add"
            } else if !healthKitAuthorized {
                "Grant"
            } else {
                nil
            }
        }
    }

    private var actionAccessibilityHint: String {
        switch kind {
        case .syncFailure:
            "Opens the sync record details"
        case .noHealthData:
            "Opens Apple Health to review permissions"
        case .backgroundRefreshDisabled:
            "Opens iOS Settings to enable Background App Refresh"
        case let .setupIncomplete(healthKitAuthorized, hasDestinations, _):
            if !hasDestinations {
                "Opens the destination type picker"
            } else if !healthKitAuthorized {
                "Opens Apple Health permissions"
            } else {
                ""
            }
        }
    }

    private var isDismissible: Bool {
        switch kind {
        case .backgroundRefreshDisabled:
            true
        case .setupIncomplete:
            true
        default:
            false
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: HP.Spacing.lg) {
        NudgeRow(
            kind: .syncFailure(
                message: "Invalid credentials for Home Assistant.",
                recovery: .reauthenticate
            )
        )

        NudgeRow(kind: .noHealthData)

        NudgeRow(kind: .backgroundRefreshDisabled)

        NudgeRow(kind: .setupIncomplete(
            healthKitAuthorized: true,
            hasDestinations: true,
            hasEverSynced: false
        ))

        NudgeRow(kind: .setupIncomplete(
            healthKitAuthorized: false,
            hasDestinations: true,
            hasEverSynced: false
        ))

        NudgeRow(kind: .setupIncomplete(
            healthKitAuthorized: true,
            hasDestinations: false,
            hasEverSynced: false
        ))
    }
    .padding()
}
