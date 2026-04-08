import Foundation

/// Configurable sync window — how far back to pull health data for the initial full sync.
enum SyncStartDateOption: String, CaseIterable, Codable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case last90Days
    case lastYear
    case custom

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .last90Days: "Last 90 Days"
        case .lastYear: "Last Year"
        case .custom: "Custom Date"
        }
    }

    /// Resolves this option to a concrete start date.
    /// - Parameter customDate: The user-chosen date (only used when `self == .custom`).
    func resolvedDate(customDate: Date? = nil) -> Date {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .yesterday:
            return calendar.startOfDay(for: now.daysAgo(1, calendar: calendar))
        case .last7Days:
            return calendar.startOfDay(for: now.daysAgo(7, calendar: calendar))
        case .last30Days:
            return calendar.startOfDay(for: now.daysAgo(30, calendar: calendar))
        case .last90Days:
            return calendar.startOfDay(for: now.daysAgo(90, calendar: calendar))
        case .lastYear:
            return calendar.startOfDay(for: now.yearsAgo(1, calendar: calendar))
        case .custom:
            return calendar.startOfDay(for: customDate ?? now)
        }
    }
}
