import Foundation
import HealthKit
import os

// MARK: - HomeAssistantError

/// Errors specific to Home Assistant webhook operations.
enum HomeAssistantError: LocalizedError {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case authenticationFailed
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            "Invalid Home Assistant configuration: \(message)"
        case let .connectionFailed(message):
            "Failed to connect to Home Assistant webhook: \(message)"
        case .authenticationFailed:
            "Home Assistant webhook authentication failed. Check your webhook secret."
        case let .syncFailed(message):
            "Failed to sync to Home Assistant webhook: \(message)"
        }
    }
}

// MARK: - HomeAssistantDestination

/// Syncs health data to a Home Assistant instance via a webhook endpoint.
///
/// All enabled health metrics are batched into a single POST request to the
/// configured webhook URL. The Home Assistant custom integration receives
/// the payload and creates sensor entities automatically.
struct HomeAssistantDestination: SyncDestination {
    // MARK: Properties

    let id: UUID
    let name: String
    let isEnabled: Bool

    /// The full webhook URL (e.g., "https://ha.local:8123/api/webhook/healthpush_abc123").
    private let webhookURL: String

    /// The webhook secret for authentication. May be empty if no secret is configured.
    private let webhookSecret: String

    private let enabledMetrics: Set<HealthMetricType>
    private let networkService: NetworkService
    private let logger = Logger(subsystem: "app.healthpush", category: "HomeAssistant")

    // MARK: Initialization

    /// Creates a Home Assistant destination from a persisted configuration.
    init(config: DestinationConfig, networkService: NetworkService = NetworkService()) throws {
        id = config.id
        name = config.name
        isEnabled = config.isEnabled
        let haConfig = try config.homeAssistantConfig
        webhookURL = haConfig.webhookURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        webhookSecret = try config.credential(for: CredentialField.webhookSecret)
        enabledMetrics = config.enabledMetrics
        self.networkService = networkService
    }

    /// Creates a destination for connection testing without a persisted config.
    init(webhookURL: String, webhookSecret: String, networkService: NetworkService = NetworkService()) {
        id = UUID()
        name = "Connection Test"
        isEnabled = true
        self.webhookURL = webhookURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.webhookSecret = webhookSecret
        enabledMetrics = []
        self.networkService = networkService
    }

    // MARK: SyncDestination

    var capabilities: SyncCapabilities {
        SyncCapabilities(supportsIncremental: true, isIdempotent: false, isFireAndForget: true, maxBatchSize: nil)
    }

    func queryWindow(lastSyncedAt: Date?, needsFullSync: Bool, now: Date) -> QueryWindow {
        let start = lastSyncedAt ?? Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        return QueryWindow(start: start, end: now)
    }

    func cumulativeQueryWindow(lastSyncedAt: Date?, now: Date) -> QueryWindow? {
        // HA sends the full day's cumulative total ("8,432 steps today")
        QueryWindow(start: Calendar.current.startOfDay(for: now), end: now)
    }

    func classifyError(_ error: Error) -> SyncFailure {
        switch error {
        case HomeAssistantError.authenticationFailed:
            .permanent(message: error.localizedDescription, recovery: .reauthenticate)
        case HomeAssistantError.invalidConfiguration:
            .permanent(message: error.localizedDescription, recovery: .fixURL)
        default:
            SyncFailure.classifyNetworkError(error)
        }
    }

    // Syncs health data points to Home Assistant via a single webhook POST.
    //
    // All enabled metrics are batched into one request. The webhook payload
    // contains the device name, a timestamp, and an array of metric objects.
    //
    // - Parameters:
    //   - data: The health data points to sync.
    //   - onProgress: Optional callback reporting (completedBatches, totalBatches).
    // - Throws: ``HomeAssistantError`` if the webhook URL is empty or the request fails.

