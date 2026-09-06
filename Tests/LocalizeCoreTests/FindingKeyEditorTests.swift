import XCTest
@testable import LocalizeCore

final class FindingKeyEditorTests: XCTestCase {
    func testEditsReachSwiftAndCatalogAndPreserveReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Screen.swift")
        try Data(#"Text("Open account"); Text("Open account"); let other = "Needs checking""#.utf8).write(to: file)
        let module = Module(name: "Accounts", root: root, kind: "Application", sources: [file], resources: [], synchronizedRoot: root)
        var config = ModuleOptions(module: module)
        config.bundleConfirmed = true
        config.replacementTemplate = "{key}.bundleLocalized"
        let options = [module.id: config]
        let analysis = try Analyzer.analyze(modules: [module], allModules: [module], options: options)
        let item = try XCTUnwrap(analysis.findings.first { $0.english == "Open account" })
        let updated = try FindingKeyEditor.edit(id: item.id, key: "accounts.open.custom", findings: analysis.findings, snapshots: analysis.snapshots, options: options)
        XCTAssertEqual(updated.filter { $0.key == "accounts.open.custom" }.count, 2)
        XCTAssertTrue(updated.filter { $0.english == "Open account" }.allSatisfy { $0.replacement == #""accounts.open.custom".bundleLocalized"# })
        let plan = try Planner.registration(root: root, findings: updated, snapshots: analysis.snapshots, options: options, modules: [module])
        XCTAssertTrue(try XCTUnwrap(plan.changes.first { $0.url == file }).afterText.contains(#""accounts.open.custom".bundleLocalized"#))
        XCTAssertTrue(try XCTUnwrap(plan.changes.first { $0.url.pathExtension == "xcstrings" }).afterText.contains("accounts.open.custom"))
        let review = try XCTUnwrap(updated.first { $0.status == .review })
        let editedReview = try FindingKeyEditor.edit(id: review.id, key: "accounts.review", findings: updated, snapshots: analysis.snapshots, options: options)
        XCTAssertEqual(editedReview.first { $0.id == review.id }?.status, .review)
        XCTAssertNil(editedReview.first { $0.id == review.id }?.replacement)
        XCTAssertThrowsError(try FindingKeyEditor.edit(id: review.id, key: "accounts.open.custom", findings: updated, snapshots: analysis.snapshots, options: options))
        XCTAssertThrowsError(try FindingKeyEditor.edit(id: item.id, key: "bad..key", findings: updated, snapshots: analysis.snapshots, options: options))
        let resource = URL(fileURLWithPath: config.resourcePath)
        let catalog = Data(#"{"sourceLanguage":"en","version":"1.0","strings":{"accounts.taken":{"localizations":{"en":{"stringUnit":{"state":"translated","value":"Different"}}}}}}"#.utf8)
        var snapshots = analysis.snapshots; snapshots[resource] = catalog
        XCTAssertThrowsError(try FindingKeyEditor.edit(id: item.id, key: "accounts.taken", findings: updated, snapshots: snapshots, options: options))
    }
}
