# Project Plan: "New Text File" Finder Extension

## Overview
A native macOS 14/15 app that adds **"New Text File"** as the first item in the Finder right-click (context) menu — appearing before "New Folder" on empty space, and before "Open" on files.

---

## Architecture

### Technology: Finder Sync Extension (FIFinderSyncExtension)
- The **only** Apple-supported mechanism for adding custom items to the Finder context menu.
- Available since macOS 10.10 (Yosemite), still supported on macOS 14 (Sonoma) and 15.2+ (Sequoia).
- **Known issue:** macOS 15.0–15.1 had a bug where third-party Finder Sync extensions were invisible in System Settings. Apple fixed this in 15.2. If the user is on 15.0 or 15.1, they must update.

### Project Structure
```
NewTextFile/
├── NewTextFile.xcodeproj/
├── NewTextFile/                  # Host app (minimal, just launches the extension)
│   ├── NewTextFileApp.swift      # SwiftUI app entry point
│   └── Info.plist                # Declares the extension
└── NewTextFileExtension/         # Finder Sync Extension target
    ├── FinderSync.swift          # Core extension logic
    ├── Info.plist                # Extension configuration (NSExtension)
    └── Assets.xcassets/          # App icon, menu icon (if needed)
```

### Two Xcode Targets
1. **Host App** (`NewTextFile`): A minimal SwiftUI app that exists only to host the extension. Its sole purpose on first launch is to prompt the user to enable the extension in System Settings.
2. **Finder Sync Extension** (`NewTextFileExtension`): The actual extension that hooks into Finder's context menu.

---

## Implementation Details

### 1. Host App — `NewTextFileApp.swift`

A minimal SwiftUI app with:
- A window that says: *"Please enable the extension in System Settings, then relaunch Finder."*
- A button: **"Open System Settings"** that deep-links to the correct settings pane.
- No other UI needed.

The host app must request **Full Disk Access** permission to create files in arbitrary directories.

### 2. Finder Sync Extension — `FinderSync.swift`

The extension subclass `FIFinderSyncExtension` and implements:

#### a. Registration — `init()`
```swift
override init() {
    super.init()
    // Monitor ALL local directories (not just a specific one)
    FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    // Alternatively, use monitorLocalDirectoryOnly for broader compatibility
}
```

#### b. Context Menu — `menu(for menuKind:)`
```swift
override func menu(for menuKind: FIMenuKind) -> NSMenu {
    let menu = NSMenu(title: "")

    // "New Text File" — the primary action, appears FIRST in the context menu
    let newItem = NSMenuItem(title: "New Text File", action: #selector(newTextFileAction(_:)), keyEquivalent: "")
    // newItem.image = NSImage(named: "menuIcon")  // optional icon
    menu.addItem(newItem)

    // Separator after our item
    menu.addItem(NSMenuItem.separator())

    return menu
}
```

The menu items returned here appear **at the top** of the Finder context menu, before system items like "New Folder", "Open", etc.

#### c. Menu Action Handler — `newTextFileAction(_:)`
This is where the file creation logic lives:

```swift
@objc func newTextFileAction(_ sender: AnyObject) {
    // 1. Get the targeted directory from the menu item's representedObject
    guard let menu = sender as? NSMenuItem,
          let targetURL = menu.representedObject as? URL else { return }

    // 2. Determine the filename with auto-increment logic
    let fileManager = FileManager.default
    var filename = "untitled.txt"
    var fileURL = targetURL.appendingPathComponent(filename)

    if fileManager.fileExists(atPath: fileURL.path) {
        var counter = 1
        repeat {
            filename = String(format: "untitled_%04d.txt", counter)
            fileURL = targetURL.appendingPathComponent(filename)
            counter += 1
        } while fileManager.fileExists(atPath: fileURL.path)
    }

    // 3. Create the empty file
    let created = fileManager.createFile(atPath: fileURL.path, contents: nil, attributes: nil)

    if created {
        // 4. Optional: open the file in the default text editor
        NSWorkspace.shared.open(fileURL)
    }
}
```

