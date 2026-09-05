import Foundation
import Darwin

public enum Transactions {
    struct Journal: Codable {
        var plan: ChangePlan
        var state: String
    }
    private static func directory(_ root: URL) -> URL { root.appendingPathComponent(".lokanow/operations", isDirectory: true) }
    private static func locked<T>(_ root: URL, _ action: () throws -> T) throws -> T {
        let dir = directory(root)
        guard inside(dir, root: root) else { throw StudioError.message("The operation backup directory resolves outside the selected project.") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.appendingPathComponent("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StudioError.message("Could not open the project operation lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StudioError.message("Another Lokanow operation is modifying this project.") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    public static func apply(_ plan: ChangePlan) throws {
        try locked(plan.root) {
            if try pending(root: plan.root) != nil { throw StudioError.message("An interrupted operation needs recovery before applying new changes.") }
            for change in plan.changes { try validatePath(change.url, root: plan.root); try verify(change.url, expected: change.before) }
            let journalURL = directory(plan.root).appendingPathComponent(plan.id.uuidString + ".json")
            var journal = Journal(plan: plan, state: "applying")
            try save(journal, to: journalURL)
            do {
                // Do not observe cancellation inside this short, recoverable transaction.
                for change in plan.changes {
                    try verify(change.url, expected: change.before)
                    try FileManager.default.createDirectory(at: change.url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try change.after.write(to: change.url, options: .atomic)
                }
                for change in plan.changes { try verify(change.url, expected: change.after) }
                journal.state = "applied"; try save(journal, to: journalURL)
            } catch {
                do { try restore(plan); journal.state = "rolledBack"; try save(journal, to: journalURL) }
                catch { throw StudioError.message("The operation was interrupted and recovery needs review. Backups are in .lokanow/operations. \(error.localizedDescription)") }
                throw error
            }
        }
    }
    public static func undo(root: URL) throws {
        try locked(root) {
            let entries = try journals(root).filter { $0.1.state == "applied" }.sorted { $0.1.plan.createdAt > $1.1.plan.createdAt }
            guard let (url, item) = entries.first else { throw StudioError.message("No applied operation is available to undo.") }
            for change in item.plan.changes { try validatePath(change.url, root: root); try verify(change.url, expected: change.after) }
            var journal = item; journal.state = "undoing"; try save(journal, to: url)
            try restore(item.plan); journal.state = "undone"; try save(journal, to: url)
        }
    }
    public static func pending(root: URL) throws -> UUID? { try journals(root).first { ["applying", "undoing"].contains($0.1.state) }?.1.plan.id }
    public static func recover(root: URL) throws {
        try locked(root) {
            for (url, item) in try journals(root) where ["applying", "undoing"].contains(item.state) {
                for change in item.plan.changes { try validatePath(change.url, root: root) }
                try restore(item.plan)
                var journal = item; journal.state = "rolledBack"; try save(journal, to: url)
            }
        }
    }
    private static func restore(_ plan: ChangePlan) throws {
        // Preflight ALL files before touching any of them. Preserve edits made after the interrupted write.
        for change in plan.changes {
            let actual = try read(change.url)
            guard actual == change.before || actual == change.after else { throw StudioError.message("Recovery stopped to preserve subsequent edits to \(change.url.lastPathComponent).") }
        }
        for change in plan.changes.reversed() {
            if let before = change.before { try before.write(to: change.url, options: .atomic) }
            else if FileManager.default.fileExists(atPath: change.url.path) { try FileManager.default.removeItem(at: change.url) }
        }
    }
    private static func validatePath(_ url: URL, root: URL) throws {
        guard inside(url, root: root), !url.path.contains("/.git/") else { throw StudioError.message("Unsafe destination outside project resources: \(url.lastPathComponent)") }
        if FileManager.default.fileExists(atPath: url.path), !FileManager.default.isWritableFile(atPath: url.path) { throw StudioError.message("Read-only file: \(url.lastPathComponent)") }
    }
    private static func read(_ url: URL) throws -> Data? { try FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil }
    private static func verify(_ url: URL, expected: Data?) throws {
        guard try read(url) == expected else { throw StudioError.message("\(url.lastPathComponent) changed since the preview. Reanalyze before applying.") }
    }
    private static func save(_ journal: Journal, to url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func journals(_ root: URL) throws -> [(URL, Journal)] {
        let dir = directory(root)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { ($0, try JSONDecoder().decode(Journal.self, from: Data(contentsOf: $0))) }
    }
}
public enum ReportExporter {
    public static func markdown(_ rows: [ReportRow]) -> String {
        rows.map { "Module: \($0.module)\nKey: \($0.key)\nEnglish: \($0.english)\nLanguage: \($0.language)\nStatus: \($0.status)\nReason: \($0.reason)\nSource: \($0.source)" }.joined(separator: "\n\n---\n\n")
    }
    public static func csv(_ rows: [ReportRow]) -> String {
        func cell(_ value: String) -> String {
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let safe = first.map { "=+-@".contains($0) } == true || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return (["Module,Key,English,Language,Status,Reason,Source,Destination,Remote Key ID"] + rows.map { [$0.module, $0.key, $0.english, $0.language, $0.status, $0.reason, $0.source, $0.destination, $0.remoteKeyID.map(String.init) ?? ""].map(cell).joined(separator: ",") }).joined(separator: "\r\n")
    }
}
