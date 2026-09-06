import Foundation

public enum FindingSearch {
    public static func results(_ findings: [Finding], query: String, status: String, hiddenIDs: Set<String>, sortOrder: [KeyPathComparator<Finding>]) throws -> [Finding] {
        var result: [Finding] = []
        for finding in findings {
            try Task.checkCancellation()
            guard !hiddenIDs.contains(finding.id),
                  status == "Everything" || (status == "All actionable" ? finding.status != .excluded && finding.status != .localized : finding.status.rawValue == status),
                  query.isEmpty || finding.english.localizedCaseInsensitiveContains(query) || finding.key.localizedCaseInsensitiveContains(query) || finding.moduleName.localizedCaseInsensitiveContains(query) else { continue }
            result.append(finding)
        }
        try Task.checkCancellation()
        result.sort(using: sortOrder)
        try Task.checkCancellation()
        return result
    }
}
