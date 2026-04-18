# Changelog

## 1.2.1 - 2026-04-18

### Changed

- **Extension entitlement narrowed from `temporary-exception.files.absolute-path.read-write = /` to `temporary-exception.files.home-relative-path.read-write = /`.** The extension can now write anywhere under the user's Home folder (Desktop, Documents, Downloads, any subfolder) but not to `/Volumes/*` external drives. `/Volumes/*` support under ad-hoc signing was not functioning silently on macOS Tahoe 26.4 and was therefore removed; reinstating it is a signing concern, not an entitlement concern. See notes below.
- **Menu items now hide in locations the sandbox cannot write to.** `menu(for:)` and `createDocument(_:)` gate on `isInsideUserHome(_:)`, which compares the target directory against the real user home (derived via `getpwuid(getuid())`, not `FileManager.default.homeDirectoryForCurrentUser`, since the latter returns the container home inside a sandboxed extension). Right-clicking in `/`, `/Applications`, `/Users/<other>`, `/tmp`, or any other out-of-scope location now shows no MoreMenu items at all, matching the existing `/Volumes/*` behaviour.
- `install-local.sh` now runs `tccutil reset SystemPolicyAppData` instead of `SystemPolicyAppBundles`. The 1.2.0 installer was resetting the wrong TCC service — the prompt text is shared between the two services but the service actually firing is `SystemPolicyAppData`. The reset does not prevent the prompt under ad-hoc signing (that requires a Developer ID), but it stops stale csreq rows from accumulating.

### Fixed

- **Corrected diagnosis of the "MoreMenu.app would like to access data from other apps" prompt recurring after every reinstall.** 1.2.0 attributed this to the legacy bookmark architecture and was wrong. Live log capture, `TCC.db` inspection, and a cross-reference against FiScript's App Store build confirmed the root cause: ad-hoc code signing produces a 40-byte `csreq` with no certificate authority clause, so TCC cannot match the stored authorization against a freshly re-signed binary on reinstall and re-prompts. FiScript uses identical entitlements (in fact broader) and does not exhibit this because Apple signs it with a stable Team ID.
- **Right-click menu items missing on `/Volumes/*` after 1.2.0 install.** Same root cause: ad-hoc signing causes `LSApplicationRecord` registration to fail for the `.appex` (`OSStatus -10811`), which in turn breaks Finder's menu dispatch for folders that need LS-validated extension records. Fix is removing `/Volumes/*` from the supported scope until the project moves to a Developer-ID signed build.

### Not Fixed (Documented Trade-off)

- **TCC prompt still appears on first launch after each reinstall.** This is structural to ad-hoc signing and cannot be eliminated by any code change in this repository. Plan 0004 §12.4 documents the Developer-ID upgrade path that would remove it.

### Notes

Full evidence — `codesign` outputs, `TCC.db` dumps, live `log stream` captures, FiScript source comparison, and the option matrix — is in [.claude/plans/0004_new_research_on_rightclick_permission.md](.claude/plans/0004_new_research_on_rightclick_permission.md) §0, §11, §12.

## 1.2.0 - 2026-04-17

### Removed

- **Authorized Folders** settings pane and all associated bookmark plumbing. The host app no longer opens `NSOpenPanel`, no longer mints security-scoped bookmarks, and no longer writes to `authorizedFolderRecords` / `sharedAuthorizedFolderEntries` in the App Group defaults. The extension no longer resolves minimal bookmarks, promotes them to local scoped bookmarks, caches them in its private `UserDefaults`, or calls `startAccessingSecurityScopedResource()` anywhere.
- `MoreMenu/AuthorizedFolderPolicy.swift` and `MoreMenuTests/AuthorizedFolderPolicyTests.swift` (no longer needed).

### Changed

- **Extension entitlements** replace the old `files.bookmarks.app-scope` + `files.user-selected.read-write` + `temporary-exception.files.home-relative-path.read-write` trio with a single `com.apple.security.temporary-exception.files.absolute-path.read-write = /`. This is the pattern used by FiScript (shipping on the Mac App Store with the same entitlement), and it grants the extension the sandbox capability to create files at any absolute path without any bookmark-minting step.
- **Host app entitlements** drop `files.bookmarks.app-scope` and `files.user-selected.read-write` — the host no longer touches user-selected folders at all.
- `install-local.sh` now purges leftover state from 1.1.5–1.1.7 on every install: the extension's private `UserDefaults` domain, the `authorizedFolderRecords` and `sharedAuthorizedFolderEntries` keys in the App Group, and the App Management TCC record for both bundle IDs.

### Fixed

