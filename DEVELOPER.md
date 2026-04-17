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
    └── 0002_the-solution.md
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

### Home folder

Inside the user's real Home folder, writes succeed because of:

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/</string>
</array>
```

The real user Home is resolved via `getpwuid(getuid())` — `FileManager.default.homeDirectoryForCurrentUser` inside a sandboxed extension returns the container home (`…/Library/Containers/<bundle id>/Data`), which is not what the `home-relative-path` entitlement is evaluated against.

### External drives and non-home locations

Non-home writes use security-scoped bookmarks. The flow is two-staged because Apple does not support round-tripping a `.withSecurityScope` bookmark through an App Group (dev-forum 66259, Code 259 "not in the correct format"):

1. Host app: `NSOpenPanel` → creates a `.withSecurityScope` bookmark for its own records, plus a `.minimalBookmark` written to shared App Group defaults under `sharedAuthorizedFolderEntries`.
2. Extension: reads the minimal bookmark → resolves with `.withoutUI` → mints its own `.withSecurityScope` bookmark from the resolved URL → caches it in the extension's private `UserDefaults` keyed by authorized-parent path.
3. Extension: subsequent invocations resolve the cached local bookmark, call `startAccessingSecurityScopedResource()`, write, stop. Stale bookmarks auto-recover by triggering a re-promotion from the shared minimal bookmark.

Required entitlements on the extension (in addition to `app-sandbox` and `application-groups`):

```xml
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

`.rtf` is special-cased to write a minimal valid rich-text payload. The other supported file types currently start as empty files.

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

- Inside Home folder: writes should work via the `home-relative-path` entitlement.
- On external drives or outside Home: confirm you have authorized the parent folder under `MoreMenu.app` → `Authorized Folders`.
- Watch live extension logs:
  ```bash
  /usr/bin/log stream --style compact \
      --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'
  ```
- Common log signatures:
  - `accessNotGranted(...)` → no authorized-folder entry matches the target path
  - `Minting local scoped bookmark failed ...` → the authorized entry points at a path the sandbox cannot reach (usually a system root); remove it in `Authorized Folders`
  - `Creating <ext> file in: <path>` followed by no error → write succeeded

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

The short version:

1. Automator and Shortcuts do not solve the empty-space Finder menu problem.
2. Finder Sync is the correct extension point.
3. A sandboxed Finder extension cannot just write everywhere unless the entitlement model is correct.
4. Shared settings are best handled through an App Group, not improvised IPC.
