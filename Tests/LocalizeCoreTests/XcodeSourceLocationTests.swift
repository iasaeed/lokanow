import XCTest
@testable import LocalizeCore

final class XcodeSourceLocationTests: XCTestCase {
    func testDocumentBookmarkAndOneBasedLine() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Source with spaces-" + UUID().uuidString + ".swift")
        try Data("// sample\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let event = try XcodeSourceLocation.event(file: file, line: 42)
        XCTAssertEqual(event.eventClass, 0x61657674)
        XCTAssertEqual(event.eventID, 0x6F646F63)
        XCTAssertEqual(event.paramDescriptor(forKeyword: 0x70726474)?.forKeyword(0x6C696E65)?.int32Value, 42)
        let bookmark = try XCTUnwrap(event.paramDescriptor(forKeyword: 0x2D2D2D2D)?.atIndex(1))
        XCTAssertEqual(bookmark.descriptorType, 0x626D726B)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark.data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, file.resolvingSymlinksInPath().path)
        let first = try XcodeSourceLocation.event(file: file, line: 0)
        XCTAssertEqual(first.paramDescriptor(forKeyword: 0x70726474)?.forKeyword(0x6C696E65)?.int32Value, 1)
    }
    func testRejectsRemoteURLs() {
        XCTAssertThrowsError(try XcodeSourceLocation.event(file: URL(string: "https://example.com/Screen.swift")!, line: 1))
    }
}