- **App Management TCC prompt on launching MoreMenu.app and on right-clicks after adding an external folder.** The bookmark promotion flow that 1.1.5–1.1.7 ran on every invocation was the most likely trigger of macOS Tahoe's `kTCCServiceSystemPolicyAppBundles` classifier. Removing the entire bookmark code path removes the trigger.
- **External-drive file creation now works directly.** Right-click on any `/Volumes/<drive>` folder creates the file with no authorization step. macOS may show a one-time "allow access to files on a removable volume" system prompt per volume on first use; that is a standard macOS prompt, not the App Management one.

### Notes

Full research and rationale: [.claude/plans/0004_new_research_on_rightclick_permission.md](.claude/plans/0004_new_research_on_rightclick_permission.md).

## 1.1.7 - 2026-04-17

### Fixed

- **App Management prompt re-fires on every right-click after authorizing an external folder** (e.g. `/Volumes/Work/`). Root cause: the host app called `startAccessingSecurityScopedResource()` on the picked URL twice — once to mint the persistent bookmark (redundant with the NSOpenPanel grant) and once more in `refreshAccessCache()` immediately after. Starting scope on a volume-root path re-triggers macOS's App Management TCC classifier until a decision is recorded; until the user clicks Allow, the prompt reappears on the next user-visible surface — which is typically a Finder right-click firing the extension.
- **External-drive file creation silently broken.** When the TCC prompt was dismissed (or denied), subsequent `startAccessingSecurityScopedResource()` calls in both the host and the extension failed silently, making external-folder flows look non-functional.

### Changed

- `AuthorizedFolderRecord` now caches the `.minimalBookmark` (for App Group sharing) alongside the `.withSecurityScope` bookmark. Both are minted once, during the single NSOpenPanel grant in `addFolders()`, and reused from that point on.
- `refreshAccessCache()` no longer re-enters security scope on every invocation. It only sanitizes stored records against the rejection policy and re-syncs shared entries from cached bookmarks. Legacy records from 1.1.5/1.1.6 migrate by reading their minimal bookmark from the existing shared App Group entries — a pure data copy, no scope entry, no TCC prompt.
- `install-local.sh` now also clears stale registrations from `/private/tmp/moremenu-build` (the release-build temp dir) and `.build`, not only DerivedData.

## 1.1.6 - 2026-04-17

### Fixed

- **App Management prompt on every app launch.** Release 1.1.5 registered the real user home (and any authorized folders) as the Finder Sync extension's `directoryURLs`. That path transitively covers `~/Library/Containers/<other apps>/`, which made macOS Sonoma classify MoreMenu as a cross-app data observer and trigger the "MoreMenu.app would like to access data from other apps" prompt every time another sandboxed app (e.g. TextEdit) was launched. The extension now registers only `[URL(fileURLWithPath: "/")]`, which is a Finder Sync special mode that is *not* classified as cross-app access. See [DEVELOPER.md](DEVELOPER.md#monitored-directory-invariant-read-before-touching-findersyncinit) for the full invariant.
- **Right-click menu items disappeared.** Same root cause: the App Management gate suppressed the extension's `menu(for:)` callbacks until the prompt was granted, so users saw no MoreMenu items in Finder.

### Added

- Unit-test coverage for the `AuthorizedFolderPolicy` rejection rules (`MoreMenuTests/AuthorizedFolderPolicyTests.swift`).
- Source-level invariant guard: `MoreMenuTests/FinderSyncInvariantTests.swift` pins the `directoryURLs = [URL(fileURLWithPath: "/")]` contract so a future refactor cannot silently reintroduce the 1.1.5 regression.
- Manual QA protocol in `DEVELOPER.md` covering the App Management prompt, menu-appearance check, and rejection-policy smoke test.

### Changed

- `AuthorizedFoldersStore.rejectionReason` now delegates to a pure, testable `AuthorizedFolderPolicy` type.

## 1.1.5 - 2026-04-17

### Added

- Authorized Folders pane in the host app for granting MoreMenu access to external drives and other locations outside the user's home folder. The host stores a security-scoped bookmark for the picked folder and writes a minimal bookmark into the shared App Group for the extension.
- Extension-side two-step bookmark promotion: the Finder Sync extension resolves the shared minimal bookmark with `.withoutUI`, mints its own `.withSecurityScope` bookmark in its private `UserDefaults`, and reuses that cached bookmark on subsequent invocations. Works around the Code 259 failure documented in Apple dev-forum 66259 when passing security-scoped bookmarks through an App Group.
- Selection validation in the Add Folder panel. System roots (`/`, `/Users`, `/Volumes`, `/System`, `/Library`, `/private`) and paths inside the real user home are rejected with a short reason; stale records that fall into these buckets are purged on launch.

### Changed

