# Architecture

`LocalizeCore` is a UI-independent Swift package. `Lokanow` is a SwiftUI macOS application with AppKit folder pickers, file exports, and Keychain storage.

- **Discovery**: enumerates first-party files, reads Xcode OpenStep property lists, resolves groups/target build phases/synchronized folders, and parses Swift Package target declarations with SwiftSyntax. No manifest evaluation or build scripts execute during inspection.
- **Analyzer**: walks Swift string-literal syntax, classifies direct UI arguments and text assignments, excludes known non-UI contexts, and produces byte-offset replacements against source snapshots. Dynamic, ambiguous, shared-source, Markdown-sensitive, and unsafe custom-lookup cases remain review items.
- **LocalizationResource**: reads catalogs and legacy strings, validates duplicate legacy keys, preserves unknown catalog fields, and performs surgical legacy value changes. Catalog writes are sorted JSON; preview makes any formatting changes visible.
- **Planner / ResourceRegistration**: coordinates source and resource edits. Xcode edits replace only modified objects and add resource references/build phases/variant children; manifests are edited at parsed argument boundaries. Swift parse validation runs before a registration preview is accepted.
- **Transactions**: checks originals, serializes operations with a filesystem lock, persists complete before/after journals, applies atomic per-file replacements, verifies results, and restores earlier bytes on failure. Multi-file transactions are recoverable, not a filesystem-wide atomic primitive. Recovery preflights all files to preserve later edits.
- **LokaliseClient**: read-only actor using URLSession, cursor/offset pagination, typed models, bounded transient retries, cancellation, and explicit errors for auth/permissions/not-found. API bodies and credentials are not logged.
- **TranslationIndex / ImportPlanner**: indexes exact English values, rejects ambiguous/unapproved normalized matches, validates placeholders, handles quality preferences, and preserves conflicts by default. Remote plural structures and existing complex variants are not flattened.
- **StudioModel**: coordinates cancellable background work, presentation state, project preferences, reports, and explicit preview/apply actions. File transactions intentionally finish coherently once started.

## Trust boundaries

Projects and remote translations are untrusted data. Inspection does not run project code. Destinations must remain in the selected project. Credentials are Keychain-only. CSV exports neutralize formula-leading characters. Sandbox entitlements allow user-selected files and outbound networking only. The automated integration test, unlike normal inspection, explicitly builds disposable fixture projects.

## Authentication decision

API tokens provide a complete desktop-only connection. OAuth is not represented by a fake login button. A future OAuth option requires registering a real Lokalise application and implementing a provider-supported native/public-client flow or a backend that protects confidential client secrets. No OAuth secrets belong in this app binary.