#### d. Target URL tracking — `didChangeObservation(at:)`

The extension needs to track which directory the context menu was invoked on. This is done via:

```swift
override func menu(for menuKind: FIMenuKind) -> NSMenu {
    let menu = NSMenu(title: "")

    // Get the current selection or directory
    let selectedItemURLs = FIFinderSyncController.default().selectedItemURLs()

    // Determine the target directory:
    let targetURL: URL
    if let firstSelected = selectedItemURLs?.first, firstSelected.hasDirectoryPath {
        targetURL = firstSelected
    } else if let firstSelected = selectedItemURLs?.first, !firstSelected.hasDirectoryPath {
        // User right-clicked a file — use the file's parent directory
        targetURL = firstSelected.deletingLastPathComponent()
    } else {
        // No selection (right-clicked empty space) — we need the directory being viewed
        // This is the tricky part — see "Empty Space Detection" below
        return menu  // Return empty menu if we can't determine the directory
    }

    let newItem = NSMenuItem(title: "New Text File", action: #selector(newTextFileAction(_:)), keyEquivalent: "")
    newItem.representedObject = targetURL
    newItem.target = self
    menu.addItem(newItem)
    menu.addItem(NSMenuItem.separator())

    return menu
}
```

### 3. Empty Space Detection (right-click on blank area)

**Challenge:** When right-clicking empty space (not on a file/folder), `selectedItemURLs()` returns `nil` or an empty array. The Finder Sync Extension does NOT directly tell us which directory is being viewed.

**Solution approaches (need to verify which works):**

**Approach A: `toolbarItemClicked()` callback**
- When the extension's toolbar button is used, `toolbarItemClicked()` provides the current directory URL.
- But this only applies to toolbar clicks, not context menus.

**Approach B: Monitor a known set of directories**
- Set `directoryURLs` to a list of paths to monitor.
- When right-clicking in a monitored directory, `menu(for:)` is called with that context.
- Setting it to `["/"]` monitors all local filesystem locations.
- The `menu(for:)` method receives context, but we still need to know *which* directory.

**Approach C: Use `NSAppleEventDescriptor` to query the frontmost Finder window**
- From within the extension, send an Apple Event to Finder to ask for the `target` of the frontmost window.
- This is what the Automator AppleScript approach does, and it works from within an extension context as well (since the extension has the same process sandbox as the host app).
- **This is the recommended approach** — proven to work, matches our existing AppleScript logic.

```swift
private func getFrontmostFinderDirectory() -> URL? {
    let script = """
    tell application "Finder"
        if (count of windows) is not 0 then
            return POSIX path of (target of front window as alias)
        else
            return POSIX path of (desktop as alias)
        end if
    end tell
    """
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        let output = scriptObject.executeAndReturnError(&error)
        if let path = output.stringValue {
            return URL(fileURLWithPath: path)
        }
    }
    return nil
}
```

### 4. Filename Logic

| Condition | Resulting filename |
|---|---|
| No `untitled.txt` exists | `untitled.txt` |
| `untitled.txt` exists | `untitled_0001.txt` |
| `untitled_0001.txt` also exists | `untitled_0002.txt` |
| ... | `untitled_0003.txt`, etc. |

The 4-digit zero-padded counter ensures sorted order in Finder's list view.

---

## Code Signing & Distribution

### What is NOT needed
- ❌ **Paid Apple Developer Program** ($99/year) — not required for personal/local use
- ❌ **Notarization** — not required if the user manually allows the app (right-click → Open, or System Settings → Privacy & Security → "Open Anyway")
- ❌ **App Store submission** — this is a local development build

### What IS needed
- ✅ **Xcode code signing** — Xcode automatically applies an **ad hoc signature** using the user's Apple ID (free). This is mandatory on Apple Silicon Macs.
- ✅ **Team selection in Xcode** — Go to target settings → Signing & Capabilities → select your Apple ID as the team. A free Apple ID works fine.
- ✅ **App Sandbox disabled** for the extension — Finder Sync Extensions need broader access. In Signing & Capabilities, remove "App Sandbox" if present.
- ✅ **System Extension approval** — After first run, the user must enable the extension in System Settings.

