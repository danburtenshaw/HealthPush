import Testing
@testable import HealthPushStorageCore

@Suite("S3ClientCompatibility")
struct S3ClientCompatibilityTests {
    @Test("Custom endpoints normalize trailing slashes")
    func normalizedEndpoint() {
        #expect(S3Client.normalizedEndpoint(" https://s3.example.com/path/ ") == "https://s3.example.com/path")
    }

    @Test("Endpoint validation rejects invalid URLs")
    func validateEndpoint() {
        #expect(S3Client.validateEndpoint("not a url") != nil)
        #expect(S3Client.validateEndpoint("https://s3.example.com") == nil)
        #expect(S3Client.validateEndpoint("") == nil)
    }
}
