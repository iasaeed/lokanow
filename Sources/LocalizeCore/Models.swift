import Foundation
import CryptoKit

public enum StudioError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
public func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
public func stableID(_ value: String) -> String { digest(Data(value.utf8)) }
public func relativePath(_ url: URL, root: URL) -> String {
    let path = url.standardizedFileURL.path, base = root.standardizedFileURL.path + "/"
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
}
public func inside(_ url: URL, root: URL) -> Bool {
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    let base = root.resolvingSymlinksInPath().standardizedFileURL.path
    return path == base || path.hasPrefix(base + "/")
}
public struct Module: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var root: URL
    public var kind: String
    public var sources: [URL]
    public var resources: [URL]
    public var warnings: [String]
    public var projectFile: URL?
    public var targetID: String?
    public var synchronizedRoot: URL?
    public var packageManifest: URL?
    public init(name: String, root: URL, kind: String, sources: [URL], resources: [URL], warnings: [String] = [], projectFile: URL? = nil, targetID: String? = nil, synchronizedRoot: URL? = nil, packageManifest: URL? = nil) {
        self.id = stableID((projectFile?.path ?? root.path) + ":" + (targetID ?? name)); self.name = name; self.root = root; self.kind = kind
        self.sources = sources; self.resources = resources; self.warnings = warnings; self.projectFile = projectFile; self.targetID = targetID; self.synchronizedRoot = synchronizedRoot
        self.packageManifest = packageManifest
    }
}
public struct ModuleOptions: Codable, Hashable, Sendable {
    public var prefix: String
    public var resourcePath: String
    public var bundleExpression: String
    public var bundleConfirmed: Bool
    public var sourceLocale: String
    public var remoteProject: String
    public var remoteBranch: String
    public var replacementTemplate: String? = nil
    public init(module: Module) {
        prefix = KeyGenerator.prefix(module.name)
        let english = module.resources.filter { $0.pathExtension == "xcstrings" || $0.deletingLastPathComponent().lastPathComponent == "en.lproj" }
        resourcePath = english.count == 1 ? english[0].path : (module.resources.isEmpty ? module.root.appendingPathComponent(module.kind == "Swift Package" ? "Resources/Localizable.xcstrings" : "Localizable.xcstrings").path : "")
        bundleExpression = module.kind == "Swift Package" ? ".module" : ".main"
        bundleConfirmed = module.kind == "Application" || module.kind == "Swift Package"
        sourceLocale = "en"; remoteProject = ""; remoteBranch = ""
    }
}
public enum FindingStatus: String, Codable, CaseIterable, Sendable {
    case ready = "Ready to register", localized = "Already localized", review = "Needs review", excluded = "Excluded", dynamic = "Dynamic / interpolated"
}
public struct Finding: Identifiable, Codable, Sendable {
    public var id: String
    public var moduleID: String
    public var moduleName: String
    public var file: URL
    public var line: Int
    public var offset: Int
    public var length: Int
    public var literal: String
    public var english: String
    public var key: String
    public var status: FindingStatus
    public var reason: String
    public var context: String
    public var replacement: String?
    public var resource: URL?
    public var selected: Bool
    public var sourceForms: [String]? = nil
}
public struct Analysis: Sendable {
    public var findings: [Finding]
    public var snapshots: [URL: Data]
    public var warnings: [String]
    public var files: Int
}
public struct FileChange: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var before: Data?
    public var after: Data
    public var reason: String
    public var beforeText: String { before.flatMap { String(data: $0, encoding: .utf8) } ?? "(new file or non-UTF-8 content)" }
    public var afterText: String { String(data: after, encoding: .utf8) ?? "(non-UTF-8 content)" }
    public init(url: URL, before: Data?, after: Data, reason: String) { self.url = url; self.before = before; self.after = after; self.reason = reason }
}
public struct ChangePlan: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var root: URL
    public var changes: [FileChange]
    public var rows: [ReportRow]
    public var createdAt = Date()
    public init(title: String, root: URL, changes: [FileChange], rows: [ReportRow]) { self.title = title; self.root = root; self.changes = changes; self.rows = rows }
}
public struct ReportRow: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var module: String
    public var key: String
    public var english: String
    public var language: String
    public var status: String
    public var reason: String
    public var source: String
    public var destination: String
    public var remoteKeyID: Int?
    public init(module: String, key: String, english: String, language: String = "en", status: String, reason: String = "", source: String = "", destination: String = "", remoteKeyID: Int? = nil) {
        self.module = module; self.key = key; self.english = english; self.language = language; self.status = status; self.reason = reason; self.source = source; self.destination = destination; self.remoteKeyID = remoteKeyID
    }
    public var unresolved: Bool { !["Registered", "Imported", "Preserved", "Already localized"].contains(status) }
}
public struct OperationReport: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var title: String
    public var rows: [ReportRow]
    public init(title: String, rows: [ReportRow]) { self.title = title; self.rows = rows }
}
public enum KeyGenerator {
    public static func words(_ text: String) -> [String] {
        let split = text.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
        return split.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    public static func prefix(_ name: String) -> String {
        let parts = words(name)
        return parts.count > 1 ? parts.compactMap(\.first).map(String.init).joined() : String((parts.first ?? "app").prefix(4))
    }
    public static func key(prefix: String, english: String, existing: [String: String]) -> String {
        let slug = words(english).prefix(5).joined(separator: ".")
        let base = prefix + "." + (slug.isEmpty ? "text" : String(slug.prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        if let value = existing[base], value != english {
            // Keep disambiguation within the final component, never a sixth word.
            let disambiguated = base + "_" + String(stableID(english).prefix(12))
            var candidate = disambiguated
            var counter = 2
            while let value = existing[candidate], value != english {
                candidate = disambiguated + "_" + String(counter)
                counter += 1
            }
            return candidate
        }
        return base
    }
    public static func validPrefix(_ prefix: String) -> Bool { prefix.range(of: "^[a-z][a-z0-9]*$", options: .regularExpression) != nil }
    public static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