- Finder Sync extension entitlements now include `com.apple.security.files.bookmarks.app-scope` and `com.apple.security.files.user-selected.read-write`. Without these the extension could not resolve bookmarks at all and the sandbox denied writes to `/Volumes/...`.
- Extension now derives the real user home via `getpwuid(getuid())` instead of `FileManager.default.homeDirectoryForCurrentUser`. Inside a sandboxed extension the latter returns the container's home (`…/Library/Containers/<bundle id>/Data`), which broke the home fast-path and routed ordinary `~/Desktop` writes through the bookmark flow.
- `FIFinderSyncController.directoryURLs` is now registered with the real user home plus any authorized folders, so macOS calls the extension for the locations it is actually authorized to work in.

### Fixed

- New-file items appeared in Finder on external drives but no file was created. Resolved by the entitlement additions, the real-home fix, and the two-step bookmark promotion described above.
- Stale authorized-folder records for unreachable system paths no longer cause repeating `Could not open() the item` errors; they are silently filtered out during `refreshAccessCache`.

## 1.1.4 - 2026-04-16

### Added

- Settings-driven file-type picker in the host app, including optional web and framework-oriented file types such as `JSX`, `TSX`, and `Vue`.
- Shared App Group preferences so the host app can control which MoreMenu commands the Finder extension shows.
- `DEVELOPER.md` for build, release, architecture, and troubleshooting notes.
- End-user screenshots in `README.md` for the Finder menu and the settings window.

### Changed

- README rewritten as an end-user guide with screenshots and usage-focused wording.
- Historical plan references now point to `.claude/plans/`.

## 1.1.3 - 2026-04-16

### Added

- Finder menu items for `untitled.md` and `untitled.rtf`, alongside the existing plain-text item.

### Changed

- Menu icons are now rendered as fixed white symbols for consistent visibility in Finder menus.
- Rich-text creation now writes a minimal valid RTF payload instead of creating a zero-byte `.rtf` file.
- Finder menu actions now use dedicated selectors per file type instead of relying on `representedObject`, which fixed Tahoe builds where clicks reached the extension but no file was created.
- Documentation now states explicitly that Finder Sync is an app extension, so the separate macOS System Extensions security flow is not relevant to MoreMenu.

## 1.1.2 - 2026-04-16

### Added

- Local installer script (`scripts/install-local.sh`) — builds the ad hoc Release app, installs it to `~/Applications`, registers the Finder extension from the installed app, removes stale DerivedData registrations, and restarts Finder.

### Changed

- Removed obsolete bookmark/folder-access UI from the host app. The extension no longer uses security-scoped bookmarks.
- Trimmed unused host-app entitlements (`application-groups`, `files.user-selected.read-write`, `files.bookmarks.app-scope`) and removed unused `files.user-selected.read-write` from the extension.
- README now recommends the ad hoc local install flow instead of installing Xcode Debug builds from DerivedData, which can expire with Apple Development provisioning profiles.
- Lowered the extension deployment target from macOS `14.8` to `14.0`, so the installed app and the Finder extension now both target macOS 14 Sonoma and later.

## 1.1.1 - 2026-04-12

### Added

- GitHub Actions release workflow (`.github/workflows/release.yml`) — pushing a `v*` tag now automatically builds a release DMG and publishes it as a GitHub Release.
- Build script (`scripts/build-release-dmg.sh`) — produces a distributable DMG via ad hoc code signing. No Apple Developer certificate required to build; users on other Macs will need to approve the app on first launch via System Settings → Privacy & Security → Open Anyway.

### Changed

- `.gitignore` extended to exclude generated build artefacts: `.build/` (derived data used by the release script) and `dist/` (output DMG location).

## 1.1 - 2026-04-10

### Fixed

- File creation now works correctly in sandboxed builds. Added `com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement to `MoreMenuExtension` so that the extension can write to arbitrary paths inside the user's home directory.
- Right-clicking directly on a file or folder now creates the new text file in the same containing directory, rather than failing silently.

### Changed

- `FinderSync.swift` refactored: target directory resolution consolidated into a single helper, duplicate-name logic moved to a dedicated function.
- `ContentView.swift` updated with clearer setup instructions and live extension-status feedback.
- `MoreMenu.entitlements` and `MoreMenuExtension.entitlements` updated to reflect the correct sandbox permissions.
- README rewritten: shorter install section, corrected extension-registration commands, added Troubleshooting section.

## 1.0 - 2026-04-07

### Added

- Initial release.
- Finder Sync Extension (`MoreMenuExtension`) adds a **New Textfile** item to Finder's right-click context menu — works on empty window space, the Desktop, and directly on files or folders.
- Auto-increments filename: `untitled.txt` → `untitled_0001.txt` → `untitled_0002.txt`, etc.
- Opens the newly created file immediately with the system default `.txt` handler.
- Host app (`MoreMenu`) shows a setup guide on first launch.
