import Foundation
import Testing
@testable import HealthPush

// MARK: - NetworkServiceTests

struct NetworkServiceTests {
    // MARK: Initialization

    @Test("Creates a network service with default configuration")
    func defaultInit() {
        let service = NetworkService()
        // Smoke test -- construction should not throw
        #expect(true)
        _ = service
    }

    @Test("Creates a network service with custom configuration")
    func customInit() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let service = NetworkService(configuration: config)
        #expect(true)
        _ = service
    }

    // MARK: URL Validation

    @Test("Empty URL throws invalidURL error")
    func invalidURL() async {
        let service = NetworkService()

        do {
            try await service.requestVoid(url: "")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case .invalidURL = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    // MARK: Error Types

    @Test("NetworkError has localized descriptions")
    func errorDescriptions() throws {
        let errors: [NetworkError] = [
            .invalidURL("http://bad"),
            .invalidResponse,
            .httpError(statusCode: 404, body: "Not Found"),
            .encodingFailed("test"),
            .decodingFailed("test"),
            .connectionFailed("test"),
            .timeout
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(try !(#require(error.errorDescription?.isEmpty)))
        }
    }

    // MARK: HTTP Methods

    @Test("HTTP method raw values are correct")
    func httpMethods() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }
}

// MARK: - NetworkServiceStubTests

/// Tests that exercise ``NetworkService`` with ``NetworkStubProtocol`` to verify
/// request/response handling without real network calls.
@Suite("NetworkService with NetworkStubProtocol", .serialized)
struct NetworkServiceStubTests {
    /// Creates a `NetworkService` backed by `NetworkStubProtocol`.
    private func makeStubService() -> NetworkService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkStubProtocol.self]
        return NetworkService(configuration: config)
    }

    /// Builds an `HTTPURLResponse` for the given URL and status code.
    private func makeResponse(url: String = "https://example.com/api", statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    // MARK: Tests

    @Test("200 response succeeds for requestVoid")
    func successfulVoidRequest() async throws {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 200), Data("{}".utf8))
        }

        try await service.requestVoid(
            url: "https://example.com/api",
            method: .post,
            headers: ["Authorization": "Bearer token"]
        )
    }

    @Test("200 response decodes JSON body")
    func successfulJSONDecode() async throws {
        let service = makeStubService()

        let json = #"{"name": "HealthPush", "version": 1}"#
        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 200), Data(json.utf8))
        }

        struct Info: Decodable, Sendable {
            let name: String
            let version: Int
        }

        let info: Info = try await service.request(url: "https://example.com/api")
        #expect(info.name == "HealthPush")
        #expect(info.version == 1)
    }

    @Test("500 response throws httpError")
    func serverErrorThrows() async {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 500), Data("Internal Server Error".utf8))
        }

        do {
            try await service.requestVoid(url: "https://example.com/api")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case let .httpError(statusCode, body) = error {
                #expect(statusCode == 500)
                #expect(body == "Internal Server Error")
            } else {
                #expect(Bool(false), "Wrong NetworkError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("401 response throws httpError with 401 status")
    func unauthorizedThrows() async {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 401), Data("Unauthorized".utf8))
        }

        do {
            try await service.requestVoid(url: "https://example.com/api")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case let .httpError(statusCode, _) = error {
                #expect(statusCode == 401)
            } else {
                #expect(Bool(false), "Wrong NetworkError case: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Timeout throws NetworkError.timeout")
    func timeoutThrows() async {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        do {
            try await service.requestVoid(url: "https://example.com/api")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case .timeout = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Expected timeout, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("Decoding invalid JSON throws decodingFailed")
    func invalidJSONThrows() async {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 200), Data("not json".utf8))
        }

        struct Dummy: Decodable, Sendable {
            let value: Int
        }

        do {
            let _: Dummy = try await service.request(url: "https://example.com/api")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case .decodingFailed = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Expected decodingFailed, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test("ping returns status code on success")
    func pingReturnsStatusCode() async throws {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            (self.makeResponse(statusCode: 200), Data())
        }

        let statusCode = try await service.ping(url: "https://example.com/api")
        #expect(statusCode == 200)
    }

    @Test("requestWithDictionary sends correct method and body")
    func requestWithDictionary() async throws {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "X-Custom") == "test")

            // Verify the body is valid JSON
            if let body = request.httpBody ?? request.httpBodyStream?.readAll() {
                let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                #expect(json?["key"] as? String == "value")
            }

            return (self.makeResponse(statusCode: 200), Data("{}".utf8))
        }

        try await service.requestWithDictionary(
            url: "https://example.com/api",
            method: .post,
            headers: ["X-Custom": "test"],
            jsonBody: ["key": "value"]
        )
    }

    @Test("Connection lost throws connectionFailed")
    func connectionLostThrows() async {
        let service = makeStubService()

        NetworkStubProtocol.requestHandler = { _ in
            throw URLError(.networkConnectionLost)
        }

        do {
            try await service.requestVoid(url: "https://example.com/api")
            #expect(Bool(false), "Should have thrown")
        } catch let error as NetworkError {
            if case .connectionFailed = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Expected connectionFailed, got: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}

// MARK: - InputStream Helper

private extension InputStream {
    /// Reads all bytes from the stream and returns them as `Data`.
    func readAll() -> Data {
        open()
        defer { close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while hasBytesAvailable {
            let count = read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
