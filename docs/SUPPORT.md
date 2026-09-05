# Supported behavior and boundaries

## Supported

- macOS 14+ native UI; Xcode 26 / Swift 6.2 build toolchain.
- SwiftUI and UIKit direct text contexts, known localization APIs, literal Swift Package targets, conventional and file-system-synchronized Xcode targets.
- Module search/multiselection, stable configurable prefixes, table routing, per-module remote project/branch overrides, explicit bundle ownership.
- `.xcstrings`, custom tables, localized `.strings`, UTF-8/UTF-16 legacy files, preservation of existing catalog metadata and legacy comments.
- Safe preview/apply, source snapshot checking, recoverable journals, undo, offline analysis, explicit offline translation cache.
- Exact English matching, remote-key ambiguity review, Arabic and configurable languages, placeholder/quality checks, preserved conflicts or explicit replacement.
- Persistent reports and CSV/JSON/Markdown export, unresolved-item copying, source opening in Xcode, VoiceOver labels, light/dark appearance.

## Detected or preserved, requiring review

- Swift interpolation, string concatenation, format strings, and runtime-computed messages.
- Plural/device variants and `.stringsdict` conversion. Existing data remains untouched; remote plural messages are reported as unsupported.
- Unknown custom UI APIs, localization wrappers, custom bundle/default-value lookups whose semantics cannot be safely inferred, and Markdown-sensitive text.
- Shared source files owned by multiple targets and multiple existing semantic keys with identical English values.
- Computed `Package.swift` target paths/resources, unconventional Xcode group/project constructs, external project source references, or unsupported encodings.
- Storyboard/XIB/Objective-C extraction is outside this Swift-source analyzer. These files are not modified. Static analysis does not claim whole-app runtime coverage.
- Multiple localization tables are supported by routing one table per module per operation. Analyze/import other tables in separate operations.

The analyzer uses syntax and recognized API context, not a full compiler type checker. Review every preview and build your project after changes. The fixture suite verifies common SwiftUI/UIKit cases; it cannot establish every application's type and resource conventions.

## Release verification still requiring external configuration

Live token validation and exact-value imports were verified with the user-saved account on September 5, 2026; branch-specific access and additional account configurations remain untested. Mock-server tests exercise pagination, authentication failure, malformed responses, ambiguous values, and transient retry behavior. Public distribution requires the owner's Apple Developer identity and notarization credentials. No signed/notarized public release is claimed without those steps.