    func sync(data: [HealthDataPoint], onProgress: (@Sendable (Int, Int) -> Void)?) async throws -> SyncStats {
        guard !webhookURL.isEmpty else {
            throw HomeAssistantError.invalidConfiguration("Webhook URL is empty.")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metrics = Self.buildMetricPayloads(
            from: data,
            enabledMetrics: enabledMetrics,
            formatter: formatter
        )

        guard !metrics.isEmpty else {
            logger.info("No enabled metrics to sync, skipping webhook call")
            return SyncStats(processedCount: 0, newCount: 0)
        }

        // Single request — one value per metric is small enough
        let payload: [String: Any] = [
            "device_name": Self.deviceName,
            "timestamp": formatter.string(from: Date()),
            "metrics": metrics
        ]

        onProgress?(0, 1)

        do {
            try await networkService.requestWithDictionary(
                url: webhookURL,
                method: .post,
                headers: webhookHeaders,
                jsonBody: payload
            )
            onProgress?(1, 1)
            logger.info("Home Assistant webhook sync complete: \(metrics.count) metrics sent")
        } catch {
            logger.error("Webhook sync failed: \(error.localizedDescription)")
            throw HomeAssistantError.syncFailed(error.localizedDescription)
        }

        // HA always sends the latest value per metric — all are "new" from HA's perspective
        return SyncStats(processedCount: data.count, newCount: metrics.count)
    }

    /// Tests whether the webhook endpoint is reachable and properly configured.
    ///
    /// Sends an empty metrics array to the webhook. The HA integration returns
    /// HTTP 400 for empty payloads, which confirms the endpoint is alive. Any 2xx
    /// response is also treated as success. HTTP 401 indicates a bad secret, and
    /// HTTP 404 indicates a wrong URL.
    ///
    /// - Returns: `true` if the webhook is reachable (2xx or 400 response).
    /// - Throws: ``HomeAssistantError`` on authentication failure, wrong URL, or connection error.
    func testConnection() async throws -> Bool {
        guard !webhookURL.isEmpty else {
            throw HomeAssistantError.invalidConfiguration("Webhook URL is empty.")
        }

        let payload: [String: Any] = [
            "metrics": [] as [Any],
            "device_name": "HealthPush Test"
        ]

        do {
            try await networkService.requestWithDictionary(
                url: webhookURL,
                method: .post,
                headers: webhookHeaders,
                jsonBody: payload
            )
            // 2xx response — webhook is alive and accepted the test
            logger.info("Home Assistant webhook connection test successful")
            return true
        } catch let error as NetworkError {
            switch error {
            case let .httpError(statusCode, _):
                switch statusCode {
                case 400:
                    // Expected response for empty metrics — webhook is alive
                    logger.info("Home Assistant webhook connection test successful (400 = endpoint active)")
                    return true
                case 401,
                     403:
                    throw HomeAssistantError.authenticationFailed
                case 404:
                    throw HomeAssistantError.connectionFailed("Webhook URL not found (HTTP 404).")
                default:
                    throw HomeAssistantError.connectionFailed("HTTP \(statusCode)")
                }
            case let .invalidURL(url):
                throw HomeAssistantError.invalidConfiguration("Invalid webhook URL: \(url)")
            case .timeout:
                throw HomeAssistantError.connectionFailed("Request timed out.")
            default:
                throw HomeAssistantError.connectionFailed(error.localizedDescription)
            }
        } catch {
            throw HomeAssistantError.connectionFailed(error.localizedDescription)
        }
    }

    // MARK: Private

    /// Headers for webhook requests. Includes the webhook secret if configured.
    private var webhookHeaders: [String: String] {
        var headers = ["Content-Type": "application/json"]
        if !webhookSecret.isEmpty {
            headers["X-Webhook-Secret"] = webhookSecret
        }
        return headers
    }

    /// The device name sent in the webhook payload.
    ///
    /// Uses a hardcoded default instead of `UIDevice.current.name` to avoid
    /// leaking the user's personal device name (e.g. "Dan's iPhone").
    /// A user-configurable sensor label can be added in a future release.
    private static let deviceName = "HealthPush"

    static func buildMetricPayloads(
        from data: [HealthDataPoint],
        enabledMetrics: Set<HealthMetricType>,
        formatter: ISO8601DateFormatter
    ) -> [[String: Any]] {
        let grouped = Dictionary(grouping: data) { $0.metricType }
        var metrics: [[String: Any]] = []

        for (metricType, points) in grouped {
            guard enabledMetrics.contains(metricType) else { continue }

            if metricType == .sleepAnalysis {
                if let sleepPayload = sleepPayload(from: points, formatter: formatter) {
                    metrics.append(sleepPayload)
                }
                continue
            }

            guard let latest = points.max(by: { $0.timestamp < $1.timestamp }) else { continue }
            metrics.append(metricPayload(for: latest, formatter: formatter))
        }

        return metrics.sorted {
            ($0["type"] as? String ?? "") < ($1["type"] as? String ?? "")
        }
    }

    static func sleepPayload(
        from points: [HealthDataPoint],
        formatter: ISO8601DateFormatter
    ) -> [String: Any]? {
        let asleepIntervals = mergedSleepIntervals(from: points)
        guard let firstInterval = asleepIntervals.first,
              let lastInterval = asleepIntervals.last
        else {
            return nil
        }

        let totalHours = asleepIntervals.reduce(0.0) { partialResult, interval in
            partialResult + interval.end.timeIntervalSince(interval.start) / 3600.0
        }

        let dateString = Self.sleepAggregateDateFormatter.string(from: lastInterval.end)
        let aggregateID = HealthDataPoint.aggregateID(date: dateString, metric: .sleepAnalysis)

        return [
            "id": aggregateID.uuidString,
            "type": HealthMetricType.sleepAnalysis.fileStem,
            "value": (totalHours * 100).rounded() / 100,
            "unit": HealthMetricType.sleepAnalysis.unitString,
            "start_date": formatter.string(from: firstInterval.start),
            "end_date": formatter.string(from: lastInterval.end)
        ]
    }

    static func mergedSleepIntervals(from points: [HealthDataPoint]) -> [(start: Date, end: Date)] {
        let sorted = points
            .filter(Self.isAsleepSample)
            .map { (start: $0.timestamp, end: $0.endTimestamp) }
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }

        guard let first = sorted.first else { return [] }

        var merged: [(start: Date, end: Date)] = [first]
        for interval in sorted.dropFirst() {
            let previous = merged[merged.count - 1]
            if interval.start <= previous.end {
                merged[merged.count - 1].end = max(previous.end, interval.end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    static func isAsleepSample(_ point: HealthDataPoint) -> Bool {
        guard point.metricType == .sleepAnalysis else { return true }
        guard let categoryValue = point.categoryValue else { return true }

        switch categoryValue {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
    }

    private static func metricPayload(
        for point: HealthDataPoint,
        formatter: ISO8601DateFormatter
    ) -> [String: Any] {
        var displayValue = point.value
        switch point.metricType {
        case .bodyFatPercentage,
             .oxygenSaturation:
            displayValue *= 100
        default:
            break
        }

        let roundedValue: Any = switch point.metricType {
        case .steps,
             .flightsClimbed:
            Int(displayValue)
        default:
            (displayValue * 100).rounded() / 100
        }

        return [
            "id": point.id.uuidString,
            "type": point.metricType.fileStem,
            "value": roundedValue,
            "unit": point.metricType == .sleepAnalysis ? "hr" : point.unit,
            "start_date": formatter.string(from: point.timestamp),
            "end_date": formatter.string(from: point.endTimestamp)
        ]
    }

    private static let sleepAggregateDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
