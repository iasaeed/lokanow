import Foundation
import SwiftParser
import SwiftSyntax

/// Placeholders represent complete Swift expressions, including string quoting.
public enum ReplacementTemplate {
    public static func render(_ template: String, key: String) throws -> String {
        guard template.contains("{key}") else { throw StudioError.message("The replacement template must contain {key}. Do not put quotes around this placeholder.") }
        let result = template.replacingOccurrences(of: "{key}", with: KeyGenerator.quote(key))
        let tree = Parser.parse(source: "let __localizePreview = " + result)
        guard !tree.hasError, tree.statements.count == 1,
              let declaration = tree.statements.first?.item.as(VariableDeclSyntax.self),
              declaration.bindings.count == 1,
              let expression = declaration.bindings.first?.initializer?.value,
              expression.tokens(viewMode: .sourceAccurate).contains(where: { $0.text == String(KeyGenerator.quote(key).dropFirst().dropLast()) }) else {
            throw StudioError.message("Use one valid Swift expression with {key} as an unquoted placeholder, for example {key}.localized or .localize({key}).")
        }
        return result
    }

    public static func validationError(_ template: String?) -> String? {
        guard let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do { _ = try render(template, key: "module.example.key"); return nil }
        catch { return error.localizedDescription }
    }
}
