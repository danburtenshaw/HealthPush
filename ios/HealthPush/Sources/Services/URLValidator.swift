import Foundation

// MARK: - URLValidationResult

/// The outcome of validating a webhook URL.
enum URLValidationResult: Equatable {
    /// The URL is valid (HTTPS, or HTTP to an allowed local network address).
    case valid

    /// The URL uses HTTP but targets a local network address, which is permitted.
    case httpAllowedLocalNetwork

    /// The URL is invalid. The associated value describes the problem.
    case invalid(String)

    var isAcceptable: Bool {
        switch self {
        case .valid, .httpAllowedLocalNetwork: true
        case .invalid: false
        }
    }

    var isHTTP: Bool {
        switch self {
        case .httpAllowedLocalNetwork: true
        default: false
        }
    }

    var errorMessage: String? {
        switch self {
        case let .invalid(message): message
        default: nil
        }
    }
}

// MARK: - URLValidator

/// Validates webhook URLs, enforcing HTTPS for public endpoints and allowing
/// HTTP only for local network addresses.
///
/// Local network addresses that permit HTTP:
/// - RFC 1918 private IPs: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`
/// - Link-local: `169.254.0.0/16`
/// - Loopback: `127.0.0.0/8`
/// - Local domains: `.local`, `.lan`, `.home.arpa`
enum URLValidator {
    /// Validates a webhook URL string.
    ///
    /// - Parameter urlString: The URL string to validate.
    /// - Returns: A ``URLValidationResult`` indicating whether the URL is acceptable.
    static func validateWebhookURL(_ urlString: String) -> URLValidationResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmed) else {
            return .invalid("Enter a valid URL.")
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .invalid("URL must start with http:// or https://.")
        }

        guard let host = url.host()?.lowercased(), !host.isEmpty else {
            return .invalid("URL must include a hostname.")
        }

        // HTTPS is always allowed
        if scheme == "https" {
            return .valid
        }

        // HTTP: only allowed for local network addresses
        if isLocalNetworkHost(host) {
            return .httpAllowedLocalNetwork
        }

        return .invalid("HTTP is only allowed for local network addresses. Use https:// for public servers.")
    }

    // MARK: Private

    /// Determines whether a hostname is a local network address.
    ///
    /// Checks against RFC 1918 private IP ranges, link-local, loopback,
    /// and well-known local domain suffixes.
    private static func isLocalNetworkHost(_ host: String) -> Bool {
        // Check local domain suffixes
        let localSuffixes = [".local", ".lan", ".home.arpa"]
        for suffix in localSuffixes {
            if host == String(suffix.dropFirst()) || host.hasSuffix(suffix) {
                return true
            }
        }

        // Parse as IPv4 and check private ranges
        if let ipv4 = parseIPv4(host) {
            return isPrivateIPv4(ipv4)
        }

        // IPv6 loopback ::1
        let stripped = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if stripped == "::1" {
            return true
        }

        return false
    }

    /// Parses an IPv4 address string into four octets.
    ///
    /// - Parameter string: A dotted-decimal IPv4 address (e.g. "192.168.1.1").
    /// - Returns: A tuple of four `UInt8` octets, or `nil` if the string is not valid IPv4.
    private static func parseIPv4(_ string: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return nil }
        guard let a = UInt8(parts[0]),
              let b = UInt8(parts[1]),
              let c = UInt8(parts[2]),
              let d = UInt8(parts[3])
        else { return nil }
        return (a, b, c, d)
    }

    /// Determines whether an IPv4 address is in a private or local range.
    ///
    /// Recognized ranges:
    /// - `10.0.0.0/8` (RFC 1918)
    /// - `172.16.0.0/12` (RFC 1918)
    /// - `192.168.0.0/16` (RFC 1918)
    /// - `169.254.0.0/16` (link-local)
    /// - `127.0.0.0/8` (loopback)
    private static func isPrivateIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = ip

        // 10.0.0.0/8
        if a == 10 { return true }

        // 172.16.0.0/12 (172.16.x.x – 172.31.x.x)
        if a == 172, (16...31).contains(b) { return true }

        // 192.168.0.0/16
        if a == 192, b == 168 { return true }

        // 169.254.0.0/16 (link-local)
        if a == 169, b == 254 { return true }

        // 127.0.0.0/8 (loopback)
        if a == 127 { return true }

        return false
    }
}
