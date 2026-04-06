import Foundation
import os

// MARK: - S3Error

/// Errors specific to S3 operations.
enum S3Error: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case connectionFailed(String)
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg):
            return "Invalid S3 configuration: \(msg)"
        case .uploadFailed(let msg):
            return "S3 upload failed: \(msg)"
        case .downloadFailed(let msg):
            return "S3 download failed: \(msg)"
        case .connectionFailed(let msg):
            return "S3 connection failed: \(msg)"
        case .authenticationFailed:
            return "S3 authentication failed. Check your access keys."
        }
    }
}

// MARK: - S3Client

/// A lightweight S3 client using the REST API with Signature V4 authentication.
///
/// Supports GET, PUT, and HEAD operations against a single bucket.
/// Uses only URLSession — no third-party dependencies.
struct S3Client: Sendable {

    let bucket: String
    let region: String

    private let signer: S3Signer
    private let session: URLSession
    private let logger = Logger(subsystem: "com.healthpush.app", category: "S3Client")

    init(bucket: String, region: String, accessKeyID: String, secretAccessKey: String) {
        self.bucket = bucket
        self.region = region
        self.signer = S3Signer(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, region: region)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    /// The S3 virtual-hosted-style endpoint for this bucket.
    private var endpoint: String {
        "https://\(bucket).s3.\(region).amazonaws.com"
    }

    // MARK: Operations

    /// Downloads an object from S3.
    /// - Parameter key: The S3 object key.
    /// - Returns: The object data, or `nil` if the object does not exist (HTTP 404).
    func getObject(key: String) async throws -> Data? {
        let urlString = "\(endpoint)/\(key.s3PercentEncoded)"
        guard let url = URL(string: urlString) else {
            throw S3Error.invalidConfiguration("Invalid S3 URL for key: \(key)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        signer.sign(&request, payloadHash: S3Signer.emptyPayloadHash)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw S3Error.connectionFailed("Invalid response")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 404:
            return nil
        case 403:
            throw S3Error.authenticationFailed
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw S3Error.downloadFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    /// Uploads an object to S3.
    /// - Parameters:
    ///   - key: The S3 object key.
    ///   - data: The object data.
    ///   - contentType: The MIME content type.
    func putObject(key: String, data: Data, contentType: String) async throws {
        let urlString = "\(endpoint)/\(key.s3PercentEncoded)"
        guard let url = URL(string: urlString) else {
            throw S3Error.invalidConfiguration("Invalid S3 URL for key: \(key)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let payloadHash = S3Signer.payloadHash(data)
        signer.sign(&request, payloadHash: payloadHash)

        let (responseData, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw S3Error.connectionFailed("Invalid response")
        }

        switch http.statusCode {
        case 200...299:
            logger.debug("Uploaded \(data.count) bytes to s3://\(self.bucket)/\(key)")
        case 403:
            throw S3Error.authenticationFailed
        default:
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw S3Error.uploadFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    /// Tests connectivity by listing the bucket with zero results.
    ///
    /// This verifies that the credentials are valid and the bucket is accessible
    /// without downloading any objects.
    func testConnection() async throws -> Bool {
        let urlString = "\(endpoint)/?max-keys=0"
        guard let url = URL(string: urlString) else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        signer.sign(&request, payloadHash: S3Signer.emptyPayloadHash)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw S3Error.connectionFailed("Invalid response")
        }

        switch http.statusCode {
        case 200...299:
            return true
        case 403:
            throw S3Error.authenticationFailed
        case 404:
            throw S3Error.invalidConfiguration("Bucket '\(bucket)' not found")
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw S3Error.connectionFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    // MARK: Private

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw S3Error.connectionFailed("Request timed out")
            case .notConnectedToInternet, .networkConnectionLost:
                throw S3Error.connectionFailed("No internet connection")
            default:
                throw S3Error.connectionFailed(error.localizedDescription)
            }
        }
    }
}

// MARK: - String + S3 Encoding

extension String {
    /// Percent-encodes an S3 object key, preserving forward slashes as path separators.
    ///
    /// Each path segment is encoded per RFC 3986 unreserved characters.
    var s3PercentEncoded: String {
        components(separatedBy: "/")
            .map { segment in
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-_.~")
                return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
            }
            .joined(separator: "/")
    }
}
