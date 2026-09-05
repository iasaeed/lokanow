import XCTest
@testable import LocalizeCore

final class AnalyzerExclusionTests: XCTestCase {
    func testTechnicalStringsExcludedWithoutDroppingRealText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Screen.swift")
        let text = #"""
        import SwiftUI
        enum CodingKeys: String, CodingKey { case name = "customer_name" }
        enum PayloadFields: String, Swift.CodingKey { case date = "created_at" }
        enum DisplayChoice: String { case title = "Account details" }
        let result = text.replacingOccurrences(of: "old text", with: "new text")
        let comma = text.replacingOccurrences(of: ",", with: "")
        let parts = text.components(separatedBy: "separator")
        let model = Item(id: "\(index)", title: "Visible title")
        let id = "\(index)"
        let fileName = "\(fallbackFileName).\(fileExtension)"
        let path = "\(directory)/\(name)"
        let value = "\(amount)"
        Text("\(count) messages")
        item.identifier = "\(index)"
        Text("A").id("stable_row")
        let color = "#FF00AA"
        let otherColor = Color(hex: "FACE")
        Text(".")
        Text("⃁")
        Text("!")
        Text("مرحبا")
        Text("Welcome!")
        Text("FACE")
        Text("{n}")
        Text("{0} {count}")
        Text("\n")
        Text("\\n")
        Text("You have {n} messages")
        Text("Hello \(name)")
        NSLocalizedString(".", comment: "")
        """#
        try Data(text.utf8).write(to: source)
        let resource = root.appendingPathComponent("Localizable.xcstrings")
        try Data(#"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8).write(to: resource)
        let module = Module(name: "Demo", root: root, kind: "Application", sources: [source], resources: [resource])
        var options = ModuleOptions(module: module)
        options.resourcePath = resource.path; options.bundleConfirmed = true
        let analysis = try Analyzer.analyze(modules: [module], allModules: [module], options: [module.id: options])
        for value in ["customer_name", "created_at", "old text", "new text", ",", "", "separator", "stable_row", "#FF00AA", ".", "⃁", "!", "{n}", "{0} {count}", "\n", "\\n"] {
            let found = analysis.findings.filter { $0.english == value }
            XCTAssertFalse(found.isEmpty, value)
            XCTAssertTrue(found.allSatisfy { $0.status == .excluded && !$0.selected && $0.replacement == nil }, value)
        }
        for literal in [#""\(fallbackFileName).\(fileExtension)""#, #""\(directory)/\(name)""#, #""\(amount)""#] {
            XCTAssertEqual(analysis.findings.first { $0.literal == literal }?.status, .excluded)
        }
        XCTAssertEqual(analysis.findings.first { $0.literal == #""\(count) messages""# }?.status, .dynamic)
        let identifiers = analysis.findings.filter { $0.literal == #""\(index)""# }
        XCTAssertEqual(identifiers.count, 3)
        XCTAssertTrue(identifiers.allSatisfy { $0.status == .excluded })
        for value in ["A", "مرحبا", "Welcome!"] {
            XCTAssertEqual(analysis.findings.first { $0.english == value }?.status, .ready, value)
        }
        XCTAssertEqual(analysis.findings.first { $0.english == "Account details" }?.status, .review)
        XCTAssertEqual(analysis.findings.first { $0.english == "You have {n} messages" }?.status, .review)
        XCTAssertEqual(analysis.findings.first { $0.english == "Visible title" }?.status, .review)
        XCTAssertEqual(analysis.findings.filter { $0.english == "FACE" }.map(\.status), [.excluded, .ready])
        XCTAssertEqual(analysis.findings.first { $0.literal == #""Hello \(name)""# }?.status, .dynamic)
    }
}
