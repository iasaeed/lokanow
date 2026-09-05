import Foundation
import SwiftParser
import SwiftSyntax

/// Edits only relevant build-file objects; never evaluates package manifests or build scripts.
public enum ResourceRegistration {
    public static func include(_ resource: URL, module: Module, sourceLocale: String, changes: inout [FileChange]) throws {
        if module.resources.contains(resource), module.packageManifest == nil { return }
        if let sync = module.synchronizedRoot, inside(resource, root: sync) { return }
        if let project = module.projectFile, let targetID = module.targetID {
            let previous = changes.first { $0.url == project }
            let original = try previous?.before ?? Data(contentsOf: project)
            var editor = try PBXEditor(data: previous?.after ?? original)
            try editor.include(resource, projectFile: project, targetID: targetID, sourceLocale: sourceLocale)
            let after = try editor.data()
            changes.removeAll { $0.url == project }; changes.append(FileChange(url: project, before: original, after: after, reason: "Register localization resources in the Xcode target"))
            return
        }
        if let manifest = module.packageManifest {
            let previous = changes.first { $0.url == manifest }
            let original = try previous?.before ?? Data(contentsOf: manifest)
            let after = try PackageResourceEditor.include(resource, module: module, sourceLocale: sourceLocale, data: previous?.after ?? original)
            if after != original { changes.removeAll { $0.url == manifest }; changes.append(FileChange(url: manifest, before: original, after: after, reason: "Register processed localization resources and source language in Swift Package")) }
            return
        }
        throw StudioError.message("Build ownership could not be established for \(module.name). Select a discoverable Xcode or Swift Package target.")
    }
}
private struct PBXEditor {
    var document: [String: Any]
    var objects: [String: [String: Any]]
    var original: String
    var changed = Set<String>()
    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8), let doc = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let objects = doc["objects"] as? [String: [String: Any]] else { throw StudioError.message("Could not parse Xcode resource ownership.") }
        self.document = doc; self.objects = objects; self.original = text
    }
    mutating func set(_ id: String, _ value: [String: Any]) { objects[id] = value; changed.insert(id) }
    mutating func identifier(_ seed: String) -> String {
        var salt = 0
        while true { let id = String(stableID(seed + ":\(salt)").prefix(24)).uppercased(); if objects[id] == nil { return id }; salt += 1 }
    }
    mutating func include(_ url: URL, projectFile: URL, targetID: String, sourceLocale: String) throws {
        guard var target = objects[targetID], let rootID = document["rootObject"] as? String, var project = objects[rootID], let groupID = project["mainGroup"] as? String, var mainGroup = objects[groupID] else { throw StudioError.message("The target's Xcode resource configuration is incomplete.") }
        let base = projectFile.deletingLastPathComponent().deletingLastPathComponent()
        guard inside(url, root: base) else { throw StudioError.message("New resources must be inside the Xcode project root.") }
        let fileID = identifier(url.path + ":file")
        var buildReference = fileID
        if url.pathExtension == "strings", url.deletingLastPathComponent().pathExtension == "lproj" {
            let locale = url.deletingLastPathComponent().deletingPathExtension().lastPathComponent
            let filename = url.lastPathComponent
            // Match existing variant groups through their child SOURCE_ROOT paths or group ancestry.
            let existing = objects.first { id, value in
                guard value["isa"] as? String == "PBXVariantGroup", (value["name"] as? String ?? value["path"] as? String) == filename else { return false }
                return (value["children"] as? [String] ?? []).contains { child in
                    guard let path = resolvePath(child, base: base) else { return false }
                    return path.deletingLastPathComponent().deletingLastPathComponent() == url.deletingLastPathComponent().deletingLastPathComponent()
                }
            }
            let variantID = existing?.key ?? identifier(url.deletingLastPathComponent().deletingLastPathComponent().path + filename + ":variant")
            var variant = existing?.value ?? ["isa": "PBXVariantGroup", "name": filename, "sourceTree": "<group>", "children": [String]()]
            let children = variant["children"] as? [String] ?? []
            if children.contains(where: { resolvePath($0, base: base) == url }) { return }
            set(fileID, ["isa": "PBXFileReference", "lastKnownFileType": "text.plist.strings", "name": locale, "path": relativePath(url, root: base), "sourceTree": "SOURCE_ROOT"])
            variant["children"] = children + [fileID]; set(variantID, variant); buildReference = variantID
            if existing == nil { mainGroup["children"] = (mainGroup["children"] as? [String] ?? []) + [variantID]; set(groupID, mainGroup) }
            var regions = project["knownRegions"] as? [String] ?? []
            for language in [sourceLocale, locale] where !regions.contains(language) { regions.append(language) }
            project["knownRegions"] = regions; set(rootID, project)
        } else {
            set(fileID, ["isa": "PBXFileReference", "lastKnownFileType": "text.json.xcstrings", "path": relativePath(url, root: base), "sourceTree": "SOURCE_ROOT"])
            mainGroup["children"] = (mainGroup["children"] as? [String] ?? []) + [fileID]; set(groupID, mainGroup)
        }
        let phases = target["buildPhases"] as? [String] ?? []
        let existingPhase = phases.first { objects[$0]?["isa"] as? String == "PBXResourcesBuildPhase" }
        let phaseID = existingPhase ?? identifier(targetID + ":resources")
        var phase = objects[phaseID] ?? ["isa": "PBXResourcesBuildPhase", "buildActionMask": "2147483647", "runOnlyForDeploymentPostprocessing": "0", "files": [String]()]
        let builds = phase["files"] as? [String] ?? []
        if !builds.contains(where: { objects[$0]?["fileRef"] as? String == buildReference }) {
            let buildID = identifier(targetID + buildReference + ":build")
            set(buildID, ["isa": "PBXBuildFile", "fileRef": buildReference]); phase["files"] = builds + [buildID]; set(phaseID, phase)
        }
        if existingPhase == nil { target["buildPhases"] = phases + [phaseID]; set(targetID, target) }
    }
    func resolvePath(_ id: String, base: URL, visited: Set<String> = []) -> URL? {
        guard !visited.contains(id), let object = objects[id] else { return nil }
        let path = object["path"] as? String ?? ""
        if object["sourceTree"] as? String == "SOURCE_ROOT" { return base.appendingPathComponent(path).standardizedFileURL }
        if let parentID = objects.first(where: { ($0.value["children"] as? [String] ?? []).contains(id) })?.key,
           let parent = resolvePath(parentID, base: base, visited: visited.union([id])) { return parent.appendingPathComponent(path).standardizedFileURL }
        return base.appendingPathComponent(path).standardizedFileURL
    }
    func data() throws -> Data {
        var output = original
        var insertions = ""
        for id in changed.sorted() {
            let replacement = "\(id) = \(Self.serialize(objects[id]!));"
            if let range = objectRange(id, in: output) { output.replaceSubrange(range, with: replacement) }
            else { insertions += "\n\t\t" + replacement + "\n" }
        }
        if !insertions.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: #"objects\s*=\s*\{"#), let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)), let range = Range(match.range, in: output) else { throw StudioError.message("Unsupported Xcode project serialization.") }
            output.insert(contentsOf: insertions, at: range.upperBound)
        }
        let data = Data(output.utf8)
        _ = try PropertyListSerialization.propertyList(from: data, format: nil)
        return data
    }
    func objectRange(_ id: String, in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: id) + #"\s*(?:/\*.*?\*/\s*)?=\s*\{"#), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let start = Range(match.range, in: text) else { return nil }
        var cursor = text.index(before: start.upperBound), depth = 0, quoted = false, escaped = false, comment = false
        while cursor < text.endIndex {
            let character = text[cursor], next = text.index(after: cursor)
            if comment { if character == "*", next < text.endIndex, text[next] == "/" { comment = false; cursor = text.index(after: next); continue } }
            else if quoted { if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false } }
            else if character == "\"" { quoted = true }
            else if character == "/", next < text.endIndex, text[next] == "*" { comment = true; cursor = text.index(after: next); continue }
            else if character == "{" { depth += 1 }
            else if character == "}" { depth -= 1; if depth == 0 { var end = next; while end < text.endIndex && text[end].isWhitespace { end = text.index(after: end) }; if end < text.endIndex && text[end] == ";" { end = text.index(after: end) }; return start.lowerBound..<end } }
            cursor = next
        }
        return nil
    }
    static func serialize(_ value: Any) -> String {
        if let dictionary = value as? [String: Any] { return "{\n" + dictionary.keys.sorted().map { "\t\t\t\(KeyGenerator.quote($0)) = \(serialize(dictionary[$0]!));" }.joined(separator: "\n") + "\n\t\t}" }
        if let array = value as? [Any] { return "(" + array.map(serialize).joined(separator: ", ") + (array.isEmpty ? "" : ",") + ")" }
        return KeyGenerator.quote(String(describing: value))
    }
}
private enum PackageResourceEditor {
    static func include(_ resource: URL, module: Module, sourceLocale: String, data: Data) throws -> Data {
        guard inside(resource, root: module.root), let text = String(data: data, encoding: .utf8) else { throw StudioError.message("Package resources must be inside their target directory.") }
        let tree = Parser.parse(source: text); let visitor = Calls(); visitor.walk(tree)
        guard let target = visitor.calls.first(where: { [".target", ".executableTarget"].contains($0.calledExpression.trimmedDescription) && $0.arguments.first(where: { $0.label?.text == "name" })?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == module.name }), let package = visitor.calls.first(where: { $0.calledExpression.trimmedDescription == "Package" }) else { throw StudioError.message("The package target uses a computed manifest; add its resource declaration manually.") }
        var edits: [(Int, Int, String)] = []
        let relative = relativePath(resource, root: module.root)
        // Localized legacy files must be processed through their containing resource directory.
        let processPath = resource.pathExtension == "strings" ? relativePath(resource.deletingLastPathComponent().deletingLastPathComponent(), root: module.root) : relative
        guard processPath != ".", processPath != module.root.path, !processPath.isEmpty else { throw StudioError.message("Place package localization files under a Resources directory before registration.") }
        if let argument = target.arguments.first(where: { $0.label?.text == "resources" }) {
            guard let array = argument.expression.as(ArrayExprSyntax.self) else { throw StudioError.message("Computed package resource declarations require manual review.") }
            let covered = array.elements.contains { element in
                guard let call = element.expression.as(FunctionCallExprSyntax.self), call.calledExpression.trimmedDescription == ".process", let path = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { return false }
                return inside(resource, root: module.root.appendingPathComponent(path))
            }
            if !covered { let suffix = array.elements.isEmpty || array.elements.last?.trailingComma != nil ? "" : ", "; edits.append((array.rightSquare.positionAfterSkippingLeadingTrivia.utf8Offset, 0, suffix + ".process(\(KeyGenerator.quote(processPath)))")) }
        } else {
            guard let paren = target.rightParen else { throw StudioError.message("Unsupported package target declaration.") }
            if let following = target.arguments.first(where: { ["publicHeadersPath", "packageAccess", "cSettings", "cxxSettings", "swiftSettings", "linkerSettings", "plugins"].contains($0.label?.text ?? "") }) {
                edits.append((following.positionAfterSkippingLeadingTrivia.utf8Offset, 0, "resources: [.process(\(KeyGenerator.quote(processPath)))], "))
            } else {
                let suffix = target.arguments.last?.trailingComma == nil ? ", " : " "
                edits.append((paren.positionAfterSkippingLeadingTrivia.utf8Offset, 0, suffix + "resources: [.process(\(KeyGenerator.quote(processPath)))]"))
            }
        }
        if let locale = package.arguments.first(where: { $0.label?.text == "defaultLocalization" }) {
            guard locale.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == sourceLocale else { throw StudioError.message("Package defaultLocalization differs from the configured source locale.") }
        } else if let name = package.arguments.first(where: { $0.label?.text == "name" }) {
            let end = name.endPositionBeforeTrailingTrivia.utf8Offset
            edits.append((end, 0, name.trailingComma == nil ? ", defaultLocalization: \(KeyGenerator.quote(sourceLocale))" : " defaultLocalization: \(KeyGenerator.quote(sourceLocale)),"))
        }
        var bytes = Array(data)
        for edit in edits.sorted(by: { $0.0 > $1.0 }) { bytes.replaceSubrange(edit.0..<(edit.0 + edit.1), with: edit.2.utf8) }
        let result = Data(bytes)
        guard !Parser.parse(source: String(decoding: result, as: UTF8.self)).hasError else { throw StudioError.message("Package resource edit failed syntax validation.") }
        return result
    }
    final class Calls: SyntaxVisitor {
        var calls: [FunctionCallExprSyntax] = []
        init() { super.init(viewMode: .sourceAccurate) }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind { calls.append(node); return .visitChildren }
    }
}
