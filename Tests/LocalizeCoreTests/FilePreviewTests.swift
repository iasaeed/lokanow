import XCTest
import AppKit
@testable import LocalizeCore

final class FilePreviewTests: XCTestCase {
    func testPagesPreserveUnicodeAndAllVersions() throws {
        let change = FileChange(url: URL(fileURLWithPath: "/tmp/Localizable.xcstrings"), before: Data("مرحبا\nOld".utf8), after: Data("مرحبا 👨‍👩‍👧‍👦\nNew\n".utf8), reason: "Test")
        for mode in ["Before", "After", "Diff"] {
            let pages = try FilePreview.pages(change, mode: mode, limit: 3)
            XCTAssertTrue(pages.allSatisfy { $0.count <= 3 })
            XCTAssertEqual(pages.joined(), mode == "Diff" ? FileDiff.unified(change) : (mode == "Before" ? change.beforeText : change.afterText))
        }
    }
    func testLargeCatalogAndLongLinesRemainBounded() throws {
        let text = String(repeating: "  \"sample.key\": {\"value\": \"Hello\"},\n", count: 100_000) + String(repeating: "x", count: 100_000)
        let change = FileChange(url: URL(fileURLWithPath: "/tmp/Localizable.xcstrings"), before: nil, after: Data(text.utf8), reason: "Test")
        let start = Date()
        let pages = try FilePreview.pages(change, mode: "Diff")
        XCTAssertGreaterThan(pages.count, 100)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 16_000 })
        XCTAssertEqual(pages.joined(), FileDiff.unified(change))
        print("LARGE_PREVIEW_SECONDS: \(Date().timeIntervalSince(start))")
    }
    func testNativeRenderingPreservesTextAndColors() {
        let text = "@@ header\n+مرحبا 👋\n-old\n unchanged\n"
        let result = FilePreview.attributedPage(text, isDiff: true)
        XCTAssertEqual(result.string, text)
        let plus = (text as NSString).range(of: "+مرحبا").location
        XCTAssertEqual(result.attribute(.foregroundColor, at: plus, effectiveRange: nil) as? NSColor, .systemGreen)
        let plain = FilePreview.attributedPage(text, isDiff: false)
        XCTAssertEqual(plain.attribute(.foregroundColor, at: plus, effectiveRange: nil) as? NSColor, .textColor)
    }
    func testDensePagesRenderWithoutAttributedStringAppending() {
        let text = String(repeating: "+x\n-y\n", count: 2_000)
        let start = Date()
        for _ in 0..<10 { XCTAssertEqual(FilePreview.attributedPage(text, isDiff: true).string, text) }
        print("NATIVE_PREVIEW_TEN_RENDERS_SECONDS: \(Date().timeIntervalSince(start))")
    }
    func testCancelledPreparationStops() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let change = FileChange(url: URL(fileURLWithPath: "/tmp/Empty"), before: nil, after: Data(), reason: "Test")
            return try FilePreview.pages(change, mode: "After")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
