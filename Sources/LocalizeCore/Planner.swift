import Foundation
import SwiftParser

public enum Planner {
    public static func registration(root: URL, findings: [Finding], snapshots: [URL: Data], options: [String: ModuleOptions], modules: [Module]) throws -> ChangePlan {
        let selected = findings.filter { $0.selected && $0.status == .ready }
        guard !selected.isEmpty else { throw StudioError.message("Select at least one safe string to register.") }
        var changes: [FileChange] = [], rows: [ReportRow] = []
        let bySource = Dictionary(grouping: selected, by: \.file)
        for (file, items) in bySource {
            guard let original = snapshots[file] else { throw StudioError.message("Missing source snapshot. Analyze the project again.") }
            var bytes = Array(original)
            var nextStart = bytes.count
            for item in items.sorted(by: { $0.offset > $1.offset }) {
                guard let replacement = item.replacement, item.offset >= 0, item.offset + item.length <= nextStart,
                      String(bytes: bytes[item.offset..<(item.offset + item.length)], encoding: .utf8) == item.literal else { throw StudioError.message("Conflicting or stale source edits in \(file.lastPathComponent).") }
                bytes.replaceSubrange(item.offset..<(item.offset + item.length), with: replacement.utf8); nextStart = item.offset
            }
            let data = Data(bytes)
            guard let text = String(data: data, encoding: .utf8), !Parser.parse(source: text).hasError else { throw StudioError.message("Generated Swift failed syntax validation: \(file.path)") }
            if data != original { changes.append(FileChange(url: file, before: original, after: data, reason: "Replace \(items.count) user-facing string references")) }
        }
        for (url, items) in Dictionary(grouping: selected, by: { $0.resource! }) {
            guard inside(url, root: root) else { throw StudioError.message("Localization destinations must remain inside the selected project.") }
            let locale = options[items[0].moduleID]?.sourceLocale ?? "en"
            var resource = try LocalizationResource(url: url, sourceLocale: locale, original: snapshots[url])
            for moduleID in Set(items.map(\.moduleID)) {
                guard let module = modules.first(where: { $0.id == moduleID }) else { throw StudioError.message("Module ownership changed. Reanalyze first.") }
                try ResourceRegistration.include(url, module: module, sourceLocale: locale, changes: &changes)
            }
            for item in items {
                try resource.register(key: item.key, value: item.english)
                rows.append(ReportRow(module: item.moduleName, key: item.key, english: item.english, status: "Registered", source: relativePath(item.file, root: root) + ":\(item.line)", destination: relativePath(url, root: root)))
            }
            let data = try resource.data()
            if data != resource.original { changes.append(FileChange(url: url, before: resource.original, after: data, reason: "Register English values and semantic keys")) }
            if url.pathExtension == "strings" {
                let owners = modules.filter { Set(items.map(\.moduleID)).contains($0.id) }
                let translations = Set(owners.flatMap(\.resources)).filter { $0 != url && $0.lastPathComponent == url.lastPathComponent && $0.pathExtension == "strings" }
                for translationURL in translations {
                    var translated = try LocalizationResource(url: translationURL)
                    var changed = false
                    for item in items where item.english != item.key {
                        if let oldValue = translated.english[item.english], translated.english[item.key] == nil {
                            try translated.register(key: item.key, value: oldValue); changed = true
                        }
                    }
                    if changed { changes.append(FileChange(url: translationURL, before: translated.original, after: try translated.data(), reason: "Preserve existing translations under the new semantic keys")) }
                }
            }
        }
        return ChangePlan(title: "Register strings", root: root, changes: changes.sorted { $0.url.path < $1.url.path }, rows: rows)
    }
}
public enum FormatValidation {
    public static func placeholders(_ value: String) -> [String] {
        let pattern = #"%(?:(\d+)\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|h|l|q|L|z|t|j)?([@diuoxXfFeEgGaAcCsSpn])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let cleaned = value.replacingOccurrences(of: "%%", with: "") as NSString
        return regex.matches(in: cleaned as String, range: NSRange(location: 0, length: cleaned.length)).enumerated().map { index, match in
            let position = match.range(at: 1).location == NSNotFound ? String(index + 1) : cleaned.substring(with: match.range(at: 1))
            let length = match.range(at: 2).location == NSNotFound ? "" : cleaned.substring(with: match.range(at: 2))
            return position + ":" + length + cleaned.substring(with: match.range(at: 3))
        }.sorted()
    }
    public static func compatible(_ source: String, _ translated: String) -> Bool {
        // Dynamic width/precision arguments require a richer formatter; do not approve automatically.
        if source.range(of: #"%[^\s]*\*"#, options: .regularExpression) != nil || translated.range(of: #"%[^\s]*\*"#, options: .regularExpression) != nil { return false }
        return placeholders(source) == placeholders(translated)
    }
}