### Enabling the Extension After Installation

| macOS Version | Path to Enable |
|---|---|
| **macOS 14 (Sonoma)** | System Settings → Privacy & Security → Extensions → Finder Extensions → check ✅ "NewTextFileExtension" |
| **macOS 15.0–15.1** | Bug: third-party Finder Sync extensions are invisible in System Settings. **Must update to 15.2+.** |
| **macOS 15.2+ (Sequoia)** | System Settings → General → Login Items & Extensions → File Providers → toggle ON "NewTextFileExtension" |

### Permission Requirements
- **Full Disk Access** — The extension needs this to create files in any directory. The host app should request this on first launch.
- **Finder Automation** — The AppleScript call to query Finder's frontmost window requires Finder to be accessible via Apple Events. This is granted automatically (no special permission needed for built-in apps like Finder).

---

## Development Steps

### Step 1: Create Xcode Project
1. Open Xcode → **New Project** → **macOS** → **App**
2. Product Name: `NewTextFile`
3. Interface: **SwiftUI**
4. Language: **Swift**
5. Set Team (Apple ID) in Signing & Capabilities

### Step 2: Add Finder Sync Extension Target
1. File → New → Target → **macOS** → **Finder Sync Extension**
2. Product Name: `NewTextFileExtension`
3. Xcode generates:
   - `FinderSync.swift` with boilerplate
   - `Info.plist` with `NSExtension` configuration
   - Entitlements file

### Step 3: Implement `FinderSync.swift`
- Replace boilerplate with the implementation described above
- Key methods: `init()`, `menu(for:)`, `newTextFileAction(_:)`, `getFrontmostFinderDirectory()`
- Handle all three scenarios: empty space, file right-click, folder right-click

### Step 4: Configure Entitlements
- Ensure the extension has `com.apple.security.files.user-selected.read-write` or equivalent
- Remove App Sandbox if it conflicts with Finder Sync functionality

### Step 5: Build, Run, Enable
1. Run the project (Cmd+R) — the host app launches
2. Enable the extension in System Settings (path depends on macOS version)
3. Relaunch Finder (`killall Finder` in Terminal) to ensure the extension is loaded
4. Test: right-click empty space in Finder → "New Text File" should appear first

### Step 6: Test Edge Cases
- Empty space right-click in Finder window
- Empty space right-click on Desktop
- Right-click on a file (file should be created in the same directory)
- Right-click on a folder (file should be created inside the folder)
- Duplicate filename handling (untitled.txt already exists)
- Counter overflow (what if untitled_9999.txt exists?)

---

## Risks & Open Questions

1. **macOS 15.0–15.1 compatibility** — The Finder Sync extension visibility bug means users on these versions cannot enable the extension via System Settings. Workaround: use `pluginkit` CLI to enable it. The user should update to 15.2+ if possible.

2. **AppleScript from within extension** — Need to verify that `NSAppleScript` can successfully call into Finder from within a Finder Sync Extension sandbox. The extension runs in the Finder process space, so it should work, but this needs testing.

3. **Position in context menu** — Finder Sync Extensions add items at the **top** of the context menu. This means "New Text File" will appear before "New Folder" on empty space — which is exactly what the user requested.

4. **Desktop right-click** — The extension needs to handle the Desktop as a special case (it's `~/Desktop`). The AppleScript approach handles this via `desktop as alias`.

---

## Files to Create

| File | Purpose |
|---|---|
| `NewTextFile.xcodeproj/project.pbxproj` | Xcode project (generated) |
| `NewTextFile/NewTextFileApp.swift` | Host app entry point, settings prompt |
| `NewTextFile/Assets.xcassets/` | App icon |
| `NewTextFileExtension/FinderSync.swift` | Core extension logic |
| `NewTextFileExtension/Info.plist` | Extension registration |
| `NewTextFileExtension/NewTextFileExtension.entitlements` | Extension entitlements |
