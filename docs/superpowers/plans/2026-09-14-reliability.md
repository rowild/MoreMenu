# MoreMenu Reliability Implementation Plan

> Execute inline with the executing-plans and test-driven-development skills. The user authorized the review recommendations on 2026-09-14, excluding Desktop-specific work.

**Goal:** Preserve authorization across launches and upgrades, prevent accidental overwrites, and make the existing Finder workflow testable.

**Architecture:** Compile a small Shared source folder into the host and extension. It owns document metadata, preferences, file creation, and home-directory policy. Keep Finder callbacks and file presentation in the extension; keep SwiftUI in the host. Use the existing Apple Development team with a macOS Team-ID-prefixed App Group. Migrate only the two known preferences through a signed host import command during local installation.

**Tech stack:** Swift 5, SwiftUI/AppKit, Foundation, FinderSync, Swift Testing, Xcode, zsh, Python 3 build tooling. No third-party runtime dependencies.

**Spec:** Review findings and user authorization in this conversation; verified Apple references below.

## Constraints

- macOS 14, 15, and 26 remain supported.
- Desktop-specific menu investigation and fixes are deferred.
- Preserve file types, titles, default selections, filename numbering, and opening newly created files.
- Keep filtered home-subfolder monitoring; assign directoryURLs once at extension initialization.
- Do not expand file-access entitlements, reset TCC, install, restart Finder, or publish as part of code validation.
- Use one certificate-backed team identity; reject ad-hoc install/release builds.
- Preserve old preference data, migrate only missing new preferences, and never repeatedly access the legacy group from the sandboxed extension.

## Phase 1 — Shared contracts and behavioral coverage

Files: Shared/DocumentKind.swift, Shared/MenuPreferences.swift, MoreMenu/SettingsStore.swift, ContentView.swift, project.pbxproj, MoreMenuTests/MoreMenuTests.swift.

- [x] Add tests for default/disabled/unknown file types, cross-instance preferences, and idempotent legacy import.
- [x] Run tests and record the expected missing-symbol failures.
- [x] Extract the existing 19 file types into a single DocumentKind catalog used by both targets.
- [x] Introduce MenuPreferences(defaults:), with isMenuEnabled, enabledKinds, setEnabled(_:for:), and importLegacySettings(_:) APIs. No fallback to process-private defaults.
- [x] Move observable settings ownership to the app so multiple windows share state; label checkboxes for accessibility.
- [x] Run tests, review the diff.

## Phase 2 — Safe creation and target resolution

Files: Shared/DocumentFileCreator.swift, Shared/HomeDirectoryScope.swift, Shared/TargetDirectoryResolver.swift, FinderSync.swift, MoreMenuTests/FileCreationTests.swift, FinderSyncInvariantTests.swift.

- [x] Add tests for existing-file preservation, simultaneous creators, numbering, valid RTF, failed writes, directory/file targets, unavailable targets, and excluded monitored roots.
- [x] Use exclusive Data.write(options: .withoutOverwriting), retry only CocoaError.fileWriteFileExists, propagate other errors.
- [x] Extract the current monitored-directory policy and exercise its results against temporary filesystem fixtures.
- [x] Reject unknown directory metadata instead of selecting its parent. Preserve the existing Desktop fallback without expanding it.
- [x] Add actionable file-creation error feedback. Keep Finder integration small and use the shared catalog/preferences.
- [x] Run behavioral tests and compile both targets.

## Phase 3 — Authorization, migration, installation

Files: both entitlements, Shared/MenuPreferences.swift, MoreMenuApp.swift, scripts/build-app.sh, build-release-dmg.sh, install-local.sh, verify-signing.py, export-legacy-settings.py and script tests.

