# Developer Notes

This file keeps the build, architecture, and troubleshooting details out of the main README.

## Repository Layout

```text
MoreMenu/
├── MoreMenu/               Host app with the settings UI
│   ├── ContentView.swift
│   └── MoreMenu.entitlements
├── MoreMenuExtension/      Finder Sync Extension
│   ├── FinderSync.swift
│   ├── Info.plist
│   └── MoreMenuExtension.entitlements
├── MoreMenu.xcodeproj
├── scripts/
│   ├── build-release-dmg.sh
│   └── install-local.sh
└── .claude/plans/
    ├── 0000_project-idea.md
    ├── 0001_bugs-and-fixes.md
    ├── 0002_the-solution.md
    └── 0004_new_research_on_rightclick_permission.md
```

## Local Build And Install

For local use on this Mac:

```bash
./scripts/install-local.sh
```

That script:

- builds the Release app
- signs the app and extension ad hoc
- copies the app to `~/Applications`
- registers the embedded Finder extension
- restarts Finder

For a distributable DMG:

```bash
./scripts/build-release-dmg.sh
```

Output:

```text
dist/MoreMenu-v<version>.dmg
```

## Signing Model

The project builds with `CODE_SIGNING_ALLOWED=NO` and then applies ad hoc signatures in the scripts. That avoids the "expired Apple Development provisioning profile" problem seen with Debug builds copied from DerivedData.

The current settings-based implementation also uses an App Group:

```text
group.GMX.MoreMenu
```

That App Group is used only for shared preferences between the host app and the Finder Sync extension.

## Architecture

### Host App

The app is not just a placeholder anymore. It now provides:

- a master toggle for hiding or showing MoreMenu commands in Finder
- a checkbox list of supported file types
- the link to the Finder Extensions settings page

The host app stores those preferences in shared `UserDefaults` via the App Group.

### Finder Sync Extension

The extension:

- receives Finder context-menu requests
- resolves the target directory
- reads enabled file types from the shared App Group defaults
- creates the file
- opens the new file with the default handler

### Why The App Group Exists

The app and the extension are separate processes. The App Group is the clean mechanism for sharing simple settings such as:

- whether MoreMenu should show commands at all
- which file types are enabled

## File Creation Notes

The extension writes files directly with:

```swift
try kind.initialContents.write(to: candidate, options: .atomic)
```

### How the sandbox permits writes inside the user's home

