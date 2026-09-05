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
        try validateDirectory(root)
        for folder in [root.appendingPathComponent(".lokanow"), dir] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        let fd = open(dir.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw StudioError.message("Could not open the project operation lock.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
            throw StudioError.message("The project operation lock is not a regular file owned by this user.")
        }
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
                    try validatePath(change.url, root: plan.root)
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
            try validatePath(change.url, root: plan.root)
            let actual = try read(change.url)
            guard actual == change.before || actual == change.after else { throw StudioError.message("Recovery stopped to preserve subsequent edits to \(change.url.lastPathComponent).") }
        }
        for change in plan.changes.reversed() {
            try validatePath(change.url, root: plan.root)
            let actual = try read(change.url)
            guard actual == change.before || actual == change.after else { throw StudioError.message("Recovery stopped to preserve subsequent edits to \(change.url.lastPathComponent).") }
            if let before = change.before { try before.write(to: change.url, options: .atomic) }
            else if FileManager.default.fileExists(atPath: change.url.path) { try FileManager.default.removeItem(at: change.url) }
        }
    }
    private static func validatePath(_ url: URL, root: URL) throws {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let protected = [".git", ".lokanow"]
        guard url.isFileURL, root.isFileURL, inside(url, root: root), resolved.path != base.path,
              !url.standardizedFileURL.pathComponents.contains(where: { protected.contains($0.lowercased()) }),
              !resolved.pathComponents.contains(where: { protected.contains($0.lowercased()) }) else {
            throw StudioError.message("Unsafe destination outside project resources or inside protected metadata: \(url.lastPathComponent)")
        }
        try rejectLinks(url, root: root)
        if let attributes = try attributesIfPresent(url) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw StudioError.message("Destination is not a regular file: \(url.lastPathComponent)") }
            guard FileManager.default.isWritableFile(atPath: url.path) else { throw StudioError.message("Read-only file: \(url.lastPathComponent)") }
        }
    }
    private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }
    private static func rejectLinks(_ url: URL, root: URL) throws {
        let base = root.standardizedFileURL
        var current = url.standardizedFileURL
        guard current.path.hasPrefix(base.path + "/") else { throw StudioError.message("Destination must be a child of the selected project.") }
        while current.path != base.path {
            if let attributes = try attributesIfPresent(current), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw StudioError.message("Symbolic links are not allowed in operation paths: \(current.lastPathComponent)")
            }
            current.deleteLastPathComponent()
        }
    }
    private static func validateDirectory(_ root: URL) throws {
        let dir = directory(root)
        guard inside(dir, root: root) else { throw StudioError.message("The operation backup directory resolves outside the selected project.") }
        try rejectLinks(dir, root: root)
    }
    private static func read(_ url: URL) throws -> Data? { try FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil }
    private static func verify(_ url: URL, expected: Data?) throws {
        guard try read(url) == expected else { throw StudioError.message("\(url.lastPathComponent) changed since the preview. Reanalyze before applying.") }
    }
    // Keep trust records outside the selected repository. Repository contents cannot authorize recovery.
    private static func receiptURL(_ url: URL) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Lokanow/JournalReceipts", isDirectory: true)
            .appendingPathComponent(stableID(url.resolvingSymlinksInPath().standardizedFileURL.path) + ".sha256")
    }
    static func save(_ journal: Journal, to url: URL) throws {
        let data = try JSONEncoder().encode(journal)
        let receipt = receiptURL(url)
        let folder = receipt.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        // Receipt first: a crash between writes fails closed and leaves the backup for manual review.
        try Data(digest(data).utf8).write(to: receipt, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static func journals(_ root: URL) throws -> [(URL, Journal)] {
        try validateDirectory(root)
        let dir = directory(root)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { url in
            guard try attributesIfPresent(url)?[.type] as? FileAttributeType == .typeRegular else { throw StudioError.message("Recovery journals must be regular files.") }
            let data = try Data(contentsOf: url)
            guard let receipt = try? Data(contentsOf: receiptURL(url)), receipt == Data(digest(data).utf8) else {
                throw StudioError.message("This operation backup is unverified or changed. Automatic undo and recovery are blocked. Review .lokanow/operations manually; existing backups have been preserved.")
            }
            let journal = try JSONDecoder().decode(Journal.self, from: data)
            guard journal.plan.root.resolvingSymlinksInPath().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else { throw StudioError.message("A recovery journal belongs to a different project. Review its backups manually.") }
            for change in journal.plan.changes { try validatePath(change.url, root: root) }
            return (url, journal)
        }
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
