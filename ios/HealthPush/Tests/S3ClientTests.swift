import Foundation
import Testing
@testable import HealthPush

// MARK: - S3ClientTests

@Suite(.serialized)
struct S3ClientTests {
    @Test("Custom endpoints use path-style URLs and include the port in the signed host header")
    func customEndpointUsesPathStyleAddressing() async throws {
        let session = makeStubSession()

        URLProtocolStub.setHandler { request in
            #expect(
                request.url?.absoluteString
                    == "http://127.0.0.1:9000/minio/healthpush-ci?max-keys=0"
            )
            #expect(request.value(forHTTPHeaderField: "Host") == "127.0.0.1:9000")
            #expect(request.value(forHTTPHeaderField: "Authorization") != nil)

            let requestURL = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (response, Data())
        }
        defer { URLProtocolStub.reset() }

        let client = S3Client(
            bucket: "healthpush-ci",
            region: "us-east-1",
            accessKeyID: "minioadmin",
            secretAccessKey: "minioadmin",
            endpointOverride: "http://127.0.0.1:9000/minio/",
            session: session
        )

        let success = try await client.testConnection()
        #expect(success)
    }

    @Test("Invalid custom endpoints fail fast")
    func invalidEndpointThrowsConfigurationError() async {
        let client = S3Client(
            bucket: "healthpush-ci",
            region: "us-east-1",
            accessKeyID: "minioadmin",
            secretAccessKey: "minioadmin",
            endpointOverride: "not a url"
        )

        do {
            _ = try await client.testConnection()
            #expect(Bool(false), "Expected invalid configuration error")
        } catch let error as S3Error {
            switch error {
            case let .invalidConfiguration(message):
                #expect(message.contains("Invalid endpoint URL"))
            default:
                #expect(Bool(false), "Unexpected S3 error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("301 PermanentRedirect surfaces as wrongRegion with the bucket's actual region")
    func wrongRegionFromHeaderProducesActionableError() async throws {
        let session = makeStubSession()
        URLProtocolStub.setHandler { request in
            let requestURL = try #require(request.url)
            // AWS sets `x-amz-bucket-region` on every redirect response; this
            // is the most reliable source for the correct region.
            let response = try #require(HTTPURLResponse(
                url: requestURL,
                statusCode: 301,
                httpVersion: nil,
                headerFields: ["x-amz-bucket-region": "us-east-1"]
            ))
            return (response, Data("<?xml version=\"1.0\"?><Error><Code>PermanentRedirect</Code></Error>".utf8))
        }
        defer { URLProtocolStub.reset() }

        let client = S3Client(
            bucket: "my-bucket",
            region: "eu-west-1", // wrong on purpose
            accessKeyID: "AKIA...",
            secretAccessKey: "secret",
            session: session
        )

        do {
            _ = try await client.testConnection()
            #expect(Bool(false), "Expected wrongRegion error")
        } catch let S3Error.wrongRegion(configured, actual, bucket) {
            #expect(configured == "eu-west-1")
            #expect(actual == "us-east-1")
            #expect(bucket == "my-bucket")
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test("301 with no header falls back to parsing <Region> from the XML body")
    func wrongRegionFromBodyXmlAlsoWorks() async throws {
        let session = makeStubSession()
        URLProtocolStub.setHandler { request in
            let requestURL = try #require(request.url)
            // Headerless response — the body is the only source of truth.
            let response = try #require(HTTPURLResponse(
                url: requestURL,
                statusCode: 301,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Error>
              <Code>PermanentRedirect</Code>
              <Message>The bucket you are attempting to access must be addressed using the specified endpoint.</Message>
              <Bucket>my-bucket</Bucket>
              <Endpoint>my-bucket.s3.us-west-2.amazonaws.com</Endpoint>
              <Region>us-west-2</Region>
            </Error>
            """
            return (response, Data(body.utf8))
        }
        defer { URLProtocolStub.reset() }

        let client = S3Client(
            bucket: "my-bucket",
            region: "eu-west-1",
            accessKeyID: "AKIA...",
            secretAccessKey: "secret",
            session: session
        )

        do {
            _ = try await client.testConnection()
            #expect(Bool(false), "Expected wrongRegion error")
        } catch let S3Error.wrongRegion(_, actual, _) {
            #expect(actual == "us-west-2")
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

// MARK: - URLProtocolStub

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handler: Handler?

    static func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        URLProtocolStub.lock.lock()
        let handler = URLProtocolStub.handler
        URLProtocolStub.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

    override func stopLoading() { }
}
