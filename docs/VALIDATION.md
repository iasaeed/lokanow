# Validation

The automated suite covers Swift analysis, semantic keys, templates, resource preservation, source rewriting, transaction recovery, locale mapping, translation caching, pagination, and network error handling. All fixtures under `Fixtures` and `Tests` are synthetic. Private account data and local live-test artifacts are excluded from the repository.

Run the regression suite with `swift test`. Run the opt-in build integration with `LOCALIZE_INTEGRATION=1 swift test --filter FixtureIntegrationTests` on a Mac with Xcode 26 and XcodeGen. The integration test uses temporary copies of synthetic projects.

Direct desktop checks cover project selection, module removal and restoration, configuration, analysis, previews, apply, undo, settings, and the cache animation. The Xcode UI test runner timed out enabling automation on the development host; it is not claimed as passing.

Additional macOS versions, Intel hardware, and managed non-admin devices require further real-device testing. Code review and secret scanning reduce risk but do not prove the absence of every defect.
