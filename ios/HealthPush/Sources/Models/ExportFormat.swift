import Foundation

/// The file format for health data exported to external storage.
enum ExportFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case json = "json"
    case csv = "csv"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }

    /// MIME content type for this format.
    var contentType: String {
        switch self {
        case .json: return "application/json"
        case .csv: return "text/csv"
        }
    }
}
