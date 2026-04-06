import Testing
import Foundation
@testable import HealthPush

// MARK: - NetworkServiceTests

@Suite("NetworkService")
struct NetworkServiceTests {

    // MARK: Initialization

    @Test("Creates a network service with default configuration")
    func defaultInit() {
        let service = NetworkService()
        // Smoke test — construction should not throw
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
    func errorDescriptions() {
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
            #expect(!error.errorDescription!.isEmpty)
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
