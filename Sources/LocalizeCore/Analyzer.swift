import Foundation
import SwiftSyntax
import SwiftParser

public enum Analyzer {
    public static func analyze(modules: [Module], allModules: [Module], options: [String: ModuleOptions], exclusions: Set<String> = [], wrappers: Set<String> = [], progress: @Sendable (Int, Int, String) -> Void = { _, _, _ in }) throws -> Analysis {
        var findings: [Finding] = [], snapshots: [URL: Data] = [:], warnings: [String] = []
        let ownership = Dictionary(grouping: allModules.flatMap { $0.sources }, by: { $0 }).mapValues(\.count)
        let total = modules.reduce(0) { $0 + $1.sources.count }; var processed = 0
        for module in modules {
            let config = options[module.id] ?? ModuleOptions(module: module)
            var resource: LocalizationResource?
            var resourceIssue: String?
            if !config.resourcePath.isEmpty {
                do {
                    let url = URL(fileURLWithPath: config.resourcePath)
                    resource = try LocalizationResource(url: url, sourceLocale: config.sourceLocale)
                    if let original = resource?.original { snapshots[url] = original }
                } catch { resourceIssue = error.localizedDescription; warnings.append(error.localizedDescription) }
            }
            var existing = resource?.english ?? [:]
            for file in module.sources {
                try Task.checkCancellation()
                processed += 1; progress(processed, total, file.lastPathComponent)
                let data = try Data(contentsOf: file); snapshots[file] = data
                guard let source = String(data: data, encoding: .utf8) else { warnings.append("Skipped non-UTF-8 Swift file: \(file.path)"); continue }
                let tree = Parser.parse(source: source)
                if tree.hasError { warnings.append("Swift syntax errors prevent safe conversion: \(file.path)"); continue }
                let visitor = LiteralVisitor(file: file, source: source, wrappers: wrappers, replacementTemplate: config.replacementTemplate); visitor.walk(tree)
                for candidate in visitor.candidates {
                    let english = candidate.value
                    var status = candidate.status, reason = candidate.reason
                    var key = KeyGenerator.key(prefix: config.prefix, english: english, existing: existing)
                    let knownKeys = existing.filter({ $0.value == english && $0.key != english }).keys.sorted()
                    if knownKeys.count == 1 { key = knownKeys[0] }
                    else if knownKeys.count > 1 && status == .ready { status = .review; reason = "Multiple local keys share this English value. Confirm the intended context before reusing a key." }
                    var replacement: String?
                    if candidate.localized && status != .excluded {
                        if let value = existing[english], english != value {
                            status = .localized; key = english; reason = "The key exists in the selected localization table."
                        } else if existing[english] == nil && english.range(of: "^[a-z0-9_]+(?:[._][a-z0-9_]+)+$", options: .regularExpression) != nil {
                            status = .review; key = english; reason = "This appears to be a key with no entry. Its English source value cannot be inferred."
                        }
                        if let table = candidate.table, let resource, table != resource.table { status = .review; reason = "This lookup uses table \(table), not the selected destination." }
                        if let bundle = candidate.bundle, bundle != config.bundleExpression { status = .review; reason = "This lookup uses bundle \(bundle), which differs from the module's configured resource bundle." }
                        if !config.bundleConfirmed { status = .review; reason = "Confirm this module's resource bundle before validating its lookups." }
                    }
                    if resource?.shouldTranslate(key: english) == false { status = .excluded; reason = "This catalog entry is marked as not translatable." }
                    if status == .ready {
                        if modules.filter({ (options[$0.id] ?? ModuleOptions(module: $0)).prefix == config.prefix }).count > 1 { status = .review; reason = "Selected modules share the same prefix. Assign distinct prefixes in module settings." }
                        else if ownership[file, default: 0] > 1 { status = .review; reason = "Shared source file: confirm one lookup works for every owning target." }
                        else if let resourceIssue { status = .review; reason = resourceIssue }
                        else if resource == nil { status = .review; reason = "Choose a localization destination for this module." }
                        else if !config.bundleConfirmed { status = .review; reason = "Confirm the module's localization bundle in module settings." }
                        else if let issue = ReplacementTemplate.validationError(config.replacementTemplate) { status = .review; reason = issue }
                        else if !KeyGenerator.validPrefix(config.prefix) { status = .review; reason = "Module prefixes must begin with a lowercase letter and contain only letters and digits." }
                        else if config.sourceLocale != "en" && !config.sourceLocale.hasPrefix("en-") && !config.sourceLocale.hasPrefix("en_") { status = .review; reason = "Automatic English-key conversion requires an English source locale." }
                        else if let table = candidate.table, table != resource?.table { status = .review; reason = "This lookup uses table \(table), not the selected destination." }
                        else if candidate.unsafeLookup { status = .review; reason = "A custom bundle, default value, or dynamic table needs manual migration." }
                        else if ![".main", ".module"].contains(config.bundleExpression) && config.bundleExpression.trimmingCharacters(in: .whitespaces).isEmpty { status = .review; reason = "A localization bundle expression is required." }
                        else {
                            if candidate.localized { replacement = KeyGenerator.quote(key) }
                            else if let template = config.replacementTemplate, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                do { replacement = try ReplacementTemplate.render(template, key: key) }
                                catch { status = .review; reason = error.localizedDescription }
                            } else {
                                replacement = "NSLocalizedString(\(KeyGenerator.quote(key)), tableName: \(KeyGenerator.quote(resource!.table)), bundle: \(config.bundleExpression), value: \(KeyGenerator.quote(english)), comment: \(KeyGenerator.quote("\(module.name): \(candidate.context)")))"
                            }
                            existing[key] = english
                        }
                    }
                    let id = stableID(file.path + ":\(candidate.offset):" + module.id)
                    if exclusions.contains(id) { status = .excluded; reason = "Excluded by your saved project rule."; replacement = nil }
                    findings.append(Finding(id: id, moduleID: module.id, moduleName: module.name, file: file, line: candidate.line, offset: candidate.offset, length: candidate.length, literal: candidate.literal, english: status == .localized ? (existing[key] ?? english) : english, key: key, status: status, reason: reason, context: candidate.context, replacement: replacement, resource: resource?.url, selected: status == .ready, sourceForms: candidate.sourceForms))
                }
            }
        }
        return Analysis(findings: findings, snapshots: snapshots, warnings: warnings, files: processed)
    }
}
private struct LiteralCandidate {
    var sourceForms: [String]
    var value: String; var literal: String; var offset: Int; var length: Int; var line: Int
    var status: FindingStatus; var reason: String; var context: String; var localized: Bool; var table: String?; var bundle: String?; var unsafeLookup: Bool
}
private final class LiteralVisitor: SyntaxVisitor {
    var candidates: [LiteralCandidate] = []
    let file: URL, source: String, wrappers: Set<String>
    let replacementTemplate: String?
    init(file: URL, source: String, wrappers: Set<String>, replacementTemplate: String?) { self.file = file; self.source = source; self.wrappers = wrappers; self.replacementTemplate = replacementTemplate; super.init(viewMode: .sourceAccurate) }
    private func isCodingKeyRawValue(_ node: StringLiteralExprSyntax) -> Bool {
        guard node.parent?.is(InitializerClauseSyntax.self) == true,
              node.parent?.parent?.is(EnumCaseElementSyntax.self) == true else { return false }
        var ancestor = node.parent
        while let current = ancestor {
            if let declaration = current.as(EnumDeclSyntax.self) {
                return declaration.name.text == "CodingKeys" || declaration.inheritanceClause?.inheritedTypes.contains {
                    ["CodingKey", "Swift.CodingKey"].contains($0.type.trimmedDescription)
                } == true
            }
            ancestor = current.parent
        }
        return false
    }
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let offset = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let literal = node.trimmedDescription
        let value = node.representedLiteralValue ?? literal
        let line = source.utf8.prefix(offset).filter { $0 == 10 }.count + 1
        var status: FindingStatus = .review, reason = "Unknown string context; review its user-facing intent.", context = "String literal", localized = false, table: String?, bundle: String?, unsafe = false
        let dynamic = node.segments.contains { $0.is(ExpressionSegmentSyntax.self) }
        // Only direct argument expressions are eligible. Nested builders, expressions and concatenation stay untouched.
        if let argument = node.parent?.as(LabeledExprSyntax.self), let list = argument.parent?.as(LabeledExprListSyntax.self), let call = list.parent?.as(FunctionCallExprSyntax.self) {
            let name = call.calledExpression.trimmedDescription
            let simple = name.components(separatedBy: ".").last ?? name
            let label = argument.label?.text ?? ""
            let first = call.arguments.first?.id == argument.id
            context = name + (label.isEmpty ? "(…)" : "(\(label): …)")
            if ["Image", "Color", "UIImage", "NSImage", "URL", "print", "debugPrint", "assert", "assertionFailure", "precondition", "fatalError", "accessibilityIdentifier", "id"].contains(simple) || ["systemImage", "systemName", "image", "named", "identifier", "id", "hex", "hexString", "format", "comment", "tableName", "table", "ofType", "forResource"].contains(label) || name.contains("logger.") || name.contains("analytics.") || label == "verbatim" {
                status = .excluded; reason = "Asset, identifier, diagnostic, or intentionally verbatim string."
            } else if (simple == "replacingOccurrences" && ["of", "with"].contains(label)) ||
                        (simple == "replacingCharacters" && label == "with") ||
                        (simple == "components" && label == "separatedBy") ||
                        (simple == "split" && label == "separator") {
                status = .excluded; reason = "String-processing argument, not display text."
            } else if simple == "NSLocalizedString" && first {
                localized = true; status = .ready; reason = "Existing lookup can migrate to a semantic key."
                let tableArg = call.arguments.first { $0.label?.text == "tableName" }
                table = tableArg?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? "Localizable"
                bundle = call.arguments.first { $0.label?.text == "bundle" }?.expression.trimmedDescription ?? ".main"
                unsafe = (tableArg != nil && tableArg?.expression.as(StringLiteralExprSyntax.self) == nil && tableArg?.expression.trimmedDescription != "nil") || call.arguments.contains { $0.label?.text == "bundle" || $0.label?.text == "value" }
            } else if ["String", "AttributedString"].contains(simple) && label == "localized" {
                localized = true; status = .ready; reason = "Existing localized value can migrate to a semantic key."
                let arg = call.arguments.first { $0.label?.text == "table" }
                table = arg?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? "Localizable"
                bundle = call.arguments.first { $0.label?.text == "bundle" }?.expression.trimmedDescription ?? ".main"
                unsafe = call.arguments.contains { ["bundle", "defaultValue"].contains($0.label?.text ?? "") } || (arg != nil && arg?.expression.as(StringLiteralExprSyntax.self) == nil)
            } else if first && (simple == "LocalizedStringKey" || (simple == "Text" && call.arguments.contains { ["tableName", "bundle"].contains($0.label?.text ?? "") })) {
                localized = true; status = .ready; reason = "Explicit SwiftUI localization lookup."
                let arg = call.arguments.first { $0.label?.text == "tableName" }
                table = arg?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue ?? "Localizable"
                bundle = call.arguments.first { $0.label?.text == "bundle" }?.expression.trimmedDescription ?? ".main"
                unsafe = arg != nil && arg?.expression.as(StringLiteralExprSyntax.self) == nil && arg?.expression.trimmedDescription != "nil"
            } else if wrappers.contains(name) && first {
                status = .review; reason = "Configured localization wrapper. Verify its key, table, and bundle contract before migration."
            } else if (["Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField", "GroupBox", "Section", "Menu", "Link"].contains(simple) && first) || (["navigationTitle", "navigationBarTitle", "accessibilityLabel", "accessibilityHint", "help", "alert", "confirmationDialog"].contains(simple) && first) || (["UIAlertController", "UIAlertAction"].contains(simple) && ["title", "message"].contains(label)) || (simple == "setTitle" && first) {
                status = .ready; reason = "Direct user-facing UI string."
            }
        } else if let sequence = node.parent?.as(ExprListSyntax.self), let expression = sequence.parent?.as(SequenceExprSyntax.self) {
            let elements = Array(expression.elements)
            if elements.count == 3, elements[1].is(AssignmentExprSyntax.self), elements[2].id == node.id {
                let lhs = elements[0].trimmedDescription
                context = lhs
                if [".text", ".title", ".placeholder", ".accessibilityLabel", ".accessibilityHint"].contains(where: lhs.hasSuffix) { status = .ready; reason = "Text property assignment." }
            } else { reason = "Concatenated or computed string; preserve expression semantics." }
        }
        if isCodingKeyRawValue(node) {
            status = .excluded; reason = "Serialization CodingKey raw value."
        }
        if let binding = node.parent?.as(InitializerClauseSyntax.self)?.parent?.as(PatternBindingSyntax.self),
           ["id", "identifier"].contains(binding.pattern.trimmedDescription) {
            status = .excluded; reason = "Identifier storage, not display text."
        }
        if ["id", "identifier"].contains(context) || context.hasSuffix(".id") || context.hasSuffix(".identifier") {
            status = .excluded; reason = "Identifier assignment, not display text."
        }
        if !dynamic {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) && !CharacterSet.decimalDigits.contains($0) }) {
                status = .excluded; reason = "Standalone punctuation or symbol, not translatable text."
            }
            if trimmed.range(of: #"^(?:\{[A-Za-z_][A-Za-z0-9_]*\}|\{[0-9]+\}|\\[nrt]|\s)+$"#, options: .regularExpression) != nil {
                status = .excluded; reason = "Placeholder or escaped whitespace without display text."
            }
            if trimmed.range(of: #"^(?:#|0[xX])(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil {
                status = .excluded; reason = "Hexadecimal color value."
            }
        }
        if !dynamic, let exclusion = TechnicalString.reason(value) {
            status = .excluded; reason = exclusion
        }
        // Recognize this module's configured wrapper on subsequent analysis.
        // Existing lookup expressions retain their wrapper; only the key literal changes.
        if !dynamic, status != .excluded, let template = replacementTemplate,
           let rendered = try? ReplacementTemplate.render(template, key: value) {
            let expected = Parser.parse(source: rendered).tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
            var ancestor: Syntax? = Syntax(node)
            while let expression = ancestor, !expression.is(CodeBlockItemSyntax.self) {
                if (expression.id != node.id || status == .ready), expression.as(ExprSyntax.self) != nil && expression.tokens(viewMode: .sourceAccurate).map(\.text) == expected {
                    localized = true; status = .ready; unsafe = false
                    reason = "Module-configured localization expression."
                    break
                }
                ancestor = expression.parent
            }
        }
        if dynamic && status != .excluded {
            let staticText = node.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
                .replacingOccurrences(of: #"\\[nrt]"#, with: "", options: .regularExpression)
            if staticText.unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) && !CharacterSet.decimalDigits.contains($0) }) {
                status = .excluded; reason = "Interpolation contains only variables and separators, without display text."
            } else {
                status = .dynamic; reason = "Swift interpolation requires a typed localization and placeholder review."
            }
        }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { status = .excluded; reason = "Empty or whitespace-only text." }
        if value.hasPrefix("https://") || value.hasPrefix("http://") { status = .excluded; reason = "URL literal." }
        if status == .ready, value.range(of: #"\{(?:[A-Za-z_][A-Za-z0-9_]*|[0-9]+)\}"#, options: .regularExpression) != nil {
            status = .review; reason = "Text contains template placeholders that require manual review."
        }
        if value.contains("%") && status == .ready && !FormatValidation.placeholders(value).isEmpty { status = .review; reason = "Format string requires a placeholder-aware manual conversion." }
        if status == .ready && (value.contains("**") || value.contains("](") || value.contains("`")) { status = .review; reason = "Markdown-sensitive text needs a manual migration that preserves attributed rendering." }
        candidates.append(LiteralCandidate(sourceForms: FindingHidePatterns.sourceForms(node), value: value, literal: literal, offset: offset, length: node.endPositionBeforeTrailingTrivia.utf8Offset - offset, line: line, status: status, reason: reason, context: context, localized: localized, table: table, bundle: bundle, unsafeLookup: unsafe))
        return .skipChildren
    }
}
