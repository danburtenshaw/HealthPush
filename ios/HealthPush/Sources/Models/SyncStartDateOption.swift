import Foundation

/// Configurable sync window — how far back to pull health data for the initial full sync.
enum SyncStartDateOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case last90Days
    case lastYear
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .lastYear: return "Last Year"
        case .custom: return "Custom Date"
        }
    }

    /// Resolves this option to a concrete start date.
    /// - Parameter customDate: The user-chosen date (only used when `self == .custom`).
    func resolvedDate(customDate: Date? = nil) -> Date {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.startOfDay(for: .now)
        case .yesterday:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: .now)!)
        case .last7Days:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -7, to: .now)!)
        case .last30Days:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -30, to: .now)!)
        case .last90Days:
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -90, to: .now)!)
        case .lastYear:
            return calendar.startOfDay(for: calendar.date(byAdding: .year, value: -1, to: .now)!)
        case .custom:
            return calendar.startOfDay(for: customDate ?? .now)
        }
    }
}
