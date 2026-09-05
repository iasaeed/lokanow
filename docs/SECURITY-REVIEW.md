# Local security review

Reviewed 2026-09-05. Changes included in version 1.0.2.

## Fixes

- File transactions reject Git metadata, operation metadata, symlink paths, broken links, and nonregular destinations. Backup locks use no-follow mode and verify ownership and file type.
- Recovery validates the selected project and every destination. A private SHA-256 receipt stored outside the repository must match the exact journal bytes before undo or recovery. This prevents an imported or modified project journal from authorizing recovery writes.
- Backup and application-data directories use owner-only permissions. Journal and cache files use owner-only read/write permissions.
- API sessions disable persistent URL caching, cookies, and automatic credential storage. HTTPS is required, and cross-origin redirects are rejected.
- Nonfinite Retry-After values cannot reach integer delay conversion. Installer redirects are restricted to HTTPS.

## Compatibility

Existing journals created before this change have no private trust receipt. Automatic undo and recovery for those journals are blocked, and their backup contents are preserved for manual review. Moving a project or losing its local receipt also requires manual recovery. A crash between updating the receipt and journal fails closed rather than trusting mismatched data.

## Remaining limits

- This is a focused source review and regression testing, not an independent penetration test or security certification.
- Cached translations and backup content are not application-encrypted. File permissions and macOS account/container protections do not defend against malware running as the same user or an administrator. Receipt checks have the same trust boundary.
- File checks reduce static path attacks but do not eliminate every race with a process changing directory entries during an operation. Do not apply changes in a workspace concurrently modified by an untrusted process.
- Very large or adversarial source files and API payloads may exhaust memory. Parser fuzzing and resource-exhaustion isolation have not been performed.
- No notarized binary is currently distributed. The source installer trusts GitHub, the selected source tag, Xcode, and the pinned SwiftSyntax dependency. Notarization is not a substitute for code review.

## Dependencies and evidence

SwiftSyntax is pinned to 602.0.0 and its resolved commit. The upstream GitHub repository security-advisory API returned no published advisories on the review date; that is not proof of no vulnerabilities.

Regression cases cover Git aliases, broken links, special files, linked backup paths and locks, foreign and tampered journals, normal undo/recovery, session privacy, HTTPS enforcement, redirects, and malformed retry headers.

Apple documents ephemeral sessions as avoiding persistent caches, cookies, and credentials: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral
