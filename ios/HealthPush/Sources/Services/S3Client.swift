import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(os)
import os
#endif

// MARK: - S3Error

/// Errors specific to S3 operations.
enum S3Error: LocalizedError {
    case invalidConfiguration(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case connectionFailed(String)
    case authenticationFailed
    /// AWS returned a 301/307 PermanentRedirect/TemporaryRedirect indicating the
    /// bucket lives in a different region than the one configured. The actual
    /// region is extracted from the `x-amz-bucket-region` response header (or
    /// the `<Region>` element in the XML body as a fallback).
    case wrongRegion(configured: String, actual: String, bucket: String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(msg):
            "Invalid S3 configuration: \(msg)"
        case let .uploadFailed(msg):
            "S3 upload failed: \(msg)"
        case let .downloadFailed(msg):
            "S3 download failed: \(msg)"
        case let .connectionFailed(msg):
            "S3 connection failed: \(msg)"
        case .authenticationFailed:
            "S3 authentication failed. Check your access keys."
        case let .wrongRegion(configured, actual, _):
            // Short on purpose — this string is shown in the dashboard nudge
            // (which has limited width). The full bucket name and longer
            // guidance live in the recovery action that the detail view shows.
            "Bucket region is '\(actual)', not '\(configured)'. Update this destination's region."
        }
    }
}

// MARK: - S3Client

/// A lightweight S3 client using the REST API with Signature V4 authentication.
///
/// Supports AWS S3 plus S3-compatible endpoints such as MinIO.
/// Uses only URLSession — no third-party dependencies.
struct S3Client {
    let bucket: String
    let region: String

    private let signer: S3Signer
    private let endpointOverride: String?
    private let session: URLSession

    #if canImport(os)
    private let logger = Logger(subsystem: "app.healthpush", category: "S3Client")
    private let signposter = OSSignposter(subsystem: "app.healthpush", category: "Performance")
    #endif

