import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

// MARK: - S3Signer

/// AWS Signature Version 4 signer for S3 REST API requests.
///
/// Implements the complete SigV4 signing process using CryptoKit-compatible APIs.
/// No third-party dependencies required.
///
/// Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
struct S3Signer {
    let accessKeyID: String
    let secretAccessKey: String
    let region: String

    // MARK: Signing

    /// Signs a URLRequest in place with AWS Signature V4 headers.
    ///
    /// After calling this method, the request will have the following headers set:
    /// - `x-amz-date`
    /// - `x-amz-content-sha256`
    /// - `Host`
    /// - `Authorization`
    ///
    /// - Parameters:
    ///   - request: The request to sign (modified in place).
    ///   - payloadHash: The hex-encoded SHA256 hash of the request body.
    ///   - date: The signing date (defaults to now; override for testing).
    func sign(_ request: inout URLRequest, payloadHash: String, date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")

        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)

        formatter.dateFormat = "yyyyMMdd"
        let dateStamp = formatter.string(from: date)

        // Set required headers before collecting them for signing
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        guard let url = request.url,
              let hostname = url.host() else { return }
        let host: String = if let port = url.port,
                              !(url.scheme == "https" && port == 443),
                              !(url.scheme == "http" && port == 80)
        {
            "\(hostname):\(port)"
        } else {
            hostname
        }
        request.setValue(host, forHTTPHeaderField: "Host")

        // --- Step 1: Canonical request ---

        let method = request.httpMethod ?? "GET"

        let canonicalURI: String = {
            let path = url.path(percentEncoded: true)
            return path.isEmpty ? "/" : path
        }()

        let canonicalQueryString: String = {
            guard let query = url.query(percentEncoded: true), !query.isEmpty else { return "" }
            return query.components(separatedBy: "&").sorted().joined(separator: "&")
        }()

        // Collect and sort headers by lowercase name
        var headerPairs: [(key: String, value: String)] = []
        if let all = request.allHTTPHeaderFields {
            for (k, v) in all {
                headerPairs.append((k.lowercased(), v.trimmingCharacters(in: .whitespaces)))
            }
        }
        headerPairs.sort { $0.key < $1.key }

        let canonicalHeaders = headerPairs.map { "\($0.key):\($0.value)" }.joined(separator: "\n") + "\n"
        let signedHeaders = headerPairs.map(\.key).joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        // --- Step 2: String to sign ---

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            Self.sha256Hex(canonicalRequest)
        ].joined(separator: "\n")

        // --- Step 3: Signing key ---

        let signingKey = deriveSigningKey(dateStamp: dateStamp)

        // --- Step 4: Signature ---

        let signature = Self.hmacHex(key: signingKey, data: stringToSign)

        // --- Step 5: Authorization header ---

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: Payload Hashing

    /// Computes the SHA-256 hash of data, returned as a lowercase hex string.
    static func payloadHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The SHA-256 hash of an empty payload (used for GET, HEAD, DELETE).
    static let emptyPayloadHash = payloadHash(Data())

    // MARK: Private

    private func deriveSigningKey(dateStamp: String) -> SymmetricKey {
        let kSecret = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        let kDate = Self.hmac(key: kSecret, data: dateStamp)
        let kRegion = Self.hmac(key: kDate, data: region)
        let kService = Self.hmac(key: kRegion, data: "s3")
        return Self.hmac(key: kService, data: "aws4_request")
    }

    private static func hmac(key: SymmetricKey, data: String) -> SymmetricKey {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return SymmetricKey(data: Data(mac))
    }

    private static func hmacHex(key: SymmetricKey, data: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
