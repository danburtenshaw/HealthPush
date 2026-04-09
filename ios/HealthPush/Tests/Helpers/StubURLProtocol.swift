import Foundation

/// A URLProtocol subclass that intercepts all requests and returns
/// canned responses configured via ``requestHandler``.
///
/// Used in tests to exercise ``NetworkService`` without real network calls.
/// Each test suite that needs HTTP stubbing should use its own subclass
/// (e.g. ``NetworkStubProtocol``, ``SyncEngineStubProtocol``) to avoid
/// shared-state races when Swift Testing runs suites in parallel.
class BaseStubURLProtocol: URLProtocol {
    class var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { nil }
        set { }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = type(of: self).handler else {
            let error = NSError(domain: "StubURLProtocol", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "requestHandler is not set"
            ])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Stub protocol for ``NetworkServiceStubTests``.
final class NetworkStubProtocol: BaseStubURLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { requestHandler }
        set { requestHandler = newValue }
    }
}

/// Stub protocol for ``SyncEngineTests``.
final class SyncEngineStubProtocol: BaseStubURLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { requestHandler }
        set { requestHandler = newValue }
    }
}
