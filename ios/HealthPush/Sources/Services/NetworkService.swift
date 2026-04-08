import Foundation
import os

// MARK: - NetworkError

/// Errors that can occur during network operations.
enum NetworkError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case encodingFailed(String)
    case decodingFailed(String)
    case connectionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case let .httpError(statusCode, body):
            let bodyInfo = body.map { ": \($0)" } ?? ""
            return "HTTP error \(statusCode)\(bodyInfo)"
        case let .encodingFailed(message):
            return "Failed to encode request: \(message)"
        case let .decodingFailed(message):
            return "Failed to decode response: \(message)"
        case let .connectionFailed(message):
            return "Connection failed: \(message)"
        case .timeout:
            return "The request timed out."
        }
    }
}

// MARK: - HTTPMethod

/// Supported HTTP methods.
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - NetworkService

/// A lightweight URLSession wrapper for REST API calls.
///
/// This service handles JSON encoding/decoding, authentication headers,
/// and error mapping. It uses no third-party dependencies.
struct NetworkService {
    // MARK: Properties

    private let session: URLSession
    private let logger = Logger(subsystem: "app.healthpush", category: "Network")

    // MARK: Initialization

    /// Creates a network service with a custom URLSession configuration.
    /// - Parameter configuration: The URLSession configuration to use.
    init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    // MARK: Request Methods

    /// Performs an HTTP request and returns the decoded response.
    /// - Parameters:
    ///   - url: The full URL string.
    ///   - method: The HTTP method.
    ///   - headers: Additional HTTP headers.
    ///   - body: An optional encodable body.
    /// - Returns: The decoded response of the specified type.
    func request<T: Decodable & Sendable>(
        url: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> T {
        let data = try await performRequest(url: url, method: method, headers: headers, body: body)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Decoding failed: \(error.localizedDescription). Body: \(bodyString)")
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    /// Performs an HTTP request that returns no meaningful body (e.g., 200/201).
    /// - Parameters:
    ///   - url: The full URL string.
    ///   - method: The HTTP method.
    ///   - headers: Additional HTTP headers.
    ///   - body: An optional encodable body.
    func requestVoid(
        url: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil
    ) async throws {
        _ = try await performRequest(url: url, method: method, headers: headers, body: body)
    }

    /// Performs an HTTP request with a raw dictionary body.
    /// - Parameters:
    ///   - url: The full URL string.
    ///   - method: The HTTP method.
    ///   - headers: Additional HTTP headers.
    ///   - jsonBody: A dictionary to serialize as JSON.
    func requestWithDictionary(
        url: String,
        method: HTTPMethod = .post,
        headers: [String: String] = [:],
        jsonBody: [String: Any]
    ) async throws {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])

        let (data, response) = try await performURLRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    /// Sends a simple GET request to test connectivity.
    /// - Parameters:
    ///   - url: The URL to ping.
    ///   - headers: Additional HTTP headers.
    /// - Returns: The HTTP status code.
    func ping(url: String, headers: [String: String] = [:]) async throws -> Int {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.get.rawValue
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await performURLRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        return httpResponse.statusCode
    }

    // MARK: Private

    @discardableResult
    private func performRequest(
        url: String,
        method: HTTPMethod,
        headers: [String: String],
        body: (any Encodable & Sendable)?
    ) async throws -> Data {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                request.httpBody = try encoder.encode(body)
            } catch {
                throw NetworkError.encodingFailed(error.localizedDescription)
            }
        }

        let (data, response) = try await performURLRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            logger.error("HTTP \(httpResponse.statusCode) from \(url)")
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    private func performURLRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw NetworkError.timeout
            case .notConnectedToInternet,
                 .networkConnectionLost:
                throw NetworkError.connectionFailed("No internet connection.")
            default:
                throw NetworkError.connectionFailed(error.localizedDescription)
            }
        }
    }
}
