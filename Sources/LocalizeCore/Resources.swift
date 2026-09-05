import Foundation

/// Retains unknown catalog fields and untouched legacy bytes. Legacy insertion is append-only.
public struct LocalizationResource {
    public var url: URL
    public var original: Data?
    public var sourceLocale: String
    private var catalog: [String: Any]?
    private var legacy: String?
    private var legacyEncoding: String.Encoding = .utf8
    public private(set) var english: [String: String] = [:]
    public var table: String { url.deletingPathExtension().lastPathComponent }
    public init(url: URL, sourceLocale: String = "en", original: Data? = nil) throws {
        self.url = url; self.sourceLocale = sourceLocale
        self.original = try original ?? (FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil)
        if url.pathExtension == "xcstrings" {
            if let data = self.original {
                guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any], let source = document["sourceLanguage"] as? String, document["strings"] is [String: Any] else { throw StudioError.message("Invalid string catalog: \(url.lastPathComponent)") }
                guard source == sourceLocale else { throw StudioError.message("Catalog source language is \(source), but this module is configured for \(sourceLocale).") }
                catalog = document
            } else { catalog = ["sourceLanguage": sourceLocale, "version": "1.0", "strings": [String: Any]()] }
            for (key, raw) in catalog?["strings"] as? [String: Any] ?? [:] {
                let entry = raw as? [String: Any] ?? [:]
                let localized = (entry["localizations"] as? [String: Any])?[sourceLocale] as? [String: Any]
                english[key] = ((localized?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
            }
        } else if url.pathExtension == "strings" {
            let data = self.original ?? Data()
            if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) { legacyEncoding = .utf16 }
            guard let text = String(data: data, encoding: legacyEncoding) else { throw StudioError.message("Unsupported strings-file encoding: \(url.path)") }
            legacy = text
            english = try Self.parseLegacy(text)
        } else { throw StudioError.message("Choose an .xcstrings or .strings file. Plural files are preserved but are not automatic conversion destinations.") }
    }
    public static func parseLegacy(_ text: String) throws -> [String: String] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let data = text.data(using: .utf8) else { throw StudioError.message("Invalid string encoding.") }
        guard let entries = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else { throw StudioError.message("Malformed .strings file.") }
        // Foundation silently drops duplicate keys, so also count parsed assignments with a lexer.
        let scanner = LegacyKeyScanner(text)
        let keys = try scanner.keys()
        guard Set(keys).count == keys.count else { throw StudioError.message("Duplicate keys in a .strings file. Resolve duplicates before writing.") }
        return entries
    }
    public mutating func register(key: String, value: String) throws {
        if let existing = english[key] {
            guard existing == value else { throw StudioError.message("Key collision: \(key) already has a different English value.") }; return
        }
        if catalog != nil {
            var strings = catalog?["strings"] as? [String: Any] ?? [:]
            // English-literal keys may already carry translations and Xcode metadata.
            // Copy the whole entry and keep the old key for references outside this selection.
            var entry = strings[value] as? [String: Any] ?? [:]
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            if localizations[sourceLocale] == nil { localizations[sourceLocale] = ["stringUnit": ["state": "translated", "value": value]] }
            entry["localizations"] = localizations; entry["extractionState"] = "manual"
            strings[key] = entry
            catalog?["strings"] = strings
        } else { legacy = (legacy ?? "") + "\n\(KeyGenerator.quote(key)) = \(KeyGenerator.quote(value));\n" }
        english[key] = value
    }
    public func translation(key: String, locale: String) -> String? {
        guard let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any], let local = (entry["localizations"] as? [String: Any])?[locale] as? [String: Any] else { return nil }
        return (local["stringUnit"] as? [String: Any])?["value"] as? String
    }
    public func shouldTranslate(key: String) -> Bool {
        let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any]
        return entry?["shouldTranslate"] as? Bool ?? true
    }
    public func hasComplexValue(key: String, locale: String) -> Bool {
        guard let entry = (catalog?["strings"] as? [String: Any])?[key] as? [String: Any], let local = (entry["localizations"] as? [String: Any])?[locale] as? [String: Any] else { return false }
        return local["variations"] != nil || local["substitutions"] != nil
    }
    public mutating func importValue(key: String, locale: String, value: String, verified: Bool) throws {
        guard catalog != nil else { throw StudioError.message("Legacy imports must be routed to the language-specific file.") }
        guard !hasComplexValue(key: key, locale: locale) else { throw StudioError.message("Existing plural or device variations require manual review.") }
        var strings = catalog?["strings"] as? [String: Any] ?? [:]
        var entry = strings[key] as? [String: Any] ?? [:]
        var localizations = entry["localizations"] as? [String: Any] ?? [:]
        var local = localizations[locale] as? [String: Any] ?? [:]
        var unit = local["stringUnit"] as? [String: Any] ?? [:]
        unit["value"] = value; unit["state"] = verified ? "translated" : "needs_review"
        local["stringUnit"] = unit; localizations[locale] = local; entry["localizations"] = localizations; strings[key] = entry; catalog?["strings"] = strings
    }
    public mutating func replaceLegacy(key: String, value: String) throws {
        guard english[key] != nil else { try register(key: key, value: value); return }
        guard let text = legacy, let entry = try LegacyKeyScanner(text).assignments().first(where: { $0.key == key }) else { throw StudioError.message("Could not locate the legacy value safely.") }
        var chars = Array(text)
        chars.replaceSubrange(entry.start..<entry.end, with: KeyGenerator.quote(value))
        legacy = String(chars); english[key] = value
    }
    public func data() throws -> Data {
        if let catalog { return try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data([10]) }
        guard let data = legacy?.data(using: legacyEncoding) else { throw StudioError.message("Could not encode legacy strings.") }
        return data
    }
}
private final class LegacyKeyScanner {
    struct Assignment { var key: String; var start: Int; var end: Int }
    let chars: [Character]; var index = 0
    init(_ text: String) { chars = Array(text) }
    func keys() throws -> [String] {
        try assignments().map(\.key)
    }
    func assignments() throws -> [Assignment] {
        var result: [Assignment] = []
        while index < chars.count {
            skip()
            if index >= chars.count { break }
            let key = try token(); skip()
            guard index < chars.count, chars[index] == "=" else { throw StudioError.message("Malformed .strings assignment.") }; index += 1
            skip(); let valueStart = index; _ = try token(); let valueEnd = index; skip()
            guard index < chars.count, chars[index] == ";" else { throw StudioError.message("Missing semicolon in .strings file.") }; index += 1; result.append(Assignment(key: key, start: valueStart, end: valueEnd))
        }
        return result
    }
    func skip() {
        while index < chars.count {
            if chars[index].isWhitespace || chars[index] == "\u{feff}" { index += 1 }
            else if index + 1 < chars.count, chars[index] == "/", chars[index + 1] == "/" { while index < chars.count && chars[index] != "\n" { index += 1 } }
            else if index + 1 < chars.count, chars[index] == "/", chars[index + 1] == "*" {
                index += 2
                while index + 1 < chars.count && !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                index = min(chars.count, index + 2)
            } else { break }
        }
    }
    func token() throws -> String {
        guard index < chars.count else { throw StudioError.message("Unexpected end of .strings file.") }
        let start = index
        if chars[index] == "\"" {
            index += 1
            while index < chars.count {
                if chars[index] == "\\" { index += 2; continue }
                if chars[index] == "\"" { index += 1; break }; index += 1
            }
        } else { while index < chars.count && !chars[index].isWhitespace && !["=", ";"].contains(chars[index]) { index += 1 } }
        let raw = String(chars[start..<min(index, chars.count)])
        let data = Data((raw + " = \"\";").utf8)
        guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String], let key = dict.keys.first else { throw StudioError.message("Invalid .strings token.") }
        return key
    }
}
