import XCTest
@testable import LocalizeCore

final class DiscoveryScaleTests: XCTestCase {
    func testTenThousandFilesAcrossOneHundredModules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiscoveryScale-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var targets: [String] = []
        for module in 0..<100 {
            let name = "Feature\(module)"
            let directory = root.appendingPathComponent("Sources/" + name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            targets.append(".target(name: \"\(name)\")")
            for file in 0..<100 { try Data().write(to: directory.appendingPathComponent("File\(file).swift")) }
        }
        try Data(("import PackageDescription\nlet package = Package(name: \"Scale\", targets: [" + targets.joined(separator: ",") + "])\n").utf8).write(to: root.appendingPathComponent("Package.swift"))
        let start = Date()
        let modules = try Discovery.discover(root: root)
        print("DISCOVERY_SCALE_SECONDS: \(Date().timeIntervalSince(start))")
        XCTAssertEqual(modules.count, 100)
        XCTAssertTrue(modules.allSatisfy { $0.sources.count == 100 })
        XCTAssertEqual(Set(modules.flatMap(\.sources)).count, 10_000)
        XCTAssertTrue(modules.allSatisfy { module in module.sources.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == module.name } })
    }
}
