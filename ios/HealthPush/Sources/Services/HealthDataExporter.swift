import Foundation
import os

// MARK: - HealthDataExporter

/// Shared data processing layer for all export destinations.
///
/// Handles the common operations that every destination needs:
/// - Grouping data points by date and metric type
/// - UUID-based deduplication and merge with existing data
/// - Serialization to JSON and CSV formats
/// - Deserialization from JSON and CSV for incremental merge
///
/// By centralising this logic, all destinations (S3, Google Sheets, local CSV, etc.)
/// get consistent, tested behaviour without reimplementing dedup/merge.
struct HealthDataExporter: Sendable {

    private let logger = Logger(subsystem: "com.healthpush.app", category: "HealthDataExporter")

    // MARK: - Date Grouping

    /// Groups data points by local calendar date and metric type.
    ///
    /// The returned dictionary is keyed by `(dateString, metricType)` so callers
    /// can iterate over it to produce one file per date/metric combination.
    ///
    /// - Parameter data: Raw data points from HealthKit.
    /// - Returns: A dictionary mapping `(YYYY-MM-DD, HealthMetricType)` to deduplicated, sorted data points.
    func groupByDateAndMetric(_ data: [HealthDataPoint]) -> [DateMetricKey: [HealthDataPoint]] {
        let calendar = Calendar.current

        // Group by date first
        let byDate = Dictionary(grouping: data) { point in
            calendar.startOfDay(for: point.timestamp)
        }

        var result: [DateMetricKey: [HealthDataPoint]] = [:]

        for (date, points) in byDate {
            let dateString = Self.dateFormatter.string(from: date)
            let byMetric = Dictionary(grouping: points) { $0.metricType }

            for (metricType, metricPoints) in byMetric {
                let key = DateMetricKey(dateString: dateString, metricType: metricType)
                result[key] = metricPoints
            }
        }

        return result
    }

    // MARK: - Deduplication / Merge

    /// The result of merging existing and incoming data points.
    struct MergeResult: Sendable {
        /// All data points after merge, sorted by timestamp.
        let points: [HealthDataPoint]
        /// How many incoming points were genuinely new or had changed values.
        let newCount: Int
    }

    /// Merges new data points into an existing set, deduplicating by UUID.
    ///
    /// When a UUID collision occurs, the new point wins (it may have updated values,
    /// e.g., resting heart rate revisions). The result is sorted by timestamp ascending.
    ///
    /// - Parameters:
    ///   - existing: Previously stored data points.
    ///   - incoming: New data points from the latest sync.
    /// - Returns: Merged points and a count of genuinely new or updated entries.
    func merge(existing: [HealthDataPoint], incoming: [HealthDataPoint]) -> MergeResult {
        var byID: [UUID: HealthDataPoint] = [:]

        for point in existing {
            byID[point.id] = point
        }

        var newCount = 0
        for point in incoming {
            if let existing = byID[point.id] {
                if existing.metricType != point.metricType
                    || existing.value != point.value
                    || existing.unit != point.unit
                    || existing.timestamp != point.timestamp
                    || existing.endTimestamp != point.endTimestamp
                    || existing.sourceName != point.sourceName
                    || existing.sourceBundleIdentifier != point.sourceBundleIdentifier
                    || existing.categoryValue != point.categoryValue {
                    newCount += 1
                }
            } else {
                newCount += 1
            }
            byID[point.id] = point // always overwrite so value revisions are captured
        }

        let sorted = byID.values.sorted { $0.timestamp < $1.timestamp }
        return MergeResult(points: sorted, newCount: newCount)
    }

    // MARK: - JSON Serialization

    /// Encodes data points to pretty-printed JSON.
    ///
    /// Uses a custom date strategy with fractional seconds so that dates
    /// survive a round-trip without losing sub-second precision. Without this,
    /// `.iso8601` truncates to whole seconds and every point looks "updated"
    /// on every sync because the deserialized dates no longer match.
    func encodeJSON(_ points: [HealthDataPoint]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(points)
    }

