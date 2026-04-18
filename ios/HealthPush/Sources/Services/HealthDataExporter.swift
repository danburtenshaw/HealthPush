import Foundation

#if canImport(os)
import os
#endif

// MARK: - HealthDataExporter

/// Shared data processing layer for all export destinations.
///
/// Handles the common operations that every destination needs:
/// - Grouping data points by date and metric type
/// - UUID-based deduplication and merge with existing data
/// - Serialization to JSON, NDJSON, and CSV formats
/// - Deserialization from JSON and CSV for incremental merge
///
/// By centralising this logic, all destinations (S3, Google Sheets, local CSV, etc.)
/// get consistent, tested behaviour without reimplementing dedup/merge.
struct HealthDataExporter {
    #if canImport(os)
    private let logger = Logger(subsystem: "app.healthpush", category: "HealthDataExporter")
    #endif

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

        let byDate = Dictionary(grouping: data) { point in
            calendar.startOfDay(for: point.startDate)
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
    struct MergeResult {
        /// All data points after merge, sorted by startDate.
        let points: [HealthDataPoint]
        /// How many incoming points were genuinely new or had changed values.
        let newCount: Int
    }

    /// Merges new data points into an existing set, deduplicating by UUID.
    ///
    /// When a UUID collision occurs, the new point wins (it may have updated values,
    /// e.g., resting heart rate revisions). Tombstoned incoming points are preserved:
    /// if an incoming point has `deleted == true`, the merged result keeps the tombstone.
    /// The result is sorted by startDate ascending.
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
            if let existingPoint = byID[point.id] {
                if existingPoint.metricType != point.metricType
                    || existingPoint.value != point.value
                    || existingPoint.unit != point.unit
                    || existingPoint.startDate != point.startDate
                    || existingPoint.endDate != point.endDate
                    || existingPoint.sourceName != point.sourceName
                    || existingPoint.sourceBundleIdentifier != point.sourceBundleIdentifier
                    || existingPoint.categoryValue != point.categoryValue
                    || existingPoint.deleted != point.deleted
                {
                    newCount += 1
                }
            } else {
                newCount += 1
            }
            byID[point.id] = point // always overwrite so value revisions are captured
        }

