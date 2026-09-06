import XCTest
@testable import LocalizeCore

final class FindingSearchTests: XCTestCase {
    private func row(_ id: Int, text: String, key: String, status: FindingStatus = .ready) -> Finding {
        Finding(id: String(id), moduleID: "m", moduleName: "Accounts", file: URL(fileURLWithPath: "/tmp/Screen.swift"), line: 1, offset: 0, length: 0, literal: text, english: text, key: key, status: status, reason: "", context: "", selected: false)
    }
    func testSearchCombinesQueryVisibilityAndOrdering() throws {
        let rows = [row(1, text: "Welcome", key: "app.welcome"), row(2, text: "مرحبا", key: "app.arabic"), row(3, text: "Welcome", key: "app.hidden"), row(4, text: "Welcome", key: "app.excluded", status: .excluded)]
        func search(_ query: String, _ status: String = "All actionable") throws -> [String] {
            try FindingSearch.results(rows, query: query, status: status, hiddenIDs: ["3"], sortOrder: [KeyPathComparator(\Finding.key)]).map(\.id)
        }
        XCTAssertEqual(try search("WELCOME"), ["1"])
        XCTAssertEqual(try search("app.arabic"), ["2"])
        XCTAssertEqual(try search("مرح"), ["2"])
        XCTAssertEqual(try search("accounts"), ["2", "1"])
        XCTAssertEqual(try search("", "Everything"), ["2", "4", "1"])
        XCTAssertTrue(try search("missing").isEmpty)
    }
    func testLargeSearchAndCancellation() async throws {
        let rows = (0..<25_000).map { row($0, text: "Message \($0)", key: "app.message.\($0)") }
        let start = Date()
        let result = try FindingSearch.results(rows, query: "24999", status: "All actionable", hiddenIDs: [], sortOrder: [])
        XCTAssertEqual(result.map(\.id), ["24999"])
        print("SEARCH_25000_SECONDS: \(Date().timeIntervalSince(start))")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FindingSearch.results(rows, query: "", status: "Everything", hiddenIDs: [], sortOrder: [])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
