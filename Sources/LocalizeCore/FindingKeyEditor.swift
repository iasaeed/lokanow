import Foundation

public enum FindingKeyEditor {
    public static func edit(id: String, key draft: String, findings: [Finding], snapshots: [URL: Data], options: [String: ModuleOptions]) throws -> [Finding] {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.range(of: #"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*$"#, options: .regularExpression) != nil else {
            throw StudioError.message("Use letters, numbers, underscores, and dots. Start with a letter and do not leave empty segments.")
        }
        guard let finding = findings.first(where: { $0.id == id }), [.ready, .review].contains(finding.status) else {
            throw StudioError.message("Only pending registration or review keys can be edited. Reanalyze if this result changed.")
        }
        guard key != finding.key else { return findings }
        let targets = findings.indices.filter { findings[$0].moduleID == finding.moduleID && findings[$0].english == finding.english && findings[$0].key == finding.key && [.ready, .review].contains(findings[$0].status) }
        var checkedResources: Set<URL> = []
        for index in targets {
            let item = findings[index]
            if findings.contains(where: { (($0.resource != nil && $0.resource == item.resource) || $0.moduleID == item.moduleID) && $0.key == key && $0.english != item.english }) {
                throw StudioError.message("This key is already used for a different English value in the results.")
            }
            if let url = item.resource, checkedResources.insert(url).inserted, let data = snapshots[url] {
                let resource = try LocalizationResource(url: url, sourceLocale: options[item.moduleID]?.sourceLocale ?? "en", original: data)
                if let existing = resource.english[key], existing != item.english {
                    throw StudioError.message("This key already has a different English value in the localization file.")
                }
            }
        }
        var result = findings
        for index in targets {
            let item = findings[index]
            if let replacement = item.replacement {
                if replacement == KeyGenerator.quote(item.key) {
                    result[index].replacement = KeyGenerator.quote(key)
                } else if let template = options[item.moduleID]?.replacementTemplate, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[index].replacement = try ReplacementTemplate.render(template, key: key)
                } else if let resource = item.resource, let option = options[item.moduleID] {
                    result[index].replacement = "NSLocalizedString(\(KeyGenerator.quote(key)), tableName: \(KeyGenerator.quote(resource.deletingPathExtension().lastPathComponent)), bundle: \(option.bundleExpression), value: \(KeyGenerator.quote(item.english)), comment: \(KeyGenerator.quote("\(item.moduleName): \(item.context)")))"
                } else { throw StudioError.message("The replacement configuration is unavailable. Reanalyze before editing this key.") }
            }
            result[index].key = key
        }
        return result
    }
}
