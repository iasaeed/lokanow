import XCTest
@testable import LocalizeCore

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class NetworkTests: XCTestCase {
    var client: LokaliseClient!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        client = LokaliseClient(token: "test-token", session: URLSession(configuration: config))
    }
    override func tearDown() { StubProtocol.handler = nil }
    func testCredentialRedirectsStayOnTheOriginalHTTPSOrigin() {
        let policy = LokaliseRedirectPolicy(origin: URL(string: "https://api.lokalise.com/api2")!)
        XCTAssertTrue(policy.allows(URL(string: "https://api.lokalise.com/api2/projects")!))
        XCTAssertFalse(policy.allows(URL(string: "https://other.example/projects")!))
        XCTAssertFalse(policy.allows(URL(string: "http://api.lokalise.com/projects")!))
        XCTAssertFalse(policy.allows(URL(string: "https://api.lokalise.com:8443/projects")!))
    }
    func testFetchesAllCursorPagesAndIncludesTranslations() async throws {
        var requests = 0
        StubProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Token"), "test-token")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "include_translations", value: "1")))
            if requests == 2 { XCTAssertTrue(query.contains(URLQueryItem(name: "cursor", value: "next-page"))) }
            let data = Data("{\"keys\":[{\"key_id\":\(requests),\"key_name\":{\"ios\":\"key\"},\"translations\":[]}]}".utf8)
            return (200, requests == 1 ? ["X-Pagination-Next-Cursor": "next-page"] : [:], data)
        }
        let keys = try await client.keys(project: "123.branch")
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(requests, 2)
    }
    func testAuthenticationFailureIsNotRetriedOrReportedMissing() async {
        var requests = 0
        StubProtocol.handler = { _ in requests += 1; return (401, [:], Data()) }
        do { _ = try await client.keys(project: "123"); XCTFail("Expected auth failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("token")); XCTAssertEqual(requests, 1) }
    }
    func testMalformedResponseFails() async {
        StubProtocol.handler = { _ in (200, [:], Data("{\"unexpected\":[]}".utf8)) }
        do { _ = try await client.keys(project: "123"); XCTFail("Expected malformed response failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Unexpected")) }
    }
    func testRepeatedCursorFails() async {
        StubProtocol.handler = { _ in (200, ["nextCursor": "same"], Data("{\"keys\":[]}".utf8)) }
        do { _ = try await client.keys(project: "123"); XCTFail("Expected repeated cursor failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("repeating")) }
    }
    func testRateLimitRecovers() async throws {
        var requests = 0
        StubProtocol.handler = { _ in requests += 1; return requests == 1 ? (429, ["Retry-After": "1"], Data()) : (200, [:], Data("{\"projects\":[]}".utf8)) }
        _ = try await client.projects(); XCTAssertEqual(requests, 2)
    }
    func testNonFiniteRetryHeaderDoesNotCrash() async throws {
        var requests = 0
        StubProtocol.handler = { _ in
            requests += 1
            return requests == 1 ? (429, ["Retry-After": "NaN"], Data()) : (200, [:], Data("{\"projects\":[]}".utf8))
        }
        _ = try await client.projects()
        XCTAssertEqual(requests, 2)
    }
    func testLanguagesOffsetPagination() async throws {
        var requests = 0
        StubProtocol.handler = { request in
            requests += 1
            if requests == 2 { XCTAssertTrue(request.url!.absoluteString.contains("page=2")) }
            return (200, ["X-Pagination-Page-Count": "2"], Data("{\"languages\":[{\"lang_id\":\(requests),\"lang_iso\":\"ar\",\"lang_name\":\"Arabic\"}]}".utf8))
        }
        let languages = try await client.languages(project: "123"); XCTAssertEqual(languages.count, 2)
    }
}
