# Developer Notes

## Build and test

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/install-local.sh
```

`test.sh` runs script tests and standalone macOS unit tests. The tests compile the same Shared sources as the app and extension, without launching the host app or running the installer. The shared Xcode scheme also builds the app and extension to catch integration errors. Xcode 16.2 or later is required; the deployment target remains macOS 14.

`build-app.sh` builds a universal Release app, signs the extension before its containing app, and verifies both signatures and entitlement sets. By default it selects an available Apple Development identity. Override with `MOREMENU_CODE_SIGN_IDENTITY`. It rejects ad-hoc signatures and signing teams that do not match the App Group. No app is installed by this command.

`install-local.sh` builds the app without generating a DMG, verifies a staged copy, exports the two legacy preferences, and replaces `~/Applications/MoreMenu.app`. The previous bundle is retained until settings import and extension registration succeed; failure restores it. It then unregisters old development copies, registers the installed extension, enables it, and restarts Finder. It neither resets TCC nor deletes preference domains. `MOREMENU_INSTALL_DIR`, `MOREMENU_LEGACY_PREFERENCES`, and `DERIVED_DATA_PATH` support isolated installer tests and custom local paths.

Build/test output is under `.build/` by default. `MOREMENU_TEST_DERIVED_DATA` overrides the test output location.

## Architecture

- `MoreMenu/Shared/DocumentKind.swift`: the 19 persistent file-type identifiers, UI/menu titles, extensions, categories, and initial contents.
- `Shared/MenuPreferences.swift`: the shared defaults contract and idempotent legacy import.
- `Shared/DocumentFileCreator.swift`: exclusive filename creation with numbered retries.
- `Shared/HomeDirectoryScope.swift`: home-boundary and monitored-directory policy.
- `Shared/TargetDirectoryResolver.swift`: file-versus-folder resolution; failed metadata reads propagate as errors.
- `MoreMenu/SettingsStore.swift`: observable settings shared by all settings windows.
- `MoreMenuExtension/FinderSync.swift`: Finder callbacks, target acquisition, menu presentation, file opening, and error feedback.

The Shared folder is compiled into both products and the standalone unit-test target. It is not a new runtime framework or service.

## Authorization: three separate concerns

### App Group membership

Both products use `QN24ZH7M6W.GMX.MoreMenu`, where `QN24ZH7M6W` is the signing Team ID. This macOS-style group is authorized by a matching certificate-backed signature without requiring a provisioning profile. The sandbox entitlements include exactly that group. `MenuPreferences` uses the same suite and never silently falls back to private defaults.

Apple also supports `group.` identifiers, but those require provisioning authorization. The old build used `group.GMX.MoreMenu` without authorizing profiles. On 2026-09-14, the installed Apple-Development-signed 1.2.1 app logged:

> Requestor's signature does not allow it to access a TCC-protected group container.

A subsequent `SystemPolicyAppData` prompt was associated with the current extension process. Apple's documented approval for unauthorized group-container access lasts only for that app instance. This explains why changing the signing certificate alone did not fix repeated prompts. Narrowing Finder monitoring does not authorize an App Group.

Sources: [App Group authorization](https://developer.apple.com/documentation/xcode/accessing-app-group-containers), [Apple DTS explanation of per-instance consent](https://developer.apple.com/forums/thread/721701).

### Sandbox write capability

The extension retains `com.apple.security.temporary-exception.files.home-relative-path.read-write = ["/"]`. In this entitlement, `/` means the user's home. The host has no broad file-write entitlement. External volumes remain out of scope. This task does not expand write capability or add Apple Events permissions.

### Folder privacy and Finder monitoring

Sandbox capability does not override macOS privacy decisions. Normal folder-access permissions and App Group authorization must be diagnosed separately.

Finder monitoring remains limited to visible top-level home subfolders, excluding `Library`, `Applications`, and packages. Set `directoryURLs` exactly once at extension initialization, using `HomeDirectoryScope.monitoredDirectoryURLs()`. Keep this conservative policy; the old notes attributing every AppData prompt to monitoring scope are not sufficient evidence to change it.

`FinderSyncInvariantTests` exercises the actual folder-selection policy against temporary filesystem fixtures and retains one structural guard for the single registration assignment.

## Preference migration

The old preferences reside at:

```text
~/Library/Group Containers/group.GMX.MoreMenu/Library/Preferences/group.GMX.MoreMenu.plist
```

The local installer reads this file outside the sandbox and validates only `finderMenuEnabled` (Boolean) and `enabledDocumentKeys` (string array). It passes JSON as one argument to the signed host:

```text
MoreMenu.app/Contents/MacOS/MoreMenu --import-legacy-settings <JSON>
```

The host decodes the entire payload before writing, filters unknown document identifiers, imports only missing new preferences, and exits without opening a window. Empty and repeated imports make no changes. Modern UserDefaults enqueues writes before `set` returns; the importer does not call the unnecessary `synchronize()` API, which reported failure for unrelated search domains during live validation. See [Foundation release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/foundation-release-notes). It never accesses the legacy group. Old data is retained for rollback; an invalid payload aborts installation. A manual DMG install does not invoke the local migration command.

## File safety

`Data.write(options: .withoutOverwriting)` claims the final name in the write operation. Only `CocoaError.fileWriteFileExists` advances to the next name. Permission, storage, and missing-directory failures propagate instead of retrying indefinitely. Do not combine `.withoutOverwriting` with `.atomic`: Apple documents these options as incompatible.

Files use `untitled.ext`, `untitled_0001.ext`, and subsequent numbers. Rich text has a minimal valid RTF payload; other types are initially empty. Failed target metadata lookup must never select a parent directory as a guessed fallback.

[Apple's exclusive-write documentation](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/withoutoverwriting)

## Desktop work is deferred

Desktop background and cloud-managed Desktop behavior are explicitly outside this patch. The existing AppleScript insertion-location fallback is retained; its missing Apple Events sandbox authorization is a known limitation, not a supported Desktop guarantee. Do not broaden monitored roots or add automation entitlements as part of these reliability fixes.

For the later investigation, log whether Finder calls `menu(for:)`, the menu kind, and whether a target URL exists. Distinguish callback suppression from MoreMenu returning an empty menu before proposing a fix.

## Settings navigation

The app uses `FIFinderSyncController.showExtensionManagementInterface()` instead of an undocumented, hard-coded System Settings URL. Verify the resulting UI on each supported macOS version. Apple's current guide places extensions under General → Login Items & Extensions; older versions differ.

Sources: [Finder Sync controller](https://developer.apple.com/documentation/findersync/fifindersynccontroller), [current System Settings guide](https://support.apple.com/en-ca/guide/mac-help/mtusr003/mac).

## Release packaging

For a local signed DMG:

```bash
./scripts/build-release-dmg.sh
```

For public distribution, set `MOREMENU_CODE_SIGN_IDENTITY` to the configured team's Developer ID Application identity, `MOREMENU_DISTRIBUTION=1`, and `MOREMENU_NOTARY_PROFILE` to an existing `notarytool` keychain profile. The script notarizes/staples the app, packages it, then notarizes/staples the DMG. This requires distribution credentials; a local Apple Development signature is not a notarized public release.

If the profile is stored in a custom file keychain, also set `MOREMENU_NOTARY_KEYCHAIN` to that keychain's path. CI supplies its temporary keychain explicitly to both submissions; `notarytool` otherwise uses the data-protection keychain. See [Apple TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool).

Output: `dist/MoreMenu-v<CFBundleShortVersionString>.dmg`. Release tags must match that version. Packaging uses a temporary staging directory cleaned on exit.

GitHub's tag workflow runs tests before signing and publishing. Configure these repository secrets for the signing team before publishing a tag:

- `MOREMENU_CERTIFICATE_P12`: base64-encoded Developer ID certificate and private key export.
- `MOREMENU_CERTIFICATE_PASSWORD`: export password.
- `MOREMENU_CODE_SIGN_IDENTITY`: full Developer ID Application identity name.
- `MOREMENU_NOTARY_APPLE_ID`: notarization Apple ID.
- `MOREMENU_NOTARY_PASSWORD`: app-specific password.

The workflow uses a temporary keychain and removes its signing material afterward. Missing credentials fail the release instead of publishing an ad-hoc app. No credentials or GitHub settings are provisioned by this patch.

## Validation before installing or releasing

1. Run `./scripts/test.sh`; include concurrent creation, preservation, RTF, settings migration, scope policy, signing rejection, and installer rollback checks.
2. Build and verify a signed app. Inspect both products' Team ID, App Group, sandbox entitlement, and hardened runtime.
3. After an actual local upgrade, confirm prior selections survive and only the intended installed extension is used.
4. Test file creation and errors inside supported Finder folders, and verify out-of-home locations have no commands.
5. Relaunch the host/extension and reboot. Confirm the logs authorize the group and the repeated AppData prompt does not return. A successful build or one launch does not establish reboot behavior.
6. Check the settings-management button and error dialog on macOS 14, 15, and 26 before claiming compatibility beyond compilation.

Useful read-only diagnostics:

```bash
pluginkit -mAvvv -i GMX.MoreMenu.MoreMenuExtension
codesign -dvv --entitlements :- "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
/usr/bin/log show --last 10m --style compact --info --predicate '(subsystem == "com.apple.containermanager" OR subsystem == "com.apple.TCC") AND eventMessage CONTAINS[c] "MoreMenu"'
```

Treat the pre-September 2026 research under `.claude/plans/` and earlier changelog diagnoses as historical. Today's installed-process evidence supersedes their claim that stable signing alone guarantees persistent AppData consent.
