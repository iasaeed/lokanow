import XCTest
@testable import LocalizeCore

final class TranslationCacheTests: XCTestCase {
    var directory: URL!
    var cache: TranslationCache!
    var client: LokaliseClient!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cache = TranslationCache(directory: directory)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        client = LokaliseClient(token: "test-token", session: URLSession(configuration: config))
    }
    override func tearDownWithError() throws {
        StubProtocol.handler = nil
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func body(_ id: Int) -> Data {
        Data("{\"keys\":[{\"key_id\":\(id),\"key_name\":{},\"translations\":[{\"language_iso\":\"en\",\"translation\":\"Hello\"},{\"language_iso\":\"ar\",\"translation\":\"مرحبا\"},{\"language_iso\":\"hi\",\"translation\":\"नमस्ते\"}]}]}".utf8)
    }
    func testAllPagesAndLanguagesPersistAcrossCacheInstances() async throws {
        var page = 0
        StubProtocol.handler = { _ in page += 1; return (200, page == 1 ? ["nextCursor": "next"] : [:], self.body(page)) }
        let snapshot = try await cache.refresh(client: client, token: "account-a", project: "p:branch")
        XCTAssertEqual(snapshot.keys.count, 2)
        let reopened = TranslationCache(directory: directory!)
        let cached = try await reopened.load(token: "account-a", project: "p:branch")
        XCTAssertEqual(cached?.keys.count, 2)
        XCTAssertEqual(cached?.keys.first?.translations.map(\.language_iso), ["en", "ar", "hi"])
        let otherAccount = try await reopened.load(token: "account-b", project: "p:branch")
        let otherBranch = try await reopened.load(token: "account-a", project: "p")
        XCTAssertNil(otherAccount); XCTAssertNil(otherBranch)
    }
    func testPartialFailurePreservesPreviousSnapshotAndEmptySuccessReplacesIt() async throws {
        StubProtocol.handler = { _ in (200, [:], self.body(1)) }
        let first = try await cache.refresh(client: client, token: "t", project: "p")
        var page = 0
        StubProtocol.handler = { _ in
            page += 1
            return page == 1 ? (200, ["nextCursor": "next"], self.body(2)) : (403, [:], Data())
        }
        do { _ = try await cache.refresh(client: client, token: "t", project: "p"); XCTFail("Expected failure") } catch {}
        let retained = try await cache.load(token: "t", project: "p")
        XCTAssertEqual(retained?.date, first.date)
        XCTAssertEqual(retained?.keys.map(\.id), [1])
        StubProtocol.handler = { _ in (200, [:], Data("{\"keys\":[]}".utf8)) }
        _ = try await cache.refresh(client: client, token: "t", project: "p")
        let empty = try await cache.load(token: "t", project: "p")
        XCTAssertEqual(empty?.keys.count, 0)
    }
    func testCancelledRefreshDoesNotReplaceCache() async throws {
        StubProtocol.handler = { _ in (200, [:], self.body(1)) }
        _ = try await cache.refresh(client: client, token: "t", project: "p")
        let cache = cache!, client = client!
        let task = Task {
            try await cache.refresh(client: client, token: "t", project: "p") { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let retained = try await cache.load(token: "t", project: "p")
        XCTAssertEqual(retained?.keys.map(\.id), [1])
    }
}
