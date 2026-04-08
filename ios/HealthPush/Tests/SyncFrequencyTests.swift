import Foundation
import Testing
@testable import HealthPush

// MARK: - SyncFrequencyTests

struct SyncFrequencyTests {
    @Test("All cases are present")
    func allCases() {
        #expect(SyncFrequency.allCases.count == 7)
    }

    @Test("Time intervals are correct", arguments: [
        (SyncFrequency.fifteenMinutes, 900.0),
        (SyncFrequency.thirtyMinutes, 1800.0),
        (SyncFrequency.oneHour, 3600.0),
        (SyncFrequency.threeHours, 10800.0),
        (SyncFrequency.sixHours, 21600.0),
        (SyncFrequency.twelveHours, 43200.0),
        (SyncFrequency.twentyFourHours, 86400.0)
    ])
    func timeIntervals(frequency: SyncFrequency, expected: TimeInterval) {
        #expect(frequency.timeInterval == expected)
    }

    @Test("Display names are non-empty")
    func displayNames() {
        for frequency in SyncFrequency.allCases {
            #expect(!frequency.displayName.isEmpty)
        }
    }

    @Test("IDs are unique")
    func uniqueIDs() {
        let ids = SyncFrequency.allCases.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test("Codable round-trip works")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for frequency in SyncFrequency.allCases {
            let data = try encoder.encode(frequency)
            let decoded = try decoder.decode(SyncFrequency.self, from: data)
            #expect(decoded == frequency)
        }
    }

    @Test("Time intervals are in ascending order")
    func ascendingOrder() {
        let intervals = SyncFrequency.allCases.map(\.timeInterval)
        for i in 0..<(intervals.count - 1) {
            #expect(intervals[i] < intervals[i + 1])
        }
    }
}
