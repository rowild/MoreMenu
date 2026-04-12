# MoreMenu

`MoreMenu` is a small macOS app that adds a `New Textfile` item to Finder's right-click context menu.

When you use it, the app:

- creates `untitled.txt` in the current Finder location
- automatically chooses `untitled_0001.txt`, `untitled_0002.txt`, and so on if a file with that name already exists
- opens the created file immediately with the default app for `.txt` files

## What problem it solves

macOS does not include a built-in "New Text File" item in Finder's context menu.

This app adds that missing command when you right-click:

- empty space inside any Finder window
- empty space on the Desktop
- a file or folder (the new file is created in the same directory)

## Requirements

- macOS 14 Sonoma, macOS 15 Sequoia, or macOS 26 Tahoe
- Xcode and an Apple ID configured in Xcode for building

For everyday use of an already-built app, Xcode is not required.

## Project structure

```
MoreMenu/
├── MoreMenu/               Host app (setup UI and extension container)
│   ├── ContentView.swift   Setup guide shown on first launch
│   └── MoreMenu.entitlements
├── MoreMenuExtension/      Finder Sync Extension
│   ├── FinderSync.swift    All extension logic — menu, target resolution, file creation
│   └── MoreMenuExtension.entitlements
└── MoreMenu.xcodeproj
plans/
├── 0001_bugs-and-fixes.md  Full bug audit and fix log
└── 0002_the-solution.md    Complete post-mortem: every approach tried and why each worked or failed
```

## How to build and install

### In Xcode

1. Open `MoreMenu/MoreMenu.xcodeproj`.
2. In `Signing & Capabilities`, select your Apple team for both the `MoreMenu` and `MoreMenuExtension` targets.
3. Choose `Product > Build` (or press `Cmd+B`).

### Install and register

After a successful build, run these commands in Terminal:

```bash
# Remove any previous copy
rm -rf ~/Applications/MoreMenu.app

# Copy the fresh build
cp -R ~/Library/Developer/Xcode/DerivedData/MoreMenu-*/Build/Products/Debug/MoreMenu.app \
      ~/Applications/MoreMenu.app

# Register and enable the extension
pluginkit -a "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
pluginkit -e use -i GMX.MoreMenu.MoreMenuExtension

# Restart Finder
killall Finder
```

### Enable in System Settings

1. Open `System Settings → Privacy & Security → Extensions → Finder Extensions`.
2. Enable `MoreMenu`.

That is all that is required.  There is no folder-access setup step needed.

## How to use it

Right-click anywhere in Finder — empty space in a window, the Desktop, or directly on a file — and choose `New Textfile`.

A new `untitled.txt` is created in that location and opened immediately.

## Can it run on another Mac?

### Build on the other Mac

The simplest reliable method: open the project in Xcode on the other Mac with a valid Apple ID, build, and install using the commands above.

### Shareable release

For distributing to people who should not need to build it themselves, create a proper release build:

- sign with Developer ID
- notarize with Apple

Without notarization, Gatekeeper on the other Mac will block the first launch.  The user can override this via `System Settings → Privacy & Security → Open Anyway`, but that is an extra friction step.

## Troubleshooting

### The menu item does not appear

- Confirm the extension is enabled in `System Settings → Privacy & Security → Extensions → Finder Extensions`.
- Restart Finder: `killall Finder` in Terminal.
- Verify the extension is registered: `pluginkit -mAvvv -i GMX.MoreMenu.MoreMenuExtension`
  The `Path` line should point to `~/Applications/MoreMenu.app/...`, not DerivedData.
- If it points to DerivedData, re-run the install commands above.

### The menu item appears but no file is created

- Check that you are working inside your home directory (`~/`).
  The extension has write access to your entire home directory tree.
  It does not have access to volumes or directories outside `~`.

### The file is not opened automatically

The app uses the default system handler for `.txt` files.  Check the default app assigned to `.txt` on your system.

### Watching live logs

```bash
/usr/bin/log stream --style compact \
    --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'
```

## Notes

- This app uses a Finder Sync Extension because Automator and Shortcuts do not support adding custom items to Finder's empty-space context menu.
- File creation uses the `com.apple.security.temporary-exception.files.home-relative-path.read-write` entitlement, which grants the sandboxed extension direct write access to the user's home directory — no bookmarks or IPC with the host app are needed.

## License

No license file is included yet.

---

## Developer notes

### How file creation works

The extension is sandboxed.  It writes files directly using:

```swift
try "".write(to: candidate, atomically: true, encoding: .utf8)
```

This is possible because of a single entitlement in `MoreMenuExtension.entitlements`:

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/</string>
</array>
```

This grants the extension read-write access to the user's entire home directory (`~/`).
Despite the word "temporary" in the key name, this is a stable entitlement available
since macOS 10.10 and still supported today.

### Approaches that do not work

Three other mechanisms were tried before finding the above solution.  All three fail:

1. **Direct `FileManager` / `Data().write()`** without the entitlement — EPERM.
2. **Security-scoped bookmarks passed from the host app via App Group** —
   `startAccessingSecurityScopedResource()` always returns `false` in the extension
   process because security-scoped bookmarks are bound to the creating app's bundle ID
   and cannot activate their scope in a different sandboxed process.
3. **AppleScript `make new file at` delegated to Finder** — fails with
   `Finder got an error: Application isn't running` from a sandboxed extension, even
   though read-only Apple Event queries to Finder (e.g. asking for the insertion
   location) succeed from the same process.

See [plans/0002_the-solution.md](plans/0002_the-solution.md) for the full post-mortem.

### Why not just use FinderUtilities?

[suolapeikko/FinderUtilities](https://github.com/suolapeikko/FinderUtilities) uses the
same entitlement and confirmed it works.  MoreMenu differs in three meaningful ways:

| Behaviour | FinderUtilities | MoreMenu |
|---|---|---|
| Right-click empty space on Desktop **with no Finder window open** | ✗ silently fails | ✓ falls back to querying Finder for the current location via AppleScript |
| Right-click **on a file** | ✗ not supported | ✓ creates the file alongside the right-clicked item |
| Sidebar right-clicks | ✗ menu appears (no `menuKind` guard) | ✓ excluded — no reliable target directory |

FinderUtilities also adds "Open Terminal" and "Copy selected paths" menu items, which
are outside the scope of MoreMenu.

### Re-registering the extension after a rebuild

macOS caches extension registrations.  After every rebuild:

```bash
rm -rf ~/Applications/MoreMenu.app
cp -R ~/Library/Developer/Xcode/DerivedData/MoreMenu-*/Build/Products/Debug/MoreMenu.app \
      ~/Applications/MoreMenu.app
pluginkit -a "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
pluginkit -e use -i GMX.MoreMenu.MoreMenuExtension
killall Finder
```

Always register from `~/Applications`, not from DerivedData — otherwise a subsequent
clean build will invalidate the registered path.