    /// Decodes data points from JSON, returning an empty array on failure.
    func decodeJSON(_ data: Data) -> [HealthDataPoint] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Self.isoFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot decode date from: \(string)"
                )
            }
            return date
        }
        do {
            return try decoder.decode([HealthDataPoint].self, from: data)
        } catch {
            logger.warning("Failed to decode JSON health data: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - CSV Serialization

    /// The CSV header row for health data exports.
    static let csvHeader = "id,metric,value,unit,timestamp,end_timestamp,source,source_bundle_id,category_value"

    /// Encodes data points to CSV format (header + data rows).
    func encodeCSV(_ points: [HealthDataPoint]) -> Data {
        var lines = [Self.csvHeader]
        let fmt = Self.isoFormatter

        for point in points {
            let fields = [
                point.id.uuidString,
                point.metricType.rawValue,
                String(point.value),
                point.unit,
                fmt.string(from: point.timestamp),
                fmt.string(from: point.endTimestamp),
                Self.csvEscape(point.sourceName),
                Self.csvEscape(point.sourceBundleIdentifier ?? ""),
                point.categoryValue.map(String.init) ?? ""
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    /// Decodes data points from CSV, returning an empty array on failure.
    func decodeCSV(_ data: Data) -> [HealthDataPoint] {
        guard let csv = String(data: data, encoding: .utf8) else { return [] }

        let rows = csv.components(separatedBy: "\n").dropFirst() // skip header
        var points: [HealthDataPoint] = []

        for row in rows where !row.isEmpty {
            if let point = Self.parseCSVRow(row) {
                points.append(point)
            }
        }

        return points
    }

    // MARK: - Full Merge Pipeline

    /// The result of merging and encoding data.
    struct MergeEncodeResult: Sendable {
        /// The encoded data ready to write.
        let data: Data
        /// How many incoming points were genuinely new or had changed values.
        let newCount: Int
    }

    /// The complete merge pipeline: decode existing data, merge with incoming, encode.
    ///
    /// This is the primary entry point for destinations that store one file per
    /// date/metric combination. It handles:
    /// 1. Decoding existing data from the given format
    /// 2. Merging with deduplication by UUID
    /// 3. Re-encoding in the requested format
    ///
    /// - Parameters:
    ///   - existingData: Raw data from the existing file (nil if file doesn't exist yet).
    ///   - incoming: New data points to merge in.
    ///   - format: The serialization format.
    /// - Returns: The encoded merged data and count of new/updated points.
    func mergeAndEncode(
        existingData: Data?,
        incoming: [HealthDataPoint],
        format: ExportFormat
    ) throws -> MergeEncodeResult {
        let existing: [HealthDataPoint]
        if let data = existingData {
            switch format {
            case .json:
                existing = decodeJSON(data)
            case .csv:
                existing = decodeCSV(data)
            }
        } else {
            existing = []
        }

        let merged = merge(existing: existing, incoming: incoming)

        let encoded: Data
        switch format {
        case .json:
            encoded = try encodeJSON(merged.points)
        case .csv:
            encoded = encodeCSV(merged.points)
        }

        return MergeEncodeResult(data: encoded, newCount: merged.newCount)
    }

    // MARK: - Path Building

    /// Builds a storage key/path for a date/metric/format combination.
    ///
    /// - Parameters:
    ///   - prefix: User-configured path prefix (may be empty).
    ///   - dateString: The date string (YYYY-MM-DD).
    ///   - metricType: The health metric type.
    ///   - ext: File extension (json or csv).
    /// - Returns: The full key path, e.g. `my-data/2026-04-03/heart_rate.json`.
    static func buildKey(prefix: String, dateString: String, metricType: HealthMetricType, ext: String) -> String {
        let fileName = "\(metricType.sensorEntitySuffix).\(ext)"
        if prefix.isEmpty {
            return "\(dateString)/\(fileName)"
        }
        return "\(prefix)/\(dateString)/\(fileName)"
    }

    // MARK: - Validation

    /// Validates a user-provided path prefix.
    /// Returns nil if valid, or an error message string if invalid.
    static func validatePathPrefix(_ prefix: String) -> String? {
        if prefix.isEmpty { return nil }
        if prefix.hasPrefix("/") { return "Path cannot start with /" }
        if prefix.hasSuffix("/") { return "Path cannot end with /" }
        if prefix.contains("//") { return "Path cannot contain //" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        if prefix.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Only letters, numbers, hyphens, underscores, dots, and slashes allowed"
        }
        if prefix.count > 256 { return "Path cannot exceed 256 characters" }
        return nil
    }

    /// Validates an S3 bucket name per AWS naming rules.
    /// Returns nil if valid, or an error message string if invalid.
    static func validateBucketName(_ name: String) -> String? {
        if name.isEmpty { return "Bucket name is required" }
        if name.count < 3 { return "Bucket name must be at least 3 characters" }
        if name.count > 63 { return "Bucket name cannot exceed 63 characters" }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-."))
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Only lowercase letters, numbers, hyphens, and dots allowed"
        }
        if name.hasPrefix("-") || name.hasPrefix(".") {
            return "Bucket name must start with a letter or number"
        }
        if name.hasSuffix("-") || name.hasSuffix(".") {
            return "Bucket name must end with a letter or number"
        }
        return nil
    }

    // MARK: - Private CSV Helpers

    private static func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }

    private static func parseCSVRow(_ row: String) -> HealthDataPoint? {
        let fields = parseCSVFields(row)
        guard fields.count >= 7,
              let uuid = UUID(uuidString: fields[0]),
              let metricType = HealthMetricType(rawValue: fields[1]),
              let value = Double(fields[2]),
              let timestamp = isoFormatter.date(from: fields[4]),
              let endTimestamp = isoFormatter.date(from: fields[5]) else {
            return nil
        }

        return HealthDataPoint(
            id: uuid,
            metricType: metricType,
            value: value,
            unit: fields[3],
            timestamp: timestamp,
            endTimestamp: endTimestamp,
            sourceName: fields[6],
            sourceBundleIdentifier: fields.count > 7 && !fields[7].isEmpty ? fields[7] : nil,
            categoryValue: fields.count > 8 ? Int(fields[8]) : nil
        )
    }

    private static func parseCSVFields(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(row)
        var i = 0

        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if inQuotes {
                    // Check for escaped quote ("")
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }

    // MARK: - Formatters

    /// Creates a new date formatter for folder names (YYYY-MM-DD in local time).
    /// Returns a fresh instance each call to avoid thread-safety issues.
    static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Creates a new ISO 8601 formatter for timestamp serialization.
    /// Returns a fresh instance each call to avoid thread-safety issues.
    static var isoFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}

// MARK: - DateMetricKey

/// A hashable key combining a date string and metric type for grouping.
struct DateMetricKey: Hashable, Sendable {
    let dateString: String
    let metricType: HealthMetricType
}
