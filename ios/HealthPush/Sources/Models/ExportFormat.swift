import Foundation

/// The file format for health data exported to external storage.
enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    /// Pretty-printed JSON array (one file contains an array of data points).
    case json

    /// Newline-delimited JSON (one object per line, no array wrapper).
    case ndjson

    /// Comma-separated values with a schema v1 header.
    case csv

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .ndjson: "NDJSON"
        case .csv: "CSV"
        }
    }

    /// A short description for UI subtitles.
    var subtitle: String {
        switch self {
        case .json: "One file contains an array of records"
        case .ndjson: "One JSON object per line — streaming-friendly"
        case .csv: "Tabular format, opens in any spreadsheet"
        }
    }

    /// MIME content type for uploads.
    var contentType: String {
        switch self {
        case .json: "application/json"
        case .ndjson: "application/x-ndjson"
        case .csv: "text/csv"
        }
    }

    /// Filename extension used when writing the primary data file.
    var fileExtension: String {
        switch self {
        case .json: "json"
        case .ndjson: "jsonl"
        case .csv: "csv"
        }
    }
}