- [x] Set both targets' group to QN24ZH7M6W.GMX.MoreMenu; use the same suite in code.
- [x] Add a host import command accepting validated JSON settings through arguments. Import only missing preferences and reject invalid input. Use modern UserDefaults write semantics; live validation showed synchronize() can return false even when the group data was saved.
- [x] Export the two known legacy preferences from the verified old group plist; never delete old settings.
- [x] Separate building/signing from DMG packaging. Require a certificate-backed signature for the expected team, verify the app and nested extension, preserve hardened runtime.
- [x] Stage and verify installation before replacing the old bundle, retain rollback on failure, remove unconditional TCC resets and blanket defaults deletion, import preferences before restarting Finder.
- [x] Validate scripts in temporary fixtures and inspect a signed build without installing it.

## Phase 4 — CI, documentation, final verification

Files: scripts/test.sh, .github/workflows/checks.yml, release.yml, README.md, DEVELOPER.md, CHANGELOG.md and current agent instructions.

- [x] Run macOS unit tests and script checks in CI; prevent automatic publication of ad-hoc packages.
- [x] Replace the obsolete settings deep link with the FinderSync management API.
- [x] Document the verified group-authorization cause, migration behavior, signing requirements, deferred Desktop work, and release/restart QA.
- [x] Build Debug/tests and signed Release; run all behavioral and script checks; review the final diff and record remaining live-system validation.

## Verified references

- https://developer.apple.com/documentation/xcode/accessing-app-group-containers — Team-ID-prefixed groups can be authorized by the matching signer without a provisioning profile.
- https://developer.apple.com/forums/thread/721701 — unapproved group access consent applies to one running instance.
- https://developer.apple.com/documentation/foundation/nsdata/writingoptions/withoutoverwriting — exclusive creation; cannot combine with atomic.
- https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html — Finder callbacks and target URL lifetimes.
- https://developer.apple.com/documentation/findersync/fifindersynccontroller — extension-management interface.

## Validation record

Initial review: existing app/test targets built; four existing unit tests passed (three source-shape checks and one placeholder). Today's installed 1.2.1 logs reject group.GMX.MoreMenu despite Apple Development signing. No source modifications existed before this task; .serena/ was already untracked.


Completed on branch `codex/reliability-improvements`:

- Red/green verification: new Swift contracts initially failed with missing symbols; new script tests initially failed for missing tooling. The notarization regression reproduced the missing custom-keychain argument before its fix.
- 15 Swift tests passed in 3 suites on macOS 26.6.2 / Xcode 26.6, with the host and extension compiling through the shared scheme. The concurrent-creation test creates 32 distinct files without overwriting existing data.
- 11 Python script tests passed, including retained settings, rejected signing configurations, failed-import rollback, failed-enablement rollback, fresh-install cleanup, and both notarization submissions using the configured keychain.
- A universal Release app was built and signed with the existing Apple Development identity. Both products passed strict signature, hardened-runtime, Team ID, and exact entitlement validation.
- Repeated launches of the signed host's import command succeeded. Container-manager logs approved the new Team-ID-prefixed group. The new group plist preserves the existing seven selected formats and master switch; the old plist remains intact.
- A local signed `MoreMenu-v1.2.2.dmg` was generated under `/tmp/moremenu-review-artifacts`; `hdiutil verify` reported a valid checksum.
- Independent review of migration, installation, signing, and CI found a custom notarization-keychain mismatch. It was fixed and covered by a failing-then-passing regression test.
- Shell syntax, workflow YAML parsing, and `git diff --check` passed.
- No installed app was replaced, no Finder restart or TCC reset was performed, and no release was published. Registered Finder extensions remain the same three pre-existing copies. Live import validation populated only the new shared-settings domain.

Subsequent user-authorized installation on 2026-09-14: copied the verified DMG into `dist/MoreMenu-v1.2.2.dmg` and ran `scripts/install-local.sh` successfully. The installed app reports 1.2.2, the seven selected formats and master switch were preserved, and Finder was restarted. `pluginkit` reports only the installed 1.2.2 extension registered and enabled. No TCC reset was performed.

Remaining manual validation: reboot behavior, Finder error-dialog/settings-button behavior on macOS 14/15/26, and public notarization with configured Developer ID credentials. Desktop-background work remains deferred. Code and build validation do not establish that every macOS privacy prompt is eliminated.
