# How this App was created

## Goal

The goal of this project was very specific:

- Add a `New Textfile` item to the Finder context menu
- Make it appear when right-clicking empty space in a Finder window
- Make it appear on the Desktop as well
- Create `untitled.txt` in the current location
- Open the new text file automatically after creation
- Support macOS 14 Sonoma and macOS 15 Sequoia

That sounds simple, but the implementation was not simple because macOS does not treat all ways of creating files or adding menu items equally.

## Where it started

The project started from a practical user need:

- A right-click menu item on empty space in Finder
- Not a Quick Action on a selected file
- Not a Service hidden in a submenu
- Not a keyboard shortcut only

The first important discovery was that this requirement rules out Automator Quick Actions and Shortcuts for the final solution.

## Why Automator is easier

Automator is easier because it runs in a much more forgiving environment for this kind of task.

With Automator or JavaScript for Automation:

- Finder is already the thing you are talking to
- the scripting model is straightforward
- getting the current Finder window path is easy
- creating a file can be done with shell `touch`, AppleScript, or Automator's built-in actions
- opening the new file is also easy

For example, this JXA code worked right away for getting the front Finder window path:

```javascript
function run(input, parameters) {
    var finder = Application('Finder');
    finder.includeStandardAdditions = true;
    var currentPath = decodeURI(finder.windows[0].target().url().slice(7));
    return currentPath;
}
```

That part was never the real problem.

The real problem was this:

- Automator and Shortcuts do not add custom items to the empty-space Finder context menu
- they require a selected file or folder, or they show up elsewhere such as `Services`

So Automator was easier technically, but it could not meet the exact UI requirement.

## Why the final app had to be a Finder Sync extension

Apple's supported mechanism for adding custom Finder context menu items is a Finder Sync extension.

That means the final app architecture had to be:

- a host macOS app
- a Finder Sync extension embedded inside that app

The host app exists mainly to:

- provide setup instructions
- request folder access from the user
- store persistent access bookmarks

The Finder Sync extension exists to:

- show the `New Textfile` menu item in Finder
- determine the target folder
- create the file in that folder
- open the created file

## The actual implementation path

### Step 1: Create the Xcode project

The project uses two targets:

- `MoreMenu`
- `MoreMenuExtension`

`MoreMenu` is the host app.

`MoreMenuExtension` is the Finder Sync extension.

The important project pieces are:

- [MoreMenu.xcodeproj](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu.xcodeproj)
- [FinderSync.swift](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenuExtension/FinderSync.swift)
- [ContentView.swift](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu/ContentView.swift)
- [Info.plist](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenuExtension/Info.plist)
- [MoreMenu.entitlements](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu/MoreMenu.entitlements)
- [MoreMenuExtension.entitlements](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenuExtension/MoreMenuExtension.entitlements)

### Step 2: Make the menu item appear at all

The Finder Sync extension was wired to return a custom `NSMenu` in:

- `override func menu(for menuKind: FIMenuKind) -> NSMenu`

The extension was restricted to:

- `.contextualMenuForContainer`

That is important, because the target was right-click on empty space in a folder view, not file-item context menus.

### Step 3: Register and enable the extension

This part was unexpectedly annoying.

The extension did not appear correctly at first because:

- the app was only being run from Xcode build output
- Finder extension registration state was inconsistent
- PlugInKit state had to be corrected

The practical fix was:

- build the app
- copy it to `/Users/robertwildling/Applications/MoreMenu.app`
- register the embedded extension with `pluginkit`
- explicitly enable it
- restart Finder

### Step 4: Make the menu item look correct

The menu icon first appeared as a black template icon.

That happened because macOS treated it as a template image.

The fix was:

- bundle a real menu icon asset
- set `icon.isTemplate = false`

That produced the green icon.

### Step 5: Try to create the file directly

The obvious implementation was:

- determine the target directory
- create `untitled.txt` with `Data().write(...)` or `FileManager`

That sounds correct, but the first real runtime logs showed that macOS blocked the write.

The actual error was:

- `NSCocoaErrorDomain Code=513`
- underlying POSIX error `Operation not permitted`

That proved the menu code was working but the extension was not allowed to write to the Desktop or other arbitrary folders.

### Step 6: Realize the core problem was sandboxing

This was the real turning point.

The problem was never "how do you create a text file?"

The problem was:

- a Finder Sync extension is sandboxed
- it is a separate process from the host app
- it does not automatically inherit Finder's permissions
- it does not automatically inherit the host app's file access

That is why the JXA script felt easy while the Finder Sync implementation felt absurdly hard.

