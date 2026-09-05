import Foundation

public enum LanguageMapping {
    public static func appleLocale(for remoteLocale: String) -> String {
        Locale.canonicalLanguageIdentifier(from: remoteLocale)
    }
}

public struct ImportOptions: Sendable {
    public var sourceLocale = "en"
    public var languages: [String: String] = ["ar": "ar"]
    public var requireReviewed = false
    public var replaceExisting = false
    public var preferredKeys: [String: Int] = [:]
    public init() {}
}
public enum ImportPlanner {
    public static func plan(root: URL, module: Module, config: ModuleOptions, remote: [RemoteKey], options: ImportOptions) throws -> ChangePlan {
        guard !config.resourcePath.isEmpty else { throw StudioError.message("Choose a localization table for \(module.name).") }
        let url = URL(fileURLWithPath: config.resourcePath)
        guard inside(url, root: root), module.resources.contains(url) || (module.synchronizedRoot.map { inside(url, root: $0) } ?? false) else { throw StudioError.message("The import destination is not owned by the selected module.") }
        var resource = try LocalizationResource(url: url, sourceLocale: config.sourceLocale)
        guard resource.original != nil else { throw StudioError.message("Register English strings before importing translations.") }
        let index = TranslationIndex(keys: remote, englishLocale: options.sourceLocale)
        var rows: [ReportRow] = [], legacy: [URL: LocalizationResource] = [:], membershipChanges: [FileChange] = []
        guard Set(options.languages.values).count == options.languages.count else { throw StudioError.message("Two remote languages map to the same Apple locale. Resolve the mapping before importing.") }
        for (key, english) in resource.english.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            if !resource.shouldTranslate(key: key) {
                rows.append(ReportRow(module: module.name, key: key, english: english, status: "Preserved", reason: "Catalog marks this key as not translatable.")); continue
            }
            let match = index.match(english, preferredID: options.preferredKeys[stableID(module.id + ":" + key + ":" + english)])
            for (remoteLocale, appleLocale) in options.languages.sorted(by: { $0.key < $1.key }) {
                let canonical = LanguageMapping.appleLocale(for: appleLocale)
                guard canonical == appleLocale else { throw StudioError.message("Apple uses \(canonical) for locale \(appleLocale). Update the visible language mapping before importing.") }
                guard appleLocale.range(of: "^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil, appleLocale != config.sourceLocale else { throw StudioError.message("Invalid or source-language destination locale: \(appleLocale)") }
                var row = ReportRow(module: module.name, key: key, english: english, language: appleLocale, status: "Missing", reason: match.reason, destination: relativePath(url, root: root), remoteKeyID: match.key?.id)
                guard let remoteKey = match.key else { row.status = match.candidates.isEmpty ? "Not found" : "Ambiguous"; rows.append(row); continue }
                guard remoteKey.is_plural != true else { row.status = "Unsupported"; row.reason = "Remote plural structure requires manual mapping; it was not flattened."; rows.append(row); continue }
                guard let translation = remoteKey.translations.first(where: { $0.language_iso == remoteLocale }), !translation.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { row.reason = "Matching key has no nonempty \(remoteLocale) translation."; rows.append(row); continue }
                let verified = translation.is_unverified == false && translation.is_reviewed == true
                if options.requireReviewed && !verified { row.status = "Unreviewed"; row.reason = "Translation does not meet the reviewed-only preference."; rows.append(row); continue }
                guard FormatValidation.compatible(english, translation.translation) else { row.status = "Invalid"; row.reason = "Translation placeholders differ from the English source."; rows.append(row); continue }
                if url.pathExtension == "xcstrings" {
                    if resource.hasComplexValue(key: key, locale: appleLocale) || resource.hasComplexValue(key: key, locale: config.sourceLocale) { row.status = "Unsupported"; row.reason = "Existing variations or substitutions need manual review."; rows.append(row); continue }
                    if let current = resource.translation(key: key, locale: appleLocale), !current.isEmpty {
                        if current == translation.translation { row.status = "Preserved"; row.reason = "Local translation already matches."; rows.append(row); continue }
                        if !options.replaceExisting { row.status = "Conflict"; row.reason = "Existing local translation differs and was preserved."; rows.append(row); continue }
                    }
                    try resource.importValue(key: key, locale: appleLocale, value: translation.translation, verified: verified)
                } else {
                    guard url.deletingLastPathComponent().lastPathComponent == config.sourceLocale + ".lproj" else { row.status = "Unsupported"; row.reason = "Legacy source files must be inside the configured source locale's .lproj directory."; rows.append(row); continue }
                    let target = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(appleLocale + ".lproj").appendingPathComponent(url.lastPathComponent)
                    row.destination = relativePath(target, root: root)
                    if legacy[target] == nil { legacy[target] = try LocalizationResource(url: target, sourceLocale: appleLocale) }
                    if legacy[target]?.original == nil && !membershipChanges.contains(where: { $0.reason == target.path }) {
                        try ResourceRegistration.include(target, module: module, sourceLocale: config.sourceLocale, changes: &membershipChanges)
                    }
                    if let current = legacy[target]?.english[key] {
                        if current == translation.translation || !options.replaceExisting {
                            row.status = current == translation.translation ? "Preserved" : "Conflict"
                            row.reason = "Existing legacy entry preserved. Enable replacement to preview an update."
                            rows.append(row); continue
                        }
                        try legacy[target]?.replaceLegacy(key: key, value: translation.translation)
                    } else {
                        try legacy[target]?.register(key: key, value: translation.translation)
                    }
                }
                row.status = "Imported"; row.reason = verified ? "Exact English match; reviewed translation." : "Exact English match; translation needs review."
                rows.append(row)
            }
        }
        var changes: [FileChange] = membershipChanges
        for item in [resource] + Array(legacy.values) {
            let data = try item.data()
            // Do not write merely to reformat the source file when no translation was imported there.
            if data != item.original && rows.contains(where: { $0.status == "Imported" && $0.destination == relativePath(item.url, root: root) }) { changes.append(FileChange(url: item.url, before: item.original, after: data, reason: "Import existing Lokalise translations")) }
        }
        return ChangePlan(title: "Import translations", root: root, changes: changes, rows: rows)
    }
}
