# Build and distribution

## Local build

Run `./scripts/build.sh`. The Xcode project uses the local `LocalizeCore` package, which pins the official SwiftSyntax 602.0.0 release. The generated app is sandboxed and signed to run locally.

The included Xcode project is checked in. XcodeGen can recreate it from `project.yml`. Package tests can run without XcodeGen; the iOS fixture integration test uses XcodeGen.

## Developer ID release

Configure an Apple Developer team and a Keychain notarytool profile, then run:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID NOTARY_PROFILE=YOUR_PROFILE ./scripts/release.sh
```

This archives, exports a Developer ID application, submits it for notarization, and staples the ticket. Use your own registered bundle identifier if distributing under your company. Do not place signing or notary credentials in the repository.

Sandbox permissions are in `Resources/Lokanow.entitlements`. Production builds enable hardened runtime. The UI test target disables hardened runtime only for its ad-hoc test runner; this does not change the shipped app's entitlements.

Before distribution, verify token save/read/disconnect against a real account, project/branch access, Arabic/region mappings on representative projects, and the release app on each supported macOS version and architecture. Run the release's first-launch flow after signing, because Keychain identity follows signing identity.
