import Foundation

/// Conservative whole-value checks. Sentences containing numbers or file types remain eligible.
enum TechnicalString {
    static let extensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "svg", "ico", "tif", "tiff", "bmp", "mp4", "mov", "avi", "m4v", "mp3", "wav", "m4a", "aac", "ogg", "json", "xml", "yaml", "yml", "csv", "tsv", "txt", "rtf", "html", "css", "js", "zip", "gz", "tar", "rar", "7z", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "swift", "strings", "xcstrings", "plist", "ttf", "otf", "woff", "woff2", "cer", "p12", "pem"]
    static func reason(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && text.unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) }) {
            return "Standalone number, numeric format, punctuation, or symbol."
        }
        if text.hasPrefix("^"), text.hasSuffix("$"), (try? NSRegularExpression(pattern: text)) != nil {
            return "Regular expression pattern, not display text."
        }
        if text.range(of: #"^(?:application|audio|font|image|model|multipart|text|video)/[A-Za-z0-9!#$&^_.+*-]+(?:\s*;\s*[A-Za-z0-9_-]+=[A-Za-z0-9_.-]+)*$"#, options: .regularExpression) != nil {
            return "MIME content type."
        }
        let lower = text.lowercased()
        if extensions.contains(lower) || (lower.hasPrefix(".") && extensions.contains(String(lower.dropFirst()))) {
            return "File type or extension."
        }
        if !text.contains(where: { $0.isWhitespace }), let dot = lower.lastIndex(of: "."), dot != lower.startIndex,
           extensions.contains(String(lower[lower.index(after: dot)...])) {
            return "Filename or resource path."
        }
        return nil
    }
}
