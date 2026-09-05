import XCTest
@testable import LocalizeCore

final class CoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalizeTests-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }
    @discardableResult func write(_ name: String, _ text: String) throws -> URL { let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(text.utf8).write(to: url); return url }
    func catalog(_ strings: [String: Any] = [:]) throws -> URL { let url = root.appendingPathComponent("Localizable.xcstrings"); try JSONSerialization.data(withJSONObject: ["sourceLanguage": "en", "version": "1.0", "strings": strings]).write(to: url); return url }
    func module(source: URL, resource: URL) -> Module { Module(name: "Account Center", root: root, kind: "Application", sources: [source], resources: [resource], synchronizedRoot: root) }
    func testKeyNormalizationAndCollision() {
        XCTAssertEqual(KeyGenerator.prefix("Account Center"), "ac")
        XCTAssertEqual(KeyGenerator.prefix("AccountCenter"), "ac")
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: "How to Open an account", existing: [:]), "ac.how.to.open.an.account")
        let collision = KeyGenerator.key(prefix: "ac", english: "Open!", existing: ["ac.open": "Open?"])
        XCTAssertNotEqual(collision, "ac.open")
        XCTAssertEqual(collision, KeyGenerator.key(prefix: "ac", english: "Open!", existing: ["ac.open": "Open?"]))
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: "👋", existing: [:]), "ac.text")
    }
    func testGeneratedKeysUseAtMostFiveWordsAfterPrefix() {
        let english = "How to open an account with our bank"
        let base = "ac.how.to.open.an.account"
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: english, existing: [:]), base)
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: "Open account", existing: [:]), "ac.open.account")
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: "How, to OPEN an account! Today", existing: [:]), base)
        let existing = [base: "How to open an account for children"]
        let collision = KeyGenerator.key(prefix: "ac", english: english, existing: existing)
        XCTAssertNotEqual(collision, base)
        XCTAssertEqual(collision.split(separator: ".").count, 6)
        XCTAssertEqual(KeyGenerator.key(prefix: "ac", english: english, existing: existing.merging([collision: english]) { _, new in new }), collision)
        let occupied = existing.merging([collision: "Different text"]) { _, new in new }
        let next = KeyGenerator.key(prefix: "ac", english: english, existing: occupied)
        XCTAssertNotEqual(next, collision)
        XCTAssertEqual(next.split(separator: ".").count, 6)
    }
    func testSafeConversionExclusionsAndIdempotency() throws {
        let source = try write("Screen.swift", #"""
        import SwiftUI
        struct Screen: View {
            var name = "Developer"
            var body: some View {
                VStack {
                    Text("How to Open an account")
                    Label("Continue", systemImage: "arrow.right")
                    Image("hero")
                    Text(verbatim: "Internal")
                    Text("Hello \(name)")
                    Text("Hello " + name)
                }
            }
        }
        """#)
        let resource = try catalog(); let module = module(source: source, resource: resource); let options = [module.id: ModuleOptions(module: module)]
        let result = try Analyzer.analyze(modules: [module], allModules: [module], options: options)
        XCTAssertEqual(result.findings.filter { $0.status == .ready }.map(\.english), ["How to Open an account", "Continue"])
        XCTAssertEqual(result.findings.first { $0.english == "hero" }?.status, .excluded)
        XCTAssertEqual(result.findings.first { $0.english == "arrow.right" }?.status, .excluded)
        XCTAssertEqual(result.findings.first { $0.english == "Internal" }?.status, .excluded)
        XCTAssertEqual(result.findings.filter { $0.status == .dynamic }.count, 1)
        let plan = try Planner.registration(root: root, findings: result.findings, snapshots: result.snapshots, options: options, modules: [module])
        try Transactions.apply(plan)
        XCTAssertTrue(try String(contentsOf: source, encoding: .utf8).contains("NSLocalizedString(\"ac.how.to.open.an.account\""))
        XCTAssertEqual(try LocalizationResource(url: resource).english["ac.how.to.open.an.account"], "How to Open an account")
        let again = try Analyzer.analyze(modules: [module], allModules: [module], options: options)
        XCTAssertEqual(again.findings.filter { $0.status == .ready }.count, 0)
        try Transactions.undo(root: root)
        XCTAssertEqual(try Data(contentsOf: source), result.snapshots[source])
        XCTAssertEqual(try Data(contentsOf: resource), result.snapshots[resource])
    }
    func testSharedSourceCannotBeAutomaticallyConverted() throws {
        let source = try write("Screen.swift", "import SwiftUI\nlet title = Text(\"Hello\")")
        let resource = try catalog(); let first = module(source: source, resource: resource)
        let second = Module(name: "Other", root: root, kind: "Application", sources: [source], resources: [resource])
        let result = try Analyzer.analyze(modules: [first], allModules: [first, second], options: [first.id: ModuleOptions(module: first)])
        XCTAssertEqual(result.findings.first?.status, .review)
    }
    func testCatalogMigrationPreservesUnknownFieldsAndTranslations() throws {
        let url = try catalog(["Hello": ["comment": "Greeting", "custom": ["keep": true], "localizations": ["ar": ["stringUnit": ["state": "translated", "value": "مرحباً"]]]]])
        var resource = try LocalizationResource(url: url); try resource.register(key: "ac.hello", value: "Hello")
        let document = try JSONSerialization.jsonObject(with: resource.data()) as! [String: Any]
        let strings = document["strings"] as! [String: [String: Any]]
        XCTAssertNotNil(strings["Hello"])
        XCTAssertNotNil(strings["ac.hello"]?["custom"])
        XCTAssertEqual(resource.translation(key: "ac.hello", locale: "ar"), "مرحباً")
    }
    func testLegacyCommentsEscapingAndDuplicateDetection() throws {
        let url = try write("en.lproj/Localizable.strings", "/* Keep this comment */\n\"old\" = \"Old\";\n")
        var resource = try LocalizationResource(url: url); try resource.register(key: "ac.quote", value: "Say \"hello\"\nمساء الخير")
        let data = try resource.data(); let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("/* Keep this comment */"))
        XCTAssertEqual(try LocalizationResource.parseLegacy(text)["ac.quote"], "Say \"hello\"\nمساء الخير")
        XCTAssertThrowsError(try LocalizationResource.parseLegacy("\"a\"=\"One\"; \"a\"=\"Two\";"))
        XCTAssertThrowsError(try LocalizationResource.parseLegacy("\"a\"=\"One\""))
    }
    func testLegacyUTF16Preserved() throws {
        let url = root.appendingPathComponent("Localizable.strings")
        try "\"a\" = \"Value\";".data(using: .utf16)!.write(to: url)
        var resource = try LocalizationResource(url: url); try resource.register(key: "b", value: "More")
        let data = try resource.data(); XCTAssertTrue(data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]))
        XCTAssertNotNil(String(data: data, encoding: .utf16))
    }
    func testTransactionRejectsStaleSourceWithoutPartialWrites() throws {
        let a = try write("a.swift", "before"), b = try write("b.swift", "before")
        let plan = ChangePlan(title: "Test", root: root, changes: [FileChange(url: a, before: Data("before".utf8), after: Data("after".utf8), reason: "test"), FileChange(url: b, before: Data("before".utf8), after: Data("after".utf8), reason: "test")], rows: [])
        try Data("user edit".utf8).write(to: b)
        XCTAssertThrowsError(try Transactions.apply(plan))
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "before")
    }
    func testUndoPreservesSubsequentChanges() throws {
        let a = try write("a.swift", "before")
        let plan = ChangePlan(title: "Test", root: root, changes: [FileChange(url: a, before: Data("before".utf8), after: Data("after".utf8), reason: "test")], rows: [])
        try Transactions.apply(plan); try Data("user edit".utf8).write(to: a)
        XCTAssertThrowsError(try Transactions.undo(root: root))
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "user edit")
    }
    func testFormatValidation() {
        XCTAssertTrue(FormatValidation.compatible("Hello %@, %d", "%2$d، %1$@"))
        XCTAssertFalse(FormatValidation.compatible("Hello %@", "مرحباً"))
        XCTAssertFalse(FormatValidation.compatible("%lld", "%d"))
        XCTAssertTrue(FormatValidation.compatible("100%%", "١٠٠%%"))
        XCTAssertFalse(FormatValidation.compatible("%*d", "%d"))
    }
    func testExactMatchingAndAmbiguity() {
        let one = RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Open")])
        let two = RemoteKey(key_id: 2, translations: [RemoteTranslation(language_iso: "en", translation: "Open")])
        let index = TranslationIndex(keys: [one, two], englishLocale: "en")
        XCTAssertNil(index.match("Open").key)
        XCTAssertEqual(index.match("Open").candidates.count, 2)
        XCTAssertEqual(index.match("Open", preferredID: 2).key?.id, 2)
        XCTAssertNil(index.match("open").key)
        XCTAssertNil(index.match("Open ").key)
        XCTAssertEqual(index.match("Open ").candidates.count, 2)
    }
    func testImportArabicHindiAndMissingValues() throws {
        let source = try write("Screen.swift", "import SwiftUI")
        let url = try catalog(["ac.open": ["localizations": ["en": ["stringUnit": ["state": "translated", "value": "Open"]]]], "ac.missing": ["localizations": ["en": ["stringUnit": ["state": "translated", "value": "Missing"]]]]])
        let module = module(source: source, resource: url)
        let keys = [RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Open"), RemoteTranslation(language_iso: "ar", translation: "افتح"), RemoteTranslation(language_iso: "hi", translation: "खोलें")])]
        var options = ImportOptions(); options.languages = ["ar": "ar", "hi": "hi"]
        let plan = try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: keys, options: options)
        XCTAssertEqual(plan.rows.filter { $0.status == "Imported" }.count, 2)
        XCTAssertEqual(plan.rows.filter { $0.status == "Not found" }.count, 2)
        try Transactions.apply(plan)
        let resource = try LocalizationResource(url: url)
        XCTAssertEqual(resource.translation(key: "ac.open", locale: "ar"), "افتح")
        XCTAssertEqual(resource.translation(key: "ac.open", locale: "hi"), "खोलें")
        let repeatPlan = try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: keys, options: options)
        XCTAssertTrue(repeatPlan.changes.isEmpty)
    }
    func testConflictingTranslationsArePreserved() throws {
        let source = try write("Screen.swift", "import SwiftUI")
        let url = try catalog(["ac.open": ["localizations": ["en": ["stringUnit": ["state": "translated", "value": "Open"]], "ar": ["stringUnit": ["state": "translated", "value": "Existing"]]]]])
        let module = module(source: source, resource: url)
        let keys = [RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Open"), RemoteTranslation(language_iso: "ar", translation: "افتح")])]
        let plan = try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: keys, options: ImportOptions())
        XCTAssertTrue(plan.changes.isEmpty); XCTAssertEqual(plan.rows.first?.status, "Conflict")
    }
    func testReportCSVPreventsFormulaInjection() {
        let row = ReportRow(module: "Test", key: "key", english: "=HYPERLINK(\"bad\")", status: "Missing")
        XCTAssertTrue(ReportExporter.csv([row]).contains("'=HYPERLINK"))
    }
    func testPackageDiscoveryDoesNotExecuteManifest() throws {
        _ = try write("Package.swift", #"""
        import PackageDescription
        let package = Package(name: "Demo", targets: [.target(name: "AccountCenter", resources: [.process("Resources")]), .target(name: "Other", path: "Modules/Other")])
        """#)
        _ = try write("Sources/AccountCenter/Screen.swift", "import SwiftUI")
        _ = try write("Modules/Other/Screen.swift", "import SwiftUI")
        let modules = try Discovery.discover(root: root)
        XCTAssertEqual(Set(modules.map(\.name)), ["AccountCenter", "Other"])
        XCTAssertEqual(modules.first { $0.name == "AccountCenter" }?.sources.count, 1)
    }
}

extension CoreTests {
    func testLegacyReplacementRetainsCommentsAndOtherEntries() throws {
        let url = try write("Localizable.strings", "/* context */\n\"a\" = \"old\"; // preserve\n\"b\" = \"keep\";\n")
        var resource = try LocalizationResource(url: url)
        try resource.replaceLegacy(key: "a", value: "جديد")
        let text = String(data: try resource.data(), encoding: .utf8)!
        XCTAssertTrue(text.contains("/* context */")); XCTAssertTrue(text.contains("// preserve")); XCTAssertTrue(text.contains("\"b\" = \"keep\";"))
        XCTAssertEqual(try LocalizationResource.parseLegacy(text)["a"], "جديد")
    }
    func testCatalogDoNotTranslateIsRespected() throws {
        let source = try write("Screen.swift", "import SwiftUI")
        let url = try catalog(["Brand": ["shouldTranslate": false]])
        let module = module(source: source, resource: url)
        let remote = [RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Brand"), RemoteTranslation(language_iso: "ar", translation: "اسم")])]
        let plan = try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: remote, options: ImportOptions())
        XCTAssertTrue(plan.changes.isEmpty)
        XCTAssertEqual(plan.rows.first?.status, "Preserved")
    }
    func testAnalysisPerformanceOnLargeFixture() throws {
        let resource = try catalog()
        var sources: [URL] = []
        for index in 0..<500 {
            let rows = (0..<8).map { "Text(\"Message \(index) item \($0)\")" }.joined(separator: "\n")
            sources.append(try write("Module/Screen\(index).swift", "import SwiftUI\nstruct Screen\(index): View { var body: some View { VStack {\n\(rows)\n} } }"))
        }
        let module = Module(name: "Large Fixture", root: root, kind: "Application", sources: sources, resources: [resource])
        let start = Date()
        let result = try Analyzer.analyze(modules: [module], allModules: [module], options: [module.id: ModuleOptions(module: module)])
        XCTAssertEqual(result.findings.filter { $0.status == .ready }.count, 4000)
        print("LOCALIZE_BENCHMARK: 500 files / 4000 UI strings in \(Date().timeIntervalSince(start)) seconds")
    }
}
extension CoreTests {
    func testWrongTableIsNotReportedAsLocalized() throws {
        let source = try write("Screen.swift", "import SwiftUI\nlet title = Text(\"ac.open\", tableName: \"Other\")")
        let url = try catalog(["ac.open": ["localizations": ["en": ["stringUnit": ["value": "Open", "state": "translated"]]]]])
        let module = module(source: source, resource: url)
        let result = try Analyzer.analyze(modules: [module], allModules: [module], options: [module.id: ModuleOptions(module: module)])
        XCTAssertEqual(result.findings.first { $0.english == "ac.open" }?.status, .review)
        XCTAssertEqual(result.findings.first { $0.english == "Other" }?.status, .excluded)
    }
    func testExplicitSwiftUITextLookupRetainsItsInitializer() throws {
        let source = try write("Screen.swift", "import SwiftUI\nlet title = Text(\"Open\", tableName: \"Localizable\", bundle: .main)")
        let url = try catalog(); let module = module(source: source, resource: url); let options = [module.id: ModuleOptions(module: module)]
        let result = try Analyzer.analyze(modules: [module], allModules: [module], options: options)
        let plan = try Planner.registration(root: root, findings: result.findings, snapshots: result.snapshots, options: options, modules: [module])
        let text = plan.changes.first { $0.url == source }!.afterText
        XCTAssertTrue(text.contains("Text(\"ac.open\", tableName: \"Localizable\", bundle: .main)"))
    }
}
extension CoreTests {
    func testAppleLocaleAliasesAreCanonicalized() {
        XCTAssertEqual(LanguageMapping.appleLocale(for: "tl"), "fil")
        XCTAssertEqual(LanguageMapping.appleLocale(for: "en_US"), "en-US")
        XCTAssertEqual(LanguageMapping.appleLocale(for: "ar"), "ar")
        XCTAssertEqual(LanguageMapping.appleLocale(for: "hi"), "hi")
    }
    func testImportRejectsNoncanonicalAppleLocale() throws {
        let source = try write("Screen.swift", "import SwiftUI")
        let url = try catalog(["ac.open": ["localizations": ["en": ["stringUnit": ["value": "Open", "state": "translated"]]]]])
        let module = module(source: source, resource: url)
        let keys = [RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Open"), RemoteTranslation(language_iso: "tl", translation: "Buksan")])]
        var options = ImportOptions(); options.languages = ["tl": "tl"]
        XCTAssertThrowsError(try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: keys, options: options))
        options.languages = ["tl": "fil"]
        let plan = try ImportPlanner.plan(root: root, module: module, config: ModuleOptions(module: module), remote: keys, options: options)
        XCTAssertEqual(plan.rows.first?.language, "fil")
        XCTAssertEqual(plan.rows.first?.status, "Imported")
    }
}