    init(
        bucket: String,
        region: String,
        accessKeyID: String,
        secretAccessKey: String,
        endpointOverride: String? = nil,
        session: URLSession? = nil
    ) {
        self.bucket = bucket
        self.region = region
        signer = S3Signer(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey, region: region)
        let normalizedEndpoint = endpointOverride.map(Self.normalizedEndpoint)
        self.endpointOverride = normalizedEndpoint?.isEmpty == false ? normalizedEndpoint : nil

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: config)
        }
    }

    static func normalizedEndpoint(_ endpoint: String) -> String {
        endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func validateEndpoint(_ endpoint: String) -> String? {
        let normalized = normalizedEndpoint(endpoint)
        if normalized.isEmpty { return nil }

        guard let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil
        else {
            return "Enter a full http:// or https:// endpoint"
        }

        return nil
    }

    // MARK: Operations

    /// Downloads an object from S3.
    /// - Parameter key: The S3 object key.
    /// - Returns: The object data, or `nil` if the object does not exist (HTTP 404).
    func getObject(key: String) async throws -> Data? {
        #if canImport(os)
        let state = signposter.beginInterval("getObject")
        #endif
        let url = try objectURL(for: key)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        signer.sign(&request, payloadHash: S3Signer.emptyPayloadHash)

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            #if canImport(os)
            signposter.endInterval("getObject", state)
            #endif
            throw S3Error.connectionFailed("Invalid response")
        }

        #if canImport(os)
        signposter.endInterval("getObject", state)
        #endif
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
        #if canImport(os)
        let state = signposter.beginInterval("putObject")
        #endif
        let url = try objectURL(for: key)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let payloadHash = S3Signer.payloadHash(data)
        signer.sign(&request, payloadHash: payloadHash)

        let (responseData, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            #if canImport(os)
            signposter.endInterval("putObject", state)
            #endif
            throw S3Error.connectionFailed("Invalid response")
        }

        #if canImport(os)
        signposter.endInterval("putObject", state)
        #endif
        switch http.statusCode {
        case 200...299:
            #if canImport(os)
            logger.debug("Uploaded \(data.count) bytes to s3://\(bucket)/\(key)")
            #endif
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
        let url = try bucketURL(queryItems: [URLQueryItem(name: "max-keys", value: "0")])
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

    private func objectURL(for key: String) throws -> URL {
        try bucketURL(key: key)
    }

    private func bucketURL(
        key: String? = nil,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        if let endpointOverride {
            return try pathStyleURL(
                endpointOverride: endpointOverride,
                bucket: bucket,
                key: key,
                queryItems: queryItems
            )
        }

        return try virtualHostedURL(bucket: bucket, region: region, key: key, queryItems: queryItems)
    }

    private func pathStyleURL(
        endpointOverride: String,
        bucket: String,
        key: String?,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard var components = URLComponents(string: endpointOverride),
              components.host != nil
        else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL: \(endpointOverride)")
        }

        let bucketPath = bucket.s3PathComponentEncoded
        let keyPath = key.map { "/\($0.s3PercentEncoded)" } ?? ""
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = basePath.isEmpty
            ? "/\(bucketPath)\(keyPath)"
            : "/\(basePath)/\(bucketPath)\(keyPath)"

        components.percentEncodedPath = fullPath
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw S3Error.invalidConfiguration("Invalid endpoint URL: \(endpointOverride)")
        }

        return url
    }

    private func virtualHostedURL(
        bucket: String,
        region: String,
        key: String?,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(bucket).s3.\(region).amazonaws.com"
        components.percentEncodedPath = key.map { "/\($0.s3PercentEncoded)" } ?? "/"
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw S3Error.invalidConfiguration("Invalid S3 configuration for bucket: \(bucket)")
        }

        return url
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let pair: (Data, URLResponse)
        do {
            pair = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw S3Error.connectionFailed("Request was cancelled")
            case .timedOut:
                throw S3Error.connectionFailed("Request timed out")
            case .notConnectedToInternet,
                 .networkConnectionLost:
                throw S3Error.connectionFailed("No internet connection")
            default:
                throw S3Error.connectionFailed(error.localizedDescription)
            }
        }

        let (data, response) = pair

        // AWS returns 301 PermanentRedirect (or 307 during bucket creation
        // propagation) when the bucket lives in a different region than the
        // request was sent to. The correct region comes back in the
        // `x-amz-bucket-region` response header. Surface this as a dedicated
        // error so the user can be told exactly what to set the region to,
        // instead of seeing a raw XML payload.
        if let http = response as? HTTPURLResponse,
           http.statusCode == 301 || http.statusCode == 307,
           let actualRegion = Self.extractBucketRegion(from: http, body: data)
        {
            throw S3Error.wrongRegion(configured: region, actual: actualRegion, bucket: bucket)
        }

        return (data, response)
    }

    /// Extracts the bucket's actual region from a 301/307 response.
    /// Prefers the `x-amz-bucket-region` header (set by AWS on every redirect
    /// response) and falls back to parsing `<Region>` from the XML body.
    static func extractBucketRegion(from response: HTTPURLResponse, body: Data) -> String? {
        if let header = response.value(forHTTPHeaderField: "x-amz-bucket-region"),
           !header.isEmpty
        {
            return header
        }
        guard let xml = String(data: body, encoding: .utf8) else { return nil }
        return extractFirstXMLElement(named: "Region", in: xml)
    }

    /// Lightweight XML element extractor. Pulls the inner text of the first
    /// `<\(name)>...</\(name)>` element it finds. We avoid pulling in an XML
    /// parser dependency for this single AWS error case.
    private static func extractFirstXMLElement(named name: String, in xml: String) -> String? {
        let openTag = "<\(name)>"
        let closeTag = "</\(name)>"
        guard let openRange = xml.range(of: openTag),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex)
        else {
            return nil
        }
        let value = xml[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

    var s3PathComponentEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