The complexity was mostly permission architecture, not file creation logic.

### Step 7: Add a host-app permission flow

The correct architecture became:

1. The host app asks the user for folder access
2. The host app stores bookmarks for those folders
3. The Finder extension reads those bookmarks
4. The Finder extension starts security-scoped access
5. The extension creates the file

That host-side setup UI was added to:

- [ContentView.swift](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu/ContentView.swift)

### Step 8: Discover the bookmark type bug

Even after folder access was granted, the extension still failed.

This was one of the most important bugs in the whole process.

The host app originally stored bookmarks with:

```swift
options: [.withSecurityScope]
```

That was wrong for this architecture.

Why it was wrong:

- the host app and the Finder extension are separate processes
- passing access between processes requires an implicit security-scoped bookmark
- an explicit app-scoped bookmark is the wrong kind for cross-process handoff here

The fix was:

- create bookmarks with `options: []`
- keep implicit security scope
- migrate existing stored bookmarks

After that change, the extension could finally use the stored access and create the file successfully.

### Step 9: Open the file automatically

Once file creation worked, the last improvement was easy.

After creating the file, the extension now does:

```swift
NSWorkspace.shared.open(fileURL)
```

If opening fails, it falls back to revealing the file in Finder.

## Every significant mistake and why it failed

This is the complete list of the important mistakes made during development.

### Mistake 1: Thinking Automator or Shortcuts could solve the exact empty-space menu requirement

Why it failed:

- Quick Actions and Shortcuts do not appear on right-click empty space in Finder
- they require selected items or show up in different UI locations

What was learned:

- they are useful comparison tools, not the final solution

### Mistake 2: Treating the problem as a "file creation" problem instead of a "permission architecture" problem

Why it failed:

- writing `untitled.txt` is trivial in unsandboxed or script-driven environments
- writing it from a Finder Sync extension is not trivial because sandbox rules dominate the behavior

What was learned:

- the implementation had to be designed around macOS sandbox and TCC behavior first

### Mistake 3: Assuming `targetedURL()` could always be used directly as the destination folder

Why it failed:

- `targetedURL()` can refer to a file or folder depending on context
- if a file is clicked, it is not a valid destination folder by itself

What was learned:

- target URLs must be normalized so that file URLs resolve to their parent directory

### Mistake 4: Trying to rely on AppleScript/Finder automation inside the extension for the actual create action

Why it failed:

- it produced Finder communication failures such as error `-600`
- it added complexity without solving the sandbox problem

What was learned:

- Finder automation was not the correct write path for the final implementation

### Mistake 5: Trying to request folder permission from inside the extension action

Why it failed:

- Finder Sync extensions are a poor place to present permission UI
- open/save panel behavior inside the extension was unreliable
- logs showed extension request teardown and exceptions

What was learned:

- all access-granting UI belongs in the host app

### Mistake 6: Using direct file creation in the extension before a valid cross-process bookmark architecture existed

Why it failed:

- macOS blocked writes with `Code=513` and underlying `EPERM`

What was learned:

- the write code was fine
- the access model was not

### Mistake 7: Storing the wrong bookmark type in the host app

Why it failed:

- the host app stored explicit `.withSecurityScope` bookmarks
- the extension could not use them correctly for cross-process access

What was learned:

- the host app had to store implicit security-scoped bookmarks instead

### Mistake 8: Assuming "folder appears in the UI" means "extension can use it"

Why it failed:

- the host app could display resolved URLs from stored bookmark data
- that did not prove the extension could activate valid access from them

What was learned:

- logs had to verify bookmark resolution and `startAccessingSecurityScopedResource()`

### Mistake 9: Focusing too little on runtime logs early enough

Why it failed:

- assumptions were made too early
- behavior looked like "nothing happens" in Finder
- the real reason only became obvious after checking extension logs

What was learned:

- the decisive information came from `log show`, not from UI appearance

### Mistake 10: Not treating PlugInKit registration state as a first-class problem

Why it failed:

- the extension was not consistently visible or enabled at first
- Finder behavior stayed inconsistent while registration state was unclear

What was learned:

- installation path and PlugInKit state matter
- Finder extensions can look broken when the registration state is the real issue

## The final working design

The working version uses this design:

### Host app responsibilities

- show setup UI
- instruct the user what to enable
- ask the user to grant folder access
- store folder bookmarks in the shared App Group container

### Finder Sync extension responsibilities

- add `New Textfile` to Finder's container context menu
- determine the current folder
- find the best matching authorized bookmark
- start security-scoped access
- create the file
- auto-increment the name if necessary
- open the created file

### File naming behavior