Required entitlements on the extension (in addition to `app-sandbox` and `application-groups`):

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/</string>
</array>
```

The leading `/` in the path array is not the filesystem root — it is the home root. This grants the extension the sandbox capability to write anywhere under `~/`. Writes outside the home (e.g. `/Volumes/<drive>`) will be denied by the sandbox and surface as a logged error plus `NSSound.beep()`.

This build intentionally does **not** use `temporary-exception.files.absolute-path.read-write = /`. That broader entitlement works correctly under Developer ID / App Store signing (it's what FiScript ships with), but under this project's current ad-hoc signing on macOS Tahoe 26.4 it cannot produce a stable TCC code requirement — which causes a re-prompt on every reinstall and unreliable `menu(for:)` dispatch on `/Volumes/*`. See [0004_new_research_on_rightclick_permission.md](.claude/plans/0004_new_research_on_rightclick_permission.md) §11–§12 for the full evidence (TCC.db dumps, live log captures, cross-reference to FiScript's App Store build).

No security-scoped bookmarks, no `startAccessingSecurityScopedResource()`, no host/extension handoff. `.rtf` is special-cased to write a minimal valid rich-text payload; other supported file types start as empty files.

### The ad-hoc signing trade-off

Because the release DMG is ad-hoc-signed (`CODE_SIGNING_ALLOWED=NO` + `codesign --sign -` in the build scripts), TCC cannot remember the "Allow" decision across reinstalls. Every fresh install produces a new CDHash, the stored `csreq` in `~/Library/Application Support/com.apple.TCC/TCC.db` fails to match, and TCC re-prompts. This is not an entitlement bug — it is how TCC is designed to behave when no stable certificate chain anchors the requirement.

Silent TCC persistence across reinstalls requires a Developer ID signature. Plan 0004 §12.4 describes the upgrade path.

## Monitored Directory Invariant (READ BEFORE TOUCHING `FinderSync.init()`)

`FIFinderSyncController.default().directoryURLs` **must** be set to exactly:

```swift
[URL(fileURLWithPath: "/")]
```

Registering a user-home path (`/Users/<user>`) — or any path that transitively covers `~/Library/Containers/` — causes macOS Sonoma (14+) to classify the extension as observing *other apps'* Container data. That triggers the **App Management** consent prompt (`"MoreMenu.app would like to access data from other apps…"`) every time *any* sandboxed app is launched, and also suppresses the right-click menu items until consent is granted.

The filesystem-root `"/"` registration is a Finder Sync special mode that macOS treats as "call me for any local folder Finder shows" and is **not** classified as cross-app data access.

This invariant is pinned by [`MoreMenuTests/FinderSyncInvariantTests.swift`](MoreMenu/MoreMenuTests/FinderSyncInvariantTests.swift). If those tests start failing after a refactor, the correct response is to restore the invariant, not to update the tests.

## Manual QA Protocol Before Each Release

Automated tests cannot fully exercise the sandbox + Finder + App Management interaction. Run all of these on a fresh install before cutting a release:

1. **Fresh install check**
   - `./scripts/install-local.sh` (or install the new DMG)
   - Open `System Settings → Privacy & Security → Extensions → Finder Extensions` and confirm `MoreMenu` is enabled

2. **Menu appears on every Finder surface inside the home folder**
   - Right-click on empty space inside a Finder window showing `~/Desktop` or any subfolder of `~/` → menu items present
   - Right-click on the Desktop → menu items present
   - Right-click on a selected file or folder inside `~/` → menu items present

3. **File creation works inside the home folder**
   - Create a `.txt`, `.md`, and `.rtf` file from each of the three surfaces above
   - Each file must open in its default app immediately

4. **Home-scope gate — menu items hidden outside `~/`**
   - Right-click in the following locations and confirm MoreMenu items do **not** appear at all:
     - filesystem root `/` (e.g. open a Finder window at `Macintosh HD`)
     - `/Applications`
     - `/Volumes/<any drive>`
     - `/Users/<other user>/*` (if another account exists)
     - `/tmp`
   - Right-click inside `~/Library/Containers/*` should still show items (this is under the home entitlement, even if it's a weird place to create files).
   - No crash, no beachball, no silent file creation attempts anywhere outside the home.

5. **App Management regression guard (release 1.1.5 → 1.1.6 fix)**
   - Fully quit `TextEdit` if it is running
   - Launch `TextEdit` from Applications or Spotlight
   - **There must be NO "MoreMenu.app would like to access data from other apps" prompt on `TextEdit` launch.** If that prompt appears, `directoryURLs` is wrong — see "Monitored Directory Invariant" above.
   - Repeat for `Markdown` editors, `Preview`, and any other app you can think of. None of them should trigger the prompt.

6. **First-install TCC prompt (ad-hoc signing trade-off, 1.2.1)**
   - `./scripts/install-local.sh` (which runs `tccutil reset SystemPolicyAppData` for both bundle IDs)
   - Quit `MoreMenu.app` if running
   - Launch `MoreMenu.app` from `~/Applications`
   - A single "MoreMenu.app would like to access data from other apps" prompt on launch is **expected** under ad-hoc signing. Click Allow.
   - After clicking Allow, the prompt must not re-fire during normal use of the same build. If it does re-fire *repeatedly during the same session*, capture `log stream --predicate 'subsystem == "com.apple.TCC"' --style compact` and consult [0004_new_research_on_rightclick_permission.md](.claude/plans/0004_new_research_on_rightclick_permission.md) §11–§12.
   - The prompt recurring on *each new install* is the accepted trade-off, not a regression.

If any of the above fails, DO NOT release. Capture `log stream --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'` output and investigate.

## Troubleshooting

### The menu does not appear

- confirm `MoreMenu` is enabled in:
  `System Settings -> Privacy & Security -> Extensions -> Finder Extensions`
- restart Finder:
  ```bash
  killall Finder
  ```
- verify registration:
  ```bash
  pluginkit -mAvvv -i GMX.MoreMenu.MoreMenuExtension
  ```
- if the registered path points to DerivedData instead of `~/Applications/MoreMenu.app`, run:
  ```bash
  ./scripts/install-local.sh
  ```

### The menu appears but no file is created

- Writes should succeed anywhere under `/` (outside SIP-protected paths) via the `temporary-exception.files.absolute-path.read-write` entitlement.
- Watch live extension logs:
  ```bash
  /usr/bin/log stream --style compact \
      --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'
  ```
- Common log signatures:
  - `Creating <ext> file in: <path>` followed by `Successfully created: ...` → write succeeded
  - `Failed to create file in <path>: ...` → sandbox denied the write. Confirm the extension really was rebuilt with `temporary-exception.files.absolute-path.read-write`:
    ```bash
    codesign -d --entitlements - "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
    ```
  - `No resolvable target directory for menu action` → `targetedURL()` returned nil and the AppleScript fallback did not find a Finder insertion location (usually because no Finder window is frontmost)

### The app does not launch

If you used a Debug build from DerivedData, you may be hitting an expired Apple Development provisioning profile. Reinstall the ad hoc local build:

```bash
./scripts/install-local.sh
```

## Notes On Failed Approaches

The full investigation history is kept here:

- [.claude/plans/0000_project-idea.md](.claude/plans/0000_project-idea.md)
- [.claude/plans/0001_bugs-and-fixes.md](.claude/plans/0001_bugs-and-fixes.md)
- [.claude/plans/0002_the-solution.md](.claude/plans/0002_the-solution.md)
- [.claude/plans/0004_new_research_on_rightclick_permission.md](.claude/plans/0004_new_research_on_rightclick_permission.md)

The short version:

1. Automator and Shortcuts do not solve the empty-space Finder menu problem.
2. Finder Sync is the correct extension point.
3. A sandboxed Finder extension cannot just write everywhere unless the entitlement model is correct.
4. Shared settings are best handled through an App Group, not improvised IPC.
5. Trying to implement external-drive access via security-scoped bookmarks inside the extension triggers macOS Tahoe's App Management TCC classifier. The correct fix is `temporary-exception.files.absolute-path.read-write = /`, matching FiScript — see plan 0004 for the full research.
