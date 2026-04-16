# MoreMenu — Bug Analysis & Fix Log

**Date:** 2026-04-10  
**Scope:** Full codebase audit after the extension stopped appearing in Finder windows
(it was still visible on the Desktop but nowhere else).

---

## Background: How the permission architecture works

Understanding the bugs requires understanding why the bookmark-passing architecture
exists in the first place.

A Finder Sync Extension is a **separate sandboxed process** from the host app.
It runs inside Finder's process tree, not inside MoreMenu.app.  Because it is
sandboxed, it cannot write to arbitrary directories on its own — macOS's TCC
(Transparency, Consent, Control) system blocks it.

The solution is a three-step handshake:

1. **Host app** — presents `NSOpenPanel`; the user picks a folder.  The OS grants
   the host app access to that folder.
2. **Host app** — serialises the permission as bookmark data and stores it in the
   **shared App Group** container (`UserDefaults(suiteName: "group.GMX.MoreMenu.shared")`).
3. **Extension** — reads the bookmark data, resolves it with `.withSecurityScope`,
   calls `startAccessingSecurityScopedResource()`, then writes the file.

Every bug in this list either broke one of these three steps, or was an
unrelated code-quality problem.

---

## Bug 1 — Menu item only appeared on empty-space right-clicks, never on files

**Severity:** Feature gap (by design, but wrong for the goal)  
**File:** `MoreMenuExtension/FinderSync.swift`  
**Lines before fix:** 25–28

### What the code did

```swift
override func menu(for menuKind: FIMenuKind) -> NSMenu {
    guard menuKind == .contextualMenuForContainer else {
        return NSMenu(title: "")   // blocked everything except empty-space
    }
```

`FIMenuKind` has three values:

| Value | When Finder calls it |
|---|---|
| `.contextualMenuForContainer` | Right-click on empty space inside a folder, or the Desktop |
| `.contextualMenuForItems` | Right-click on a selected file or folder |
| `.contextualMenuForSidebar` | Right-click on a sidebar item |

The guard was returning an empty menu for `.contextualMenuForItems`, which meant
"New Textfile" never appeared when the user right-clicked a file.

### Fix

Allow both container and item contexts:

```swift
guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems else {
    return NSMenu(title: "")
}
```

`.contextualMenuForSidebar` is intentionally still excluded — there is no reliable
way to determine a target directory from the sidebar context.

---

## Bug 2 — `newTextFileAction` hardcoded the wrong menu kind

**Severity:** Bug (silently wrong target directory for file right-clicks)  
**File:** `MoreMenuExtension/FinderSync.swift`  
**Lines before fix:** 51–52

### What the code did

```swift
@objc func newTextFileAction(_ sender: AnyObject) {
    guard let targetURL = targetDirectory(for: .contextualMenuForContainer) else {
```

Even after Bug 1 was fixed, the action always asked `targetDirectory` to resolve
as if this were a container (empty-space) click.  When a user right-clicked a file,
`targetDirectory` received `.contextualMenuForContainer` instead of `.contextualMenuForItems`,
which could cause it to fall back to the slow AppleScript path (or fail entirely)
rather than using the file's parent directory directly.

### Fix

Added a `currentMenuKind` property that `menu(for:)` writes before returning, and
`newTextFileAction` reads it:

```swift
// In menu(for:):
currentMenuKind = menuKind

// In newTextFileAction(_:):
guard let targetURL = targetDirectory(for: currentMenuKind) else {
```

`menu(for:)` and the action both run on the main thread in the extension process, so
no thread-safety mechanism is needed for this property.

---

## Bug 3 — Bookmark resolution in `authorizedBookmarkURL` used wrong options flag

**Severity:** Critical — caused file creation to fail silently after the extension appeared to work  
**File:** `MoreMenuExtension/FinderSync.swift`  
**Lines before fix:** 188–194

### What the code did

```swift
resolvedURL = try URL(
    resolvingBookmarkData: bookmarkData,
    options: [],              // ← wrong
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
```

Then, a few lines later:

```swift
let accessedScope = scopeURL?.startAccessingSecurityScopedResource() ?? false
// ...
guard accessedScope || scopeURL == nil else {
    throw FinderFileError.accessNotGranted(directoryURL.path)   // always thrown
}
```

### Why it failed

The host app creates bookmarks with `options: []`.  This produces an **implicit
security-scope bookmark** — one that carries the user's permission implicitly.
To *activate* that implicit scope in a different sandboxed process (the extension),
the bookmark must be resolved with `options: .withSecurityScope`.