The extension uses this sequence:

- `untitled.txt`
- `untitled_0001.txt`
- `untitled_0002.txt`
- and so on

### File opening behavior

After creation:

- the file is opened with the default app for `.txt`
- on most systems that is TextEdit unless the user changed the default

## Exactly what had to be done in Xcode

This section is intentionally detailed for someone who is not yet an Xcode user.

### 1. Open the project

Open:

- [MoreMenu.xcodeproj](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu.xcodeproj)

Do not run the extension scheme directly.

Run the host app scheme:

- `MoreMenu`

### 2. Check the selected scheme

In the top Xcode toolbar:

- there is a scheme selector
- it may show `MoreMenu` or `MoreMenuExtension`

You must choose:

- `MoreMenu`

Not:

- `MoreMenuExtension`

Why:

- the host app launches and registers the embedded Finder extension
- the extension target alone is not the app the user installs

### 3. Configure signing

For both targets:

- `MoreMenu`
- `MoreMenuExtension`

go to:

- `Signing & Capabilities`

Make sure:

- `Automatically manage signing` is enabled
- your Apple ID team is selected

This project was built successfully with a free Apple developer team.

### 4. Confirm capabilities

The host app needs:

- App Sandbox
- User-selected file access: read/write
- App Groups

The extension needs:

- App Sandbox
- App Groups
- bookmark entitlement
- Apple Events entitlement

These are already configured in the project files:

- [MoreMenu.entitlements](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu/MoreMenu.entitlements)
- [MoreMenuExtension.entitlements](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenuExtension/MoreMenuExtension.entitlements)

### 5. Build and run from Xcode

In Xcode:

1. select scheme `MoreMenu`
2. choose destination `My Mac`
3. click the Run button

What this does:

- builds the host app
- builds the Finder Sync extension
- signs both
- launches the host app

### 6. Enable the Finder extension in System Settings

Go to:

- `System Settings`
- `Privacy & Security`
- `Extensions`
- `Finder Extensions`

Enable:

- `MoreMenu`

If the extension does not appear immediately:

- quit and reopen System Settings
- restart Finder
- run the app again from Xcode

### 7. Grant folder access in the host app

When the `MoreMenu` host app opens:

1. click `Grant Folder Access…`
2. choose the folder you want to allow

Recommended choice:

- `/Users/<your-user-name>`

Why:

- that covers Desktop and other folders inside your home directory

If you only care about Desktop, you can choose Desktop directly.

### 8. Test the menu item

In Finder:

1. open a folder or go to the Desktop
2. right-click empty space
3. choose `New Textfile`

Expected result:

- `untitled.txt` is created
- if the name already exists, the app creates the next available name
- the created file opens automatically

### 9. Install the app as a normal standalone application

Running from Xcode is useful for development, but the app should finally live in the Applications folder.

The practical installation process used here was:

1. build the app in Xcode
2. locate the built app bundle
3. copy it to the Applications folder
4. register the embedded Finder extension
5. enable the extension
6. restart Finder

The built app bundle came from Xcode's build output and was copied to:

- `/Users/robertwildling/Applications/MoreMenu.app`

For everyday use, that is the app you should keep.

### 10. What "save it to Applications" really means

On macOS, an `.app` is a bundle.

That means:

- `MoreMenu.app` is the actual application
- the Finder extension lives inside that app bundle
- copying the app bundle to Applications is how you install it for local use

You do not separately install the extension by dragging the `.appex` somewhere.

The `.appex` must remain embedded inside `MoreMenu.app`.

## Useful terminal commands during development

These were the important commands used during debugging and installation.

### Build from terminal

```bash
xcodebuild -project MoreMenu/MoreMenu.xcodeproj -scheme MoreMenu -configuration Debug -sdk macosx build
```

### List the registered extension

```bash
pluginkit -mAvvv -i GMX.MoreMenu.MoreMenuExtension
```

### Register the embedded extension

```bash
pluginkit -a "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
```

### Enable the extension

```bash
pluginkit -e use -i GMX.MoreMenu.MoreMenuExtension
```

### Restart Finder

```bash
killall Finder
```

### Inspect extension logs

```bash
/usr/bin/log show --last 20m --style compact --predicate 'subsystem == "GMX.MoreMenu.MoreMenuExtension"'
```

## Final conclusion

This app eventually worked by choosing the only Apple-supported route that satisfies the exact UI requirement:

- Finder Sync extension for the menu
- host app for permission setup
- shared bookmarks for persistent cross-process folder access

The hardest part was not the menu and not the file creation.

The hardest part was understanding and fixing the macOS permission model correctly.
