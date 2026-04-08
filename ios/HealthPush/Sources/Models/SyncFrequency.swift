import Foundation

/// Represents the interval at which background syncs are scheduled.
enum SyncFrequency: String, CaseIterable, Codable, Identifiable {
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hr"
    case threeHours = "3hr"
    case sixHours = "6hr"
    case twelveHours = "12hr"
    case twentyFourHours = "24hr"

    var id: String {
        rawValue
    }

    /// The time interval in seconds.
    var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .threeHours: 3 * 60 * 60
        case .sixHours: 6 * 60 * 60
        case .twelveHours: 12 * 60 * 60
        case .twentyFourHours: 24 * 60 * 60
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .fifteenMinutes: "Every 15 Minutes"
        case .thirtyMinutes: "Every 30 Minutes"
        case .oneHour: "Every Hour"
        case .threeHours: "Every 3 Hours"
        case .sixHours: "Every 6 Hours"
        case .twelveHours: "Every 12 Hours"
        case .twentyFourHours: "Every 24 Hours"
        }
    }
}