        let sorted = byID.values.sorted { $0.startDate < $1.startDate }
        return MergeResult(points: sorted, newCount: newCount)
    }

    // MARK: - JSON Serialization

    /// Encodes data points to pretty-printed JSON (v1 schema with nested metric/source).
    func encodeJSON(_ points: [HealthDataPoint]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(points)
    }

    /// Decodes data points from JSON (v1 schema with nested metric/source).
    ///
    /// - Parameter data: The raw JSON data to decode.
    /// - Returns: The decoded health data points.
    /// - Throws: `DecodingError` if the JSON is malformed or contains unexpected values.
    func decodeJSON(_ data: Data) throws -> [HealthDataPoint] {
        let decoder = JSONDecoder()
        return try decoder.decode([HealthDataPoint].self, from: data)
    }

    // MARK: - NDJSON Serialization

    /// Encodes data points to newline-delimited JSON (one JSON object per line, no array wrapper).
    ///
    /// Each line is a complete JSON object representing a single `HealthDataPoint`.
    /// This format is used for the v1 `data.jsonl` files.
    func encodeNDJSON(_ points: [HealthDataPoint]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var lines: [Data] = []
        for point in points {
            let lineData = try encoder.encode(point)
            lines.append(lineData)
        }

        let newline = Data([0x0A]) // "\n"
        var result = Data()
        for (index, line) in lines.enumerated() {
            result.append(line)
            if index < lines.count - 1 {
                result.append(newline)
            }
        }
        return result
    }

    /// Decodes data points from newline-delimited JSON.
    ///
    /// - Parameter data: Raw NDJSON data (one JSON object per line).
    /// - Returns: The decoded health data points. Malformed lines are skipped.
    func decodeNDJSON(_ data: Data) -> [HealthDataPoint] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()

        return string
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(HealthDataPoint.self, from: lineData)
            }
    }

    // MARK: - CSV Serialization

    /// The CSV header row for health data exports (v1 schema column order).
    static let csvHeader = "uuid,startDate,endDate,tzOffset,value,unit,aggregation,sourceName,sourceBundleId,schemaVersion"

    /// Encodes data points to CSV format (header + data rows).
    func encodeCSV(_ points: [HealthDataPoint]) -> Data {
        var lines = [Self.csvHeader]
        let fmt = Self.isoFormatter

        for point in points {
            let fields = [
                point.id.uuidString,
                fmt.string(from: point.startDate),
                fmt.string(from: point.endDate),
                point.tzOffset,
                String(point.value),
                point.unit,
                point.aggregation,
                Self.csvEscape(point.sourceName),
                Self.csvEscape(point.sourceBundleIdentifier ?? ""),
                point.schemaVersion
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
    struct MergeEncodeResult {
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
        let existing: [HealthDataPoint] = if let data = existingData {
            switch format {
            case .json:
                (try? decodeJSON(data)) ?? []
            case .ndjson:
                decodeNDJSON(data)
            case .csv:
                decodeCSV(data)
            }
        } else {
            []
        }

        let merged = merge(existing: existing, incoming: incoming)

        let encoded: Data = switch format {
        case .json:
            try encodeJSON(merged.points)
        case .ndjson:
            try encodeNDJSON(merged.points)
        case .csv:
            encodeCSV(merged.points)
        }

        return MergeEncodeResult(data: encoded, newCount: merged.newCount)
    }

    // MARK: - Path Building

    /// Builds a v1 storage key/path for a date/metric combination.
    ///
    /// Layout: `{prefix}/v1/{metric.key}/{YYYY}/{MM}/{DD}/data.{ext}`
    ///
    /// - Parameters:
    ///   - prefix: User-configured path prefix (may be empty).
    ///   - dateString: The date string (YYYY-MM-DD).
    ///   - metricType: The health metric type.
    ///   - ext: File extension — typically the export format's `fileExtension`
    ///          (e.g. `jsonl`, `json`, `csv`). Legacy callers may pass any string.
    /// - Returns: The full key path.
    static func buildKey(prefix: String, dateString: String, metricType: HealthMetricType, ext: String) -> String {
        let fileExt = ext.isEmpty ? "jsonl" : ext
        let fileName = "data.\(fileExt)"
        let parts = dateString.split(separator: "-")
        guard parts.count == 3 else {
            if prefix.isEmpty {
                return "v1/\(metricType.fileStem)/\(dateString)/\(fileName)"
            }
            return "\(prefix)/v1/\(metricType.fileStem)/\(dateString)/\(fileName)"
        }

        let year = parts[0]
        let month = parts[1]
        let day = parts[2]

        if prefix.isEmpty {
            return "v1/\(metricType.fileStem)/\(year)/\(month)/\(day)/\(fileName)"
        }
        return "\(prefix)/v1/\(metricType.fileStem)/\(year)/\(month)/\(day)/\(fileName)"
    }

    /// Convenience overload that derives the file extension from an ``ExportFormat``.
    static func buildKey(prefix: String, dateString: String, metricType: HealthMetricType, format: ExportFormat) -> String {
        buildKey(prefix: prefix, dateString: dateString, metricType: metricType, ext: format.fileExtension)
    }

    // MARK: - Manifest

    /// Builds a `_manifest.json` sidecar for a given date/metric data file.
    ///
    /// - Parameters:
    ///   - metric: The metric type key (fileStem).
    ///   - dateString: The date in YYYY-MM-DD format.
    ///   - recordCount: Number of records in the data file.
    ///   - lastModified: When the file was last written.
    /// - Returns: JSON data for the manifest sidecar.
    static func buildManifest(metric: String, dateString: String, recordCount: Int, lastModified: Date) -> Data {
        let isoString = isoFormatter.string(from: lastModified)
        let json = """
        {
          "schemaVersion": "1.0",
          "metric": "\(metric)",
          "date": "\(dateString)",
          "recordCount": \(recordCount),
          "lastModified": "\(isoString)"
        }
        """
        return json.data(using: .utf8) ?? Data()
    }

    /// Builds the key path for a `_manifest.json` sidecar.
    ///
    /// - Parameters:
    ///   - prefix: User-configured path prefix (may be empty).
    ///   - dateString: The date string (YYYY-MM-DD).
    ///   - metricType: The health metric type.
    /// - Returns: The full manifest key path.
    static func buildManifestKey(prefix: String, dateString: String, metricType: HealthMetricType) -> String {
        let dataKey = buildKey(prefix: prefix, dateString: dateString, metricType: metricType, ext: "")
        let dir = (dataKey as NSString).deletingLastPathComponent
        return "\(dir)/_manifest.json"
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
        // v1 CSV: uuid,startDate,endDate,tzOffset,value,unit,aggregation,sourceName,sourceBundleId,schemaVersion
        guard fields.count >= 8,
              let uuid = UUID(uuidString: fields[0]),
              let startDate = isoFormatter.date(from: fields[1]),
              let endDate = isoFormatter.date(from: fields[2]),
              let value = Double(fields[4])
        else {
            return nil
        }

        let unit = fields[5]
        let aggregation = fields.count > 6 ? fields[6] : "raw"
        let sourceName = fields.count > 7 ? fields[7] : ""
        let sourceBundleId = fields.count > 8 && !fields[8].isEmpty ? fields[8] : nil
        let tzOffset = fields[3]

        // Reverse-lookup metric type from canonical unit (best-effort)
        let metricType = HealthMetricType.allCases.first { $0.canonicalUnit == unit } ?? .heartRate

        return HealthDataPoint(
            id: uuid,
            metricType: metricType,
            value: value,
            unit: unit,
            startDate: startDate,
            endDate: endDate,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleId,
            aggregation: aggregation,
            tzOffset: tzOffset
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
struct DateMetricKey: Hashable {
    let dateString: String
    let metricType: HealthMetricType
}
