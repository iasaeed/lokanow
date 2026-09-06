import Foundation
import AppKit

/// Bounded rendering pages; the planned file data is never shortened or modified.
public enum FilePreview {
    public static func attributedPage(_ text: String, isDiff: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor
        ])
        if isDiff {
            text.enumerateSubstrings(in: text.startIndex..., options: .byLines) { line, range, _, _ in
                let color: NSColor?
                if line?.hasPrefix("+") == true { color = .systemGreen }
                else if line?.hasPrefix("-") == true { color = .systemRed }
                else if line?.hasPrefix("@@") == true { color = .systemPurple }
                else { color = nil }
                if let color { result.addAttribute(.foregroundColor, value: color, range: NSRange(range, in: text)) }
            }
        }
        return result
    }

    public static func pages(_ change: FileChange, mode: String, limit: Int = 16_000) throws -> [String] {
        try Task.checkCancellation()
        let text = mode == "Diff" ? FileDiff.unified(change) : (mode == "Before" ? change.beforeText : change.afterText)
        var pages: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(start, offsetBy: max(1, limit), limitedBy: text.endIndex) ?? text.endIndex
            pages.append(String(text[start..<end]))
            start = end
        }
        return pages.isEmpty ? [""] : pages
    }
}
