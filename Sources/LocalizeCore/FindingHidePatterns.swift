import Foundation
import SwiftSyntax

/// Display-only matching. Patterns never change analysis classifications or source files.
public struct FindingHidePatterns {
    private let wrappers: Set<String>
    private let keys: [NSRegularExpression]

    public init(_ text: String) {
        var parts: [String] = [], current = "", depth = 0
        for character in text {
            if character == "," && depth == 0 { parts.append(current); current = ""; continue }
            current.append(character)
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(0, depth - 1) }
        }
        parts.append(current)
        let patterns = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        wrappers = Set(patterns.filter { $0.contains("{text}") }.map(Self.normalize))
        keys = patterns.filter { !$0.contains("{text}") }.compactMap {
            let expression = $0.components(separatedBy: "*").map(NSRegularExpression.escapedPattern(for:)).joined(separator: ".*")
            return try? NSRegularExpression(pattern: "\\A" + expression + "\\z")
        }
    }

    public func matches(_ finding: Finding) -> Bool {
        if (finding.sourceForms ?? []).contains(where: { wrappers.contains(Self.normalize($0)) }) { return true }
        return [finding.english, finding.key].contains { value in
            keys.contains { $0.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\"{text}\"", with: "{text}").filter { !$0.isWhitespace }
    }

    /// Preserve the actual expression around this literal, not neighboring strings on its line.
    static func sourceForms(_ literal: StringLiteralExprSyntax) -> [String] {
        var forms: [String] = [], ancestor = literal.parent
        while let node = ancestor {
            if node.is(CodeBlockItemSyntax.self) || node.is(ClosureExprSyntax.self) || node.is(VariableDeclSyntax.self) { break }
            if node.is(ExprSyntax.self) {
                let bytes = Array(node.description.utf8)
                if bytes.count > 4096 { break }
                let start = literal.positionAfterSkippingLeadingTrivia.utf8Offset - node.position.utf8Offset
                let end = literal.endPositionBeforeTrailingTrivia.utf8Offset - node.position.utf8Offset
                if start >= 0 && end <= bytes.count {
                    forms.append(String(decoding: bytes[..<start], as: UTF8.self) + "{text}" + String(decoding: bytes[end...], as: UTF8.self))
                }
            }
            ancestor = node.parent
        }
        return forms
    }
}
