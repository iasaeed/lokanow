import XCTest
@testable import LocalizeCore

final class TechnicalStringTests: XCTestCase {
    func testTechnicalValuesExcludedThroughAnalyzer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let values = ["0", "00", "0.00", "1", "٠", "٥", "١٬٠٠٠", "#,##0.00", "⃁ 0,000", ".", "•", "^[0-9]*$", "^[a-zA-Z0-9@._-]*$", "^[$0-9]+$", "pdf", ".pdf", "JPEG", "report.pdf", "assets/icon.png", "application/pdf", "image/*", "text/plain; charset=utf-8"]
        let source = root.appendingPathComponent("Screen.swift")
        try Data(values.map { "Text(\(KeyGenerator.quote($0)))" }.joined(separator: "\n").utf8).write(to: source)
        let module = Module(name: "Demo", root: root, kind: "Application", sources: [source], resources: [])
        let analysis = try Analyzer.analyze(modules: [module], allModules: [module], options: [:])
        XCTAssertEqual(analysis.findings.count, values.count)
        for finding in analysis.findings {
            XCTAssertEqual(finding.status, .excluded, finding.english)
            XCTAssertFalse(finding.selected, finding.english)
            XCTAssertNil(finding.replacement, finding.english)
        }
    }
    func testDisplayTextRemainsEligible() {
        for text in ["Upload a PDF", "You have 3 files", "3D view", "Version 1.0", "Enter a number", "Go", "A", "مرحبا", "لديك ٣ ملفات", "Open report.pdf", "^ Save $5", "Text with image/png inside"] {
            XCTAssertNil(TechnicalString.reason(text), text)
        }
    }
}
