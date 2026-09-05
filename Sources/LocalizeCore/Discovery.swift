import Foundation
import SwiftSyntax
import SwiftParser

public enum Discovery {
    public static let defaultExclusions: Set<String> = ["Pods", "Carthage", "DerivedData", ".build", ".git", "node_modules", ".lokanow", "build", "Generated", "vendor"]
    public static func files(at root: URL, excluding: Set<String> = defaultExclusions) throws -> [URL] {
        guard FileManager.default.isReadableFile(atPath: root.path) else { throw StudioError.message("The project folder is not readable. Select it again to renew access.") }
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [], errorHandler: { _, error in failure = error; return false }) else { throw StudioError.message("Could not enumerate the project folder.") }
        var result: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if excluding.contains(url.lastPathComponent) || values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory != true { result.append(url.standardizedFileURL) }
        }
        if let failure { throw failure }
        return result.sorted { $0.path < $1.path }
    }
    public static func discover(root: URL, exclusions: Set<String> = defaultExclusions) throws -> [Module] {
        let all = try files(at: root, excluding: exclusions)
        let index = try DiscoveryFileIndex(all)
        var modules: [Module] = []
        for project in all where project.lastPathComponent == "project.pbxproj" {
            try Task.checkCancellation()
            modules += try xcodeModules(project, index: index)
        }
        for manifest in all where manifest.lastPathComponent == "Package.swift" {
            let packageRoot = manifest.deletingLastPathComponent()
            let tree = Parser.parse(source: try String(contentsOf: manifest, encoding: .utf8))
            let visitor = PackageTargets(); visitor.walk(tree)
            for target in visitor.targets {
                try Task.checkCancellation()
                let folder = packageRoot.appendingPathComponent(target.path ?? "Sources/\(target.name)")
                let contents = try index.files(in: folder)
                let warnings = target.hasResources ? [] : ["This target has no literal resources declaration. New resources require a reviewed Package.swift change."]
                modules.append(Module(name: target.name, root: folder, kind: "Swift Package", sources: contents.filter { $0.pathExtension == "swift" }, resources: contents.filter(isResource), warnings: warnings, packageManifest: manifest))
            }
        }
        if modules.isEmpty {
            let swift = all.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Package.swift" }
            guard !swift.isEmpty else { throw StudioError.message("No Swift targets were found. Select a folder containing an Xcode project or a Swift package.") }
            modules = [Module(name: root.lastPathComponent, root: root, kind: "Unresolved folder", sources: swift, resources: all.filter(isResource), warnings: ["No build target was found. Confirm bundle and resource ownership before converting strings."])]
        }
        let counts = Dictionary(grouping: modules.flatMap { $0.sources }, by: { $0 }).mapValues(\.count)
        for i in modules.indices where modules[i].sources.contains(where: { counts[$0, default: 0] > 1 }) {
            modules[i].warnings.append("Some Swift files belong to multiple targets. Shared source conversions require manual review.")
        }
        return modules.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func isResource(_ url: URL) -> Bool { ["xcstrings", "strings", "stringsdict"].contains(url.pathExtension) }
    static func xcodeModules(_ project: URL, all: [URL]) throws -> [Module] {
        try xcodeModules(project, index: DiscoveryFileIndex(all))
    }
    private static func xcodeModules(_ project: URL, index: DiscoveryFileIndex) throws -> [Module] {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: project), options: [], format: nil)
        guard let document = plist as? [String: Any], let objects = document["objects"] as? [String: [String: Any]] else { throw StudioError.message("Invalid Xcode project: \(project.path)") }
        let base = project.deletingLastPathComponent().deletingLastPathComponent()
        var paths: [String: URL] = [:]
        var visiting = Set<String>()
        func resolve(_ id: String, parent: URL) {
            guard visiting.insert(id).inserted, let object = objects[id] else { return }
            let path = object["path"] as? String ?? ""
            let tree = object["sourceTree"] as? String ?? "<group>"
            let url: URL
            if tree == "SOURCE_ROOT" { url = base.appendingPathComponent(path) }
            else if tree == "<absolute>" { url = URL(fileURLWithPath: path) }
            else { url = path.isEmpty ? parent : parent.appendingPathComponent(path) }
            paths[id] = url.standardizedFileURL
            for child in object["children"] as? [String] ?? [] { resolve(child, parent: url) }
        }
        if let main = objects[document["rootObject"] as? String ?? ""]?["mainGroup"] as? String { resolve(main, parent: base) }
        var result: [Module] = []
        for (id, object) in objects where object["isa"] as? String == "PBXNativeTarget" {
            let product = object["productType"] as? String ?? ""
            guard !product.contains("test"), !product.contains("watchkit") else { continue }
            var sources: [URL] = [], resources: [URL] = [], warnings: [String] = []
            for phaseID in object["buildPhases"] as? [String] ?? [] {
                guard let phase = objects[phaseID] else { continue }
                for buildID in phase["files"] as? [String] ?? [] {
                    guard let ref = objects[buildID]?["fileRef"] as? String else { continue }
                    let children = objects[ref]?["children"] as? [String] ?? [ref]
                    for child in children {
                        guard let url = paths[child], index.members.contains(url) else { continue }
                        if phase["isa"] as? String == "PBXSourcesBuildPhase", url.pathExtension == "swift" { sources.append(url) }
                        if phase["isa"] as? String == "PBXResourcesBuildPhase", isResource(url) { resources.append(url) }
                    }
                }
            }
            var synced: URL?
            for syncID in object["fileSystemSynchronizedGroups"] as? [String] ?? [] {
                guard let folder = paths[syncID] else { continue }
                let exceptionIDs = objects[syncID]?["exceptions"] as? [String] ?? []
                let exclusions = exceptionIDs.compactMap { objects[$0] }.filter { $0["target"] as? String == id }.flatMap { $0["membershipExceptions"] as? [String] ?? [] }
                let excluded = Set(exclusions)
                let contents = try index.files(in: folder).filter { !excluded.contains(relativePath($0, root: folder)) }
                sources += contents.filter { $0.pathExtension == "swift" }
                resources += contents.filter(isResource)
                if synced == nil { synced = folder }
            }
            if sources.isEmpty { continue }
            if resources.isEmpty { warnings.append("No localization resource is registered for this target.") }
            let kind = product == "com.apple.product-type.application" ? "Application" : "Framework"
            let sourceRoot = synced ?? commonParent(sources, fallback: base)
            result.append(Module(name: object["name"] as? String ?? "Target", root: sourceRoot, kind: kind, sources: Array(Set(sources)).sorted { $0.path < $1.path }, resources: Array(Set(resources)).sorted { $0.path < $1.path }, warnings: warnings, projectFile: project, targetID: id, synchronizedRoot: synced))
        }
        return result
    }
    static func commonParent(_ urls: [URL], fallback: URL) -> URL {
        guard var parent = urls.first?.deletingLastPathComponent() else { return fallback }
        // All source URLs came from one enumeration. Compare lexical parents without filesystem calls.
        let paths = urls.map { $0.standardizedFileURL.path }
        while parent.path != "/" && !paths.allSatisfy({ $0.hasPrefix(parent.path + "/") }) { parent.deleteLastPathComponent() }
        return parent
    }
}
final class PackageTargets: SyntaxVisitor {
    struct Target { var name: String; var path: String?; var hasResources: Bool }
    var targets: [Target] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let called = node.calledExpression.trimmedDescription
        if [".target", ".executableTarget"].contains(called), let name = node.arguments.first(where: { $0.label?.text == "name" })?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            let path = node.arguments.first(where: { $0.label?.text == "path" })?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            targets.append(Target(name: name, path: path, hasResources: node.arguments.contains { $0.label?.text == "resources" }))
        }
        return .visitChildren
    }
}

/// Resolve each enumerated path once, then use binary search for target subtrees.
struct DiscoveryFileIndex {
    let members: Set<URL>
    private let entries: [(path: String, url: URL)]
    init(_ files: [URL]) throws {
        members = Set(files)
        var values: [(path: String, url: URL)] = []
        values.reserveCapacity(files.count)
        for file in files {
            try Task.checkCancellation()
            values.append((file.resolvingSymlinksInPath().standardizedFileURL.path, file))
        }
        entries = values.sorted { $0.path < $1.path }
    }
    func files(in folder: URL) throws -> [URL] {
        let base = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = base == "/" ? "/" : base + "/"
        var low = 0, high = entries.count
        while low < high {
            let middle = low + (high - low) / 2
            if entries[middle].path < prefix { low = middle + 1 } else { high = middle }
        }
        var result: [URL] = []
        while low < entries.count, entries[low].path.hasPrefix(prefix) {
            try Task.checkCancellation()
            result.append(entries[low].url)
            low += 1
        }
        return result
    }
}
