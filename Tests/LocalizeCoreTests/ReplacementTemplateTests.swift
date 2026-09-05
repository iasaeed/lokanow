import XCTest
@testable import LocalizeCore

extension CoreTests {
    func testReplacementTemplatesPreserveWrappersAndAreIdempotent() throws {
        for template in ["{key}.bundleLocalized", "{key}.localized", ".localize({key})", "Legacy.translate({key})", "{key}"] {
            let source = try write("Screen.swift", "import SwiftUI\nlet title = Text(\"Open account\")\nlet asset = Image(\"hero\")\nlet unknown = \"Internal value\"\nlet old = Text(NSLocalizedString(\"Continue\", comment: \"\"))")
            let resource = try catalog()
            let target = module(source: source, resource: resource)
            var config = ModuleOptions(module: target); config.replacementTemplate = template
            let options = [target.id: config]
            let analysis = try Analyzer.analyze(modules: [target], allModules: [target], options: options)
            XCTAssertEqual(analysis.findings.filter { $0.status == .ready }.count, 2, template)
            XCTAssertEqual(analysis.findings.first { $0.english == "Internal value" }?.status, .review)
            let plan = try Planner.registration(root: root, findings: analysis.findings, snapshots: analysis.snapshots, options: options, modules: [target])
            try Transactions.apply(plan)
            let rewritten = try String(contentsOf: source, encoding: .utf8)
            XCTAssertTrue(rewritten.contains("Text(" + (try ReplacementTemplate.render(template, key: "ac.open.account")) + ")"), rewritten)
            XCTAssertTrue(rewritten.contains("NSLocalizedString(\"ac.continue\", comment: \"\")"), rewritten)
            XCTAssertTrue(rewritten.contains("Image(\"hero\")"))
            let again = try Analyzer.analyze(modules: [target], allModules: [target], options: options)
            XCTAssertEqual(again.findings.filter { $0.status == .ready }.count, 0, template)
            XCTAssertEqual(again.findings.filter { $0.status == .localized }.count, 2, template)
            try Transactions.undo(root: root)
        }
    }

    func testReplacementTemplateValidationAndEscaping() throws {
        for invalid in [".localized", "\"{key}\".localized", "localize({key}", "{key}; print(\"side effect\")", "{key}, other = 1"] {
            XCTAssertNotNil(ReplacementTemplate.validationError(invalid), invalid)
        }
        XCTAssertNil(ReplacementTemplate.validationError(nil))
        XCTAssertNil(ReplacementTemplate.validationError(""))
        XCTAssertEqual(try ReplacementTemplate.render("Legacy.localize({key})", key: "a\"b"), "Legacy.localize(\"a\\\"b\")")
        let source = try write("Screen.swift", "let title = Text(\"Open account\")")
        let target = module(source: source, resource: try catalog())
        var config = ModuleOptions(module: target); config.replacementTemplate = "bad({key}"
        let result = try Analyzer.analyze(modules: [target], allModules: [target], options: [target.id: config])
        XCTAssertEqual(result.findings.first?.status, .review)
        XCTAssertNil(result.findings.first?.replacement)
    }

    func testModuleTemplatePersistenceAndOlderSettingsCompatibility() throws {
        let target = module(source: root.appendingPathComponent("Screen.swift"), resource: try catalog())
        var config = ModuleOptions(module: target)
        config.replacementTemplate = "{key}.bundleLocalized"
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(ModuleOptions.self, from: data).replacementTemplate, config.replacementTemplate)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "replacementTemplate")
        XCTAssertNil(try JSONDecoder().decode(ModuleOptions.self, from: JSONSerialization.data(withJSONObject: old)).replacementTemplate)
    }
}
