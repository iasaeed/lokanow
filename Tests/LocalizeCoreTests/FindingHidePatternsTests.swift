import XCTest
import SwiftParser
import SwiftSyntax
@testable import LocalizeCore

final class FindingHidePatternsTests: XCTestCase {
    private func findings(_ source: String) -> [Finding] {
        let visitor = Literals(viewMode: .sourceAccurate)
        visitor.walk(Parser.parse(source: source))
        return visitor.nodes.map { node in
            Finding(id: String(node.position.utf8Offset), moduleID: "demo", moduleName: "Demo", file: URL(fileURLWithPath: "/tmp/Screen.swift"), line: 1, offset: 0, length: 0, literal: node.trimmedDescription, english: node.representedLiteralValue ?? "", key: "demo.key", status: .review, reason: "Review", context: "String", selected: false, sourceForms: FindingHidePatterns.sourceForms(node))
        }
    }
    func testDefaultMatchesOnlyItsLiteralAndIgnoresWhitespace() {
        let rows = findings(#"Text("Welcome" . Localized ()); Text("Visible"); Text("Lower".localized())"#)
        let filter = FindingHidePatterns("{text}.Localized()")
        XCTAssertEqual(rows.map { filter.matches($0) }, [true, false, false])
    }
    func testMultiplePatternsAndNestedComma() {
        let rows = findings(#"Text("Welcome".localized); Text(.localize("Hello")); translate("Save", bundle: .module); Text("Visible")"#)
        let filter = FindingHidePatterns(#" "{text}".localized, .localize({text}), translate({text}, bundle: .module), "#)
        XCTAssertEqual(rows.map { filter.matches($0) }, [true, true, true, false])
    }
    func testKeyFormatsAreAnchoredAndEmptyPatternsHideNothing() {
        let rows = findings(#"Text("ac.home.title"); Text("unrelated ac.home.title"); Text("Welcome")"#)
        XCTAssertEqual(rows.map { FindingHidePatterns("ac.*").matches($0) }, [true, false, false])
        XCTAssertFalse(rows.contains { FindingHidePatterns(" , , ").matches($0) })
        XCTAssertTrue(rows.allSatisfy { FindingHidePatterns("demo.*").matches($0) })
    }
    func testOldFindingsDecodeWithoutSourceForms() throws {
        let row = try XCTUnwrap(findings(#"Text("Welcome")"#).first)
        let data = try JSONEncoder().encode(row)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sourceForms")
        let decoded = try JSONDecoder().decode(Finding.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.sourceForms)
    }
}
private final class Literals: SyntaxVisitor {
    var nodes: [StringLiteralExprSyntax] = []
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(node)
        return .skipChildren
    }
}
