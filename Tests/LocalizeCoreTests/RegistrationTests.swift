import XCTest
@testable import LocalizeCore
final class RegistrationTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws { root = FileManager.default.temporaryDirectory.appendingPathComponent("Registration-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testNewPackageResourcesPreserveArgumentOrder() throws {
        let manifest = root.appendingPathComponent("Package.swift")
        let original = Data(#"let package = Package(name: "Demo", targets: [.target(name: "Demo", swiftSettings: [.define("DEBUG")])])"#.utf8)
        try original.write(to: manifest)
        let target = root.appendingPathComponent("Sources/Demo")
        let module = Module(name: "Demo", root: target, kind: "Swift Package", sources: [], resources: [], packageManifest: manifest)
        var changes: [FileChange] = []
        try ResourceRegistration.include(target.appendingPathComponent("Resources/Localizable.xcstrings"), module: module, sourceLocale: "en", changes: &changes)
        XCTAssertEqual(changes.count, 1)
        let text = changes[0].afterText
        XCTAssertTrue(text.contains("defaultLocalization: \"en\""))
        XCTAssertTrue(text.contains("resources: [.process(\"Resources/Localizable.xcstrings\")], swiftSettings"))
    }
    func testPackageResourceCoverageIsIdempotent() throws {
        let manifest = root.appendingPathComponent("Package.swift")
        try Data(#"let package = Package(name: "Demo", defaultLocalization: "en", targets: [.target(name: "Demo", resources: [.process("Resources")])])"#.utf8).write(to: manifest)
        let target = root.appendingPathComponent("Sources/Demo")
        let module = Module(name: "Demo", root: target, kind: "Swift Package", sources: [], resources: [], packageManifest: manifest)
        var changes: [FileChange] = []
        try ResourceRegistration.include(target.appendingPathComponent("Resources/ar.lproj/Localizable.strings"), module: module, sourceLocale: "en", changes: &changes)
        XCTAssertTrue(changes.isEmpty)
    }
    func testCrashRecoveryRestoresPartialWrites() throws {
        let file = root.appendingPathComponent("File.swift")
        let before = Data("before".utf8), after = Data("after".utf8)
        try after.write(to: file)
        let plan = ChangePlan(title: "Interrupted", root: root, changes: [FileChange(url: file, before: before, after: after, reason: "test")], rows: [])
        let dir = root.appendingPathComponent(".lokanow/operations")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(Transactions.Journal(plan: plan, state: "applying")).write(to: dir.appendingPathComponent(plan.id.uuidString + ".json"))
        XCTAssertNotNil(try Transactions.pending(root: root))
        try Transactions.recover(root: root)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertNil(try Transactions.pending(root: root))
    }
    func testSymlinkEscapingRootIsRejected() throws {
        let external = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("safe".utf8).write(to: external); defer { try? FileManager.default.removeItem(at: external) }
        let link = root.appendingPathComponent("linked.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let plan = ChangePlan(title: "Bad path", root: root, changes: [FileChange(url: link, before: Data("safe".utf8), after: Data("bad".utf8), reason: "test")], rows: [])
        XCTAssertThrowsError(try Transactions.apply(plan))
        XCTAssertEqual(try Data(contentsOf: external), Data("safe".utf8))
    }
}
final class FixtureIntegrationTests: XCTestCase {
    func testXcodeAndPackageFixturesBuildAfterConversion() throws {
        guard ProcessInfo.processInfo.environment["LOCALIZE_INTEGRATION"] == "1" else { throw XCTSkip("Set LOCALIZE_INTEGRATION=1 for Xcode and package build verification.") }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("LocalizeIntegration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let showcase = temp.appendingPathComponent("Showcase")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Fixtures/Showcase"), to: showcase)
        try run("/opt/homebrew/bin/xcodegen", ["generate"], at: showcase)
        let modules = try Discovery.discover(root: showcase)
        XCTAssertEqual(modules.count, 3)
        var configs: [String: ModuleOptions] = [:]
        for module in modules {
            var option = ModuleOptions(module: module)
            if module.kind == "Framework" { option.bundleExpression = "Bundle(for: LocalizationBundleToken.self)"; option.bundleConfirmed = true }
            configs[module.id] = option
        }
        let analysis = try Analyzer.analyze(modules: modules, allModules: modules, options: configs)
        XCTAssertGreaterThanOrEqual(analysis.findings.filter { $0.status == .ready }.count, 5)
        let registration = try Planner.registration(root: showcase, findings: analysis.findings, snapshots: analysis.snapshots, options: configs, modules: modules)
        try Transactions.apply(registration)
        let refreshed = try Discovery.discover(root: showcase)
        XCTAssertTrue(refreshed.allSatisfy { !$0.resources.isEmpty })
        for module in refreshed {
            let config = configs[module.id]!
            let values = try LocalizationResource(url: URL(fileURLWithPath: config.resourcePath)).english
            let keys = values.sorted { $0.key < $1.key }.enumerated().map { i, pair in RemoteKey(key_id: i + 1, translations: [RemoteTranslation(language_iso: "en", translation: pair.value), RemoteTranslation(language_iso: "ar", translation: "ترجمة"), RemoteTranslation(language_iso: "hi", translation: "अनुवाद")]) }
            var options = ImportOptions(); options.languages = ["ar": "ar", "hi": "hi"]
            let imported = try ImportPlanner.plan(root: showcase, module: module, config: config, remote: keys, options: options)
            try Transactions.apply(imported)
        }
        try run("/usr/bin/xcodebuild", ["-project", "LocalizationShowcase.xcodeproj", "-scheme", "DemoApp", "-sdk", "iphonesimulator", "-configuration", "Debug", "-derivedDataPath", temp.appendingPathComponent("DerivedData").path, "CODE_SIGNING_ALLOWED=NO", "build"], at: showcase)
        let package = temp.appendingPathComponent("PackageDemo")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("Fixtures/PackageDemo"), to: package)
        let packages = try Discovery.discover(root: package)
        let module = try XCTUnwrap(packages.first)
        let config = ModuleOptions(module: module)
        let scan = try Analyzer.analyze(modules: packages, allModules: packages, options: [module.id: config])
        try Transactions.apply(Planner.registration(root: package, findings: scan.findings, snapshots: scan.snapshots, options: [module.id: config], modules: packages))
        let remote = [RemoteKey(key_id: 1, translations: [RemoteTranslation(language_iso: "en", translation: "Confirm order"), RemoteTranslation(language_iso: "ar", translation: "تأكيد الطلب")])]
        try Transactions.apply(ImportPlanner.plan(root: package, module: module, config: config, remote: remote, options: ImportOptions()))
        let runtimeTest = package.appendingPathComponent("Tests/CheckoutTests/ArabicTests.swift")
        try Data("import XCTest\n@testable import Checkout\nfinal class ArabicTests: XCTestCase { func testArabic() { XCTAssertEqual(CheckoutLocalization.value(\"chec.confirm.order\", locale: \"ar\"), \"تأكيد الطلب\") } }".utf8).write(to: runtimeTest)
        try run("/usr/bin/swift", ["test", "--disable-sandbox"], at: package)
    }
    private func run(_ executable: String, _ args: [String], at url: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; process.currentDirectoryURL = url
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("localize-fixture-\(URL(fileURLWithPath: executable).lastPathComponent).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
        process.standardOutput = log; process.standardError = log; try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Fixture command failed. See \(logURL.path)")
        if process.terminationStatus != 0 { throw StudioError.message("Fixture build failed. See \(logURL.path)") }
    }
}