Resolving with `options: []` produces a plain `URL` with no security scope attached.
`startAccessingSecurityScopedResource()` then returns `false` (as documented by Apple:
"If you call this method on a URL that was not obtained from a security-scoped bookmark,
the method returns false").  The guard throws `accessNotGranted`, `NSSound.beep()` plays,
and no file is written.

### Fix

```swift
resolvedURL = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,   // ← correct
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
```

---

## Bug 4 — `removeFolderAccess` used `.withSecurityScope` for comparison

**Severity:** Bug — silently prevented folder removal from working  
**File:** `MoreMenu/ContentView.swift`  
**Lines before fix:** 90–96

### What the code did

```swift
func removeFolderAccess(_ folderURL: URL) {
    var bookmarkEntries = ...
    bookmarkEntries.removeAll { existingData in
        guard let existingURL = try? URL(
            resolvingBookmarkData: existingData,
            options: [.withSecurityScope],   // ← inconsistent with how they were stored
            ...
```

### Why it failed

Bookmarks are stored with `options: []` (see `grantFolderAccess`).  Resolving them
with `.withSecurityScope` in the host app — which is not the process that created the
implicit scope — could fail or return a different URL representation, causing the
`standardizedFileURL ==` comparison to never match, and leaving the entry in place
(silent no-op).

### Fix

Use `options: []` for comparison — we only need the path, not an active security scope:

```swift
guard let existingURL = resolveForComparison(existing) else { return true }
```

Where `resolveForComparison` uses `options: []`.

---

## Bug 5 — `migrateStoredBookmarksIfNeeded` ran on every app launch

**Severity:** Minor — wasted CPU, potential bookmark corruption risk  
**File:** `MoreMenu/ContentView.swift`  
**Lines before fix:** 115–152

### What the code did

The migration function had no "already done" guard.  It ran every time the host app
opened, re-processing all stored bookmarks unconditionally.

### Why it mattered

1. Wasted CPU on every launch.
2. If the re-creation of a bookmark failed partway through (e.g., network volume
   temporarily unavailable), the migrated list would be shorter than the original,
   effectively deleting a valid entry.
3. Made the intention of the code unclear — "migration" implies a one-time upgrade.

### Fix

Added a version key in shared defaults:

```swift
static let currentMigrationVersion = 1
static let migrationVersionKey     = "BookmarkMigrationVersion"
```

The migration checks and updates this key:

```swift
let storedVersion = defaults.integer(forKey: SharedAccessStore.migrationVersionKey)
guard storedVersion < SharedAccessStore.currentMigrationVersion else { return }
// ... run migration ...
defaults.set(SharedAccessStore.currentMigrationVersion, forKey: SharedAccessStore.migrationVersionKey)
```

To trigger a new migration in future, increment `currentMigrationVersion`.

---

## Bug 6 — `fatalError` in `sharedDefaults` crashed the extension process in a loop

**Severity:** Stability — catastrophic if shared defaults ever failed to open  
**File:** `MoreMenuExtension/FinderSync.swift`  
**Lines before fix:** 233–238

### What the code did

```swift
private var sharedDefaults: UserDefaults {
    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
        fatalError("Unable to open shared defaults for app group \(Self.appGroupIdentifier)")
    }
    return defaults
}
```

### Why it was dangerous

A `fatalError` inside an extension process kills that process.  macOS is designed to
restart crashed extensions automatically — within seconds.  The restarted extension
immediately crashes again.  This produces a tight crash loop that is:

- **Invisible to the user** — they just see "nothing happens"
- **Difficult to diagnose** — `log show` would reveal it, but most users never check
- **Potentially persistent** — the loop continues until the extension is disabled

### Fix

Return `nil` and log the error.  Call sites that previously called `sharedDefaults`
unconditionally now unwrap optionally:

```swift
private var sharedDefaults: UserDefaults? {
    guard let defaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
        logger.error("Unable to open shared defaults for app group \(Self.appGroupIdentifier, privacy: .public)")
        return nil
    }
    return defaults
}
```

---

## Bug 7 — `UserDefaults.synchronize()` called throughout (deprecated no-op)

**Severity:** Code quality  
**Files:** Both `FinderSync.swift` and `ContentView.swift`

### What the code did

`synchronize()` was called after every read and write operation.

### Why it was wrong

`UserDefaults.synchronize()` has been a documented no-op since macOS 10.12 Sierra
and is formally deprecated in the latest SDKs.  The OS synchronises `UserDefaults`
automatically at appropriate intervals.  Calling it manually does nothing useful and
signals a misunderstanding of the API to any future reader.

### Fix

All calls removed.  Reads and writes use the standard `UserDefaults` API directly,
relying on automatic synchronisation.

---

## Non-bug: Why the menu stopped showing in Finder windows

The user reported that the menu item disappeared from Finder windows but remained
visible on the Desktop.

**This is most likely an installation/registration issue, not a code bug.**

The extension registers against `[URL(fileURLWithPath: "/")]` — every local
directory.  If the extension's registered binary path and the binary on disk diverge
(e.g., the app was rebuilt in Xcode but not re-copied to `~/Applications`), macOS
may partially serve stale registration state.  The Desktop is treated specially
enough by PlugInKit that it may remain functional even with stale state.

**Fix (manual, outside Xcode):**

```bash
# 1. Build in Xcode, then copy the fresh app to Applications:
cp -R ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/MoreMenu.app \
      ~/Applications/MoreMenu.app

# 2. Re-register the embedded extension:
pluginkit -a "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"

# 3. Explicitly enable it:
pluginkit -e use -i GMX.MoreMenu.MoreMenuExtension

# 4. Restart Finder:
killall Finder
```

To verify the extension is correctly registered:

```bash
pluginkit -mAvvv -i GMX.MoreMenu.MoreMenuExtension
```

To read the extension's runtime logs:

```bash
/usr/bin/log show --last 20m --style compact \
    --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'
```

---

## Code refactors applied alongside the bug fixes

### Bookmark helper methods extracted in `ContentView.swift`

The original code repeated similar `URL(resolvingBookmarkData:options:...)` blocks in
several places with different `options` flags, making it easy to use the wrong one.
The fix extracts three clearly-named helpers:

| Method | Options | Purpose |
|---|---|---|
| `resolveForComparison` | `[]` | Path comparison only (no scope needed) |
| `resolveForDisplay` | `[]` with `.withSecurityScope` fallback | Showing paths in the UI |
| `resolveForMigration` | `.withSecurityScope` with `[]` fallback | Converting old-format bookmarks |

This makes the intent of each call site explicit and prevents accidentally using the
wrong flag.

### `storedBookmarkEntries()` / `saveBookmarkEntries()` helpers

The pattern `sharedDefaults?.array(forKey: ...) as? [Data] ?? []` appeared in four
separate places.  Extracted into two private methods to keep changes in one place.

### MARK sections added to both files

Long Swift files without `// MARK:` sections are hard to navigate.  Sections were
added to group: constants, properties, init, FIFinderSync overrides, menu action,
target directory resolution, file creation, bookmark resolution, file presentation,
and shared defaults.

---

---

## Bug 8 — Wrong file-creation mechanism (root cause of all extension write failures)

**Severity:** Critical — the entire AppleScript + bookmark architecture was unnecessary  
**File:** `MoreMenuExtension/FinderSync.swift` and `MoreMenuExtension/MoreMenuExtension.entitlements`

### What went wrong

Multiple approaches were tried to write files from the sandboxed extension:

1. Direct `Data().write()` — failed with EPERM (no write access)
2. Security-scoped bookmarks cross-process — failed because `startAccessingSecurityScopedResource()` 
   always returned `false` in the extension process (bookmarks are bound to the creating app's bundle ID)
3. AppleScript `make new file at` delegated to Finder — failed with  
   `Finder got an error: Application isn't running`

All three approaches were wrong because they bypassed the actual correct solution.

### Root cause

The missing entitlement.  A working open-source reference implementation
([suolapeikko/FinderUtilities](https://github.com/suolapeikko/FinderUtilities)) uses:

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/</string>
</array>
```

This **sandbox temporary exception entitlement** grants the extension direct read-write access
to the user's entire home directory tree.  "Temporary" is a historical Apple naming convention —
these entitlements have existed since macOS 10.10 and remain valid.

### Fix

**Entitlements** — `MoreMenuExtension.entitlements` was simplified to:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
<array>
    <string>/</string>
</array>
```

Removed: `apple-events`, `application-groups`, `bookmarks.app-scope`.

**FinderSync.swift** — file creation replaced with a direct write:

```swift
try "".write(to: candidate, atomically: true, encoding: .utf8)
```

The entire bookmark-resolution system, `sharedDefaults`, `storedBookmarkEntries`, and
`createFileViaFinder` (AppleScript) were removed.  The extension no longer needs
the App Group or any IPC with the host app for file creation.

`currentInsertionLocation()` (which uses Apple Events to *query* the current Finder folder
path) was kept — that query-only use works correctly in a sandboxed extension.

### What the host app ContentView now does

`ContentView.swift` and its bookmark management code is no longer required for the extension
to work.  It remains as a user-visible setup guide but no longer serves a functional role in
granting the extension write access.

---

## Summary of all changes

| File | Change | Bug fixed |
|---|---|---|
| `FinderSync.swift` | Allow `.contextualMenuForItems` in `menu(for:)` | Bug 1 |
| `FinderSync.swift` | `currentMenuKind` property; use in action | Bug 2 |
| `FinderSync.swift` | `sharedDefaults` returns nil instead of fatalError | Bug 6 |
| `FinderSync.swift` | Remove all `synchronize()` calls | Bug 7 |
| `FinderSync.swift` | Replace AppleScript file creation with direct `String.write(to:)` | Bug 8 |
| `FinderSync.swift` | Remove entire bookmark/IPC architecture | Bug 8 |
| `FinderSync.swift` | Add MARK sections and doc-comments | Refactor |
| `MoreMenuExtension.entitlements` | Add `home-relative-path.read-write` exception | Bug 8 |
| `MoreMenuExtension.entitlements` | Remove `apple-events`, `app-group`, `bookmarks.app-scope` | Bug 8 |
| `ContentView.swift` | `removeFolderAccess` uses `options: []` | Bug 4 |
| `ContentView.swift` | Migration version key prevents re-runs | Bug 5 |
| `ContentView.swift` | Remove all `synchronize()` calls | Bug 7 |
| `ContentView.swift` | Extract bookmark helper methods | Refactor |
| `ContentView.swift` | Extract `storedBookmarkEntries` / `saveBookmarkEntries` | Refactor |
| `ContentView.swift` | Add MARK sections and doc-comments | Refactor |
