import XCTest
@testable import LocalizeCore

final class ReviewResolutionTests: XCTestCase {
    func testFrameworkConfigurationMakesSafeUIStringsSelectable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Screen.swift")
        try Data(#"import SwiftUI; let title = Text("Open account"); let unknown = "Review this value""#.utf8).write(to: file)
        let module = Module(name: "Accounts", root: root, kind: "Framework", sources: [file], resources: [], synchronizedRoot: root)
        var config = ModuleOptions(module: module)
        let blocked = try Analyzer.analyze(modules: [module], allModules: [module], options: [module.id: config])
        let first = try XCTUnwrap(blocked.findings.first { $0.english == "Open account" })
        XCTAssertEqual(first.status, .review)
        XCTAssertTrue(first.reason.contains("bundle"))
        XCTAssertFalse(first.selected)
        config.bundleExpression = "Bundle(for: LocalizationBundleToken.self)"
        config.bundleConfirmed = true
        let resolved = try Analyzer.analyze(modules: [module], allModules: [module], options: [module.id: config])
        let ready = try XCTUnwrap(resolved.findings.first { $0.english == "Open account" })
        XCTAssertEqual(ready.status, .ready)
        XCTAssertTrue(ready.selected)
        XCTAssertTrue(try XCTUnwrap(ready.replacement).contains(config.bundleExpression))
        XCTAssertEqual(resolved.findings.first { $0.english == "Review this value" }?.status, .review)
        let plan = try Planner.registration(root: root, findings: resolved.findings, snapshots: resolved.snapshots, options: [module.id: config], modules: [module])
        XCTAssertTrue(plan.changes.contains { $0.url == file })
        XCTAssertTrue(plan.changes.contains { $0.url.path == config.resourcePath })
    }
}
