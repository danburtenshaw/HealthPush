import Foundation

/// Represents the interval at which background syncs are scheduled.
enum SyncFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hr"
    case threeHours = "3hr"
    case sixHours = "6hr"
    case twelveHours = "12hr"
    case twentyFourHours = "24hr"

    var id: String { rawValue }

    /// The time interval in seconds.
    var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .threeHours: return 3 * 60 * 60
        case .sixHours: return 6 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .fifteenMinutes: return "Every 15 Minutes"
        case .thirtyMinutes: return "Every 30 Minutes"
        case .oneHour: return "Every Hour"
        case .threeHours: return "Every 3 Hours"
        case .sixHours: return "Every 6 Hours"
        case .twelveHours: return "Every 12 Hours"
        case .twentyFourHours: return "Every 24 Hours"
        }
    }
}
