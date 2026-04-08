import Foundation

extension Date {
    /// Returns a date `days` days before `self`.
    ///
    /// Falls back to `addingTimeInterval` if `Calendar.date(byAdding:)` returns nil,
    /// which can happen at DST transitions or invalid-date edge cases.
    func daysAgo(_ days: Int, calendar: Calendar = .current) -> Date {
        if let shifted = calendar.date(byAdding: .day, value: -days, to: self) {
            return shifted
        }
        return addingTimeInterval(-TimeInterval(days) * 86400)
    }

    /// Returns a date `years` years before `self`, with the same DST-safe fallback as `daysAgo`.
    func yearsAgo(_ years: Int, calendar: Calendar = .current) -> Date {
        if let shifted = calendar.date(byAdding: .year, value: -years, to: self) {
            return shifted
        }
        return addingTimeInterval(-TimeInterval(years) * 365 * 86400)
    }
}
