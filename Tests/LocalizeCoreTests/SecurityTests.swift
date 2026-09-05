import XCTest
import Darwin
@testable import LocalizeCore

final class SecurityTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func plan(_ url: URL, before: Data? = nil) -> ChangePlan {
        ChangePlan(title: "Test", root: root, changes: [FileChange(url: url, before: before, after: Data("replacement".utf8), reason: "Test")], rows: [])
    }
    func testRejectsGitFileAndAliasedMetadata() throws {
        let git = root.appendingPathComponent(".git")
        try Data("gitdir: elsewhere".utf8).write(to: git)
        XCTAssertThrowsError(try Transactions.apply(plan(git, before: Data("gitdir: elsewhere".utf8))))
        try FileManager.default.removeItem(at: git)
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let config = git.appendingPathComponent("config")
        let original = Data("original".utf8); try original.write(to: config)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: git)
        XCTAssertThrowsError(try Transactions.apply(plan(alias.appendingPathComponent("config"), before: original)))
        XCTAssertEqual(try Data(contentsOf: config), original)
    }
    func testRejectsBrokenSymlinksAndSpecialFiles() throws {
        let missing = root.appendingPathComponent("missing")
        let link = root.appendingPathComponent("link.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
        XCTAssertThrowsError(try Transactions.apply(plan(link)))
        let pipe = root.appendingPathComponent("pipe.swift")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertThrowsError(try Transactions.apply(plan(pipe)))
    }
    func testRejectsSymlinkedBackupDirectoryAndLock() throws {
        let backup = root.appendingPathComponent(".lokanow")
        let alias = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: backup, withDestinationURL: alias)
        XCTAssertThrowsError(try Transactions.pending(root: root))
        try FileManager.default.removeItem(at: backup)
        let operations = backup.appendingPathComponent("operations")
        try FileManager.default.createDirectory(at: operations, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: operations.appendingPathComponent("lock"), withDestinationURL: root.appendingPathComponent("unrelated"))
        XCTAssertThrowsError(try Transactions.apply(plan(root.appendingPathComponent("Screen.swift"))))
    }
    func testRejectsJournalForAnotherRoot() throws {
        let dir = root.appendingPathComponent(".lokanow/operations")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let foreign = ChangePlan(title: "Foreign", root: root.appendingPathComponent("Other"), changes: [], rows: [])
        let journal = Transactions.Journal(plan: foreign, state: "applying")
        try Transactions.save(journal, to: dir.appendingPathComponent("entry.json"))
        XCTAssertThrowsError(try Transactions.recover(root: root))
    }
    func testRejectsUntrustedAndTamperedRecoveryJournal() throws {
        let file = root.appendingPathComponent("Screen.swift")
        let after = Data("replacement".utf8); try after.write(to: file)
        let change = plan(file, before: Data("original".utf8))
        let dir = root.appendingPathComponent(".lokanow/operations")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(change.id.uuidString + ".json")
        let journal = Transactions.Journal(plan: change, state: "applying")
        try JSONEncoder().encode(journal).write(to: url)
        XCTAssertThrowsError(try Transactions.recover(root: root))
        try Transactions.save(journal, to: url)
        var tampered = try Data(contentsOf: url); tampered.append(Data(" ".utf8))
        try tampered.write(to: url)
        XCTAssertThrowsError(try Transactions.recover(root: root))
        XCTAssertEqual(try Data(contentsOf: file), after)
    }
    func testBackupsArePrivateAndNormalUndoWorks() throws {
        let file = root.appendingPathComponent("Screen.swift")
        let original = Data("original".utf8); try original.write(to: file)
        try Transactions.apply(plan(file, before: original))
        let dir = root.appendingPathComponent(".lokanow/operations")
        let permissions = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        try Transactions.undo(root: root)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testNetworkConfigurationDoesNotPersistCredentialsOrResponses() {
        let config = LokaliseClient.privateConfiguration()
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }
    func testPlaintextEndpointRejectedBeforeNetworkRequest() async {
        let client = LokaliseClient(token: "test-token", base: URL(string: "http://example.invalid")!)
        do { _ = try await client.projects(); XCTFail("Expected rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("HTTPS")) }
    }
}
