import Foundation

public struct CachedKeys: Codable, Sendable {
    public var date: Date
    public var keys: [RemoteKey]
    public init(date: Date, keys: [RemoteKey]) { self.date = date; self.keys = keys }
}

/// One complete snapshot per credential and project/branch. Failed refreshes leave it intact.
public actor TranslationCache {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func url(token: String, project: String) -> URL {
        directory.appendingPathComponent("cache-" + stableID(stableID(token) + ":" + project) + ".json")
    }
    public func load(token: String, project: String) throws -> CachedKeys? {
        let path = url(token: token, project: project)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(CachedKeys.self, from: Data(contentsOf: path))
    }
    @discardableResult public func refresh(client: LokaliseClient, token: String, project: String, progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> CachedKeys {
        let keys = try await client.keys(project: project, progress: progress)
        try Task.checkCancellation()
        let snapshot = CachedKeys(date: Date(), keys: keys)
        let data = try JSONEncoder().encode(snapshot)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = url(token: token, project: project)
        // Atomic replacement prevents half-downloaded snapshots being used by an import.
        try data.write(to: path, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return snapshot
    }
}
