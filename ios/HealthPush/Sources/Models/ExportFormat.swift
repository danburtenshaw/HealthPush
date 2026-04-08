import Foundation

/// The file format for health data exported to external storage.
enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case json
    case csv

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .json: "JSON"
        case .csv: "CSV"
        }
    }

    /// MIME content type for this format.
    var contentType: String {
        switch self {
        case .json: "application/json"
        case .csv: "text/csv"
        }
    }
}
