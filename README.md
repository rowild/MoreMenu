# MoreMenu

`MoreMenu` is a small macOS app that adds a `New Textfile` item to Finder's right-click menu for empty space.

When you use it, the app:

- creates `untitled.txt` in the current Finder location
- automatically chooses `untitled_0001.txt`, `untitled_0002.txt`, and so on if needed
- opens the created text file immediately with the default app for `.txt` files

## What problem it solves

macOS does not include a built-in "New Text File" item in Finder's empty-space context menu.

This app adds that missing command for:

- Finder windows
- the Desktop

## Requirements

- macOS 14 Sonoma or macOS 15 Sequoia
- Xcode
- an Apple ID configured in Xcode for signing

## Project structure

- [MoreMenu](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu) contains the Xcode project
- [ContentView.swift](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu/ContentView.swift) is the host app setup UI
- [FinderSync.swift](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenuExtension/FinderSync.swift) is the Finder extension logic
- [How this App was created.md](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/How%20this%20App%20was%20created.md) explains the full implementation and debugging process

## How to build and run

### In Xcode

1. Open [MoreMenu.xcodeproj](/Users/robertwildling/Desktop/_WWW/_CreateTextFileRightCLickMenuItemOnMacOS/MoreMenu/MoreMenu.xcodeproj).
2. In the top toolbar, choose the `MoreMenu` scheme.
3. Choose `My Mac` as the run destination.
4. In `Signing & Capabilities`, make sure your Apple team is selected for both targets.
5. Click Run.

### Enable the Finder extension

1. Open `System Settings`.
2. Go to `Privacy & Security`.
3. Open `Extensions`.
4. Open `Finder Extensions`.
5. Enable `MoreMenu`.

## First-time setup

When the host app opens:

1. Click `Grant Folder Access…`.
2. Select the folder tree where the app should be allowed to create files.

Recommended choice:

- your home folder, such as `/Users/your-name`

That gives the app access to:

- Desktop
- Documents
- and other folders inside your home directory

## How to use it

1. Open Finder.
2. Go to the Desktop or any authorized folder.
3. Right-click empty space.
4. Choose `New Textfile`.

Result:

- a new text file is created in that location
- the file is opened immediately

## Installing it as a standalone app

For local use, the finished app should live in your Applications folder.

The installed app used during development was:

- `/Users/robertwildling/Applications/MoreMenu.app`

The embedded Finder extension is inside that app bundle.

If needed, the extension can be re-registered with:

```bash
pluginkit -a "$HOME/Applications/MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex"
pluginkit -e use -i GMX.MoreMenu.MoreMenuExtension
killall Finder
```

## Troubleshooting

### The menu item does not appear

Check:

- the `MoreMenu` Finder extension is enabled in System Settings
- Finder has been restarted
- the app was actually built and signed

### The menu item appears but no file is created

Check:

- folder access was granted in the host app
- the chosen folder is the same folder or a parent of the folder you are testing

Example:

- to use it on Desktop, granting `/Users/your-name` is sufficient
- granting some unrelated external volume is not sufficient

### The file is not opened automatically

The app uses the default handler for `.txt` files.

If the file is created but not opened as expected, check the default app assigned to `.txt` files on your system.

## Notes

- This app uses a Finder Sync extension because Automator and Shortcuts do not support adding custom commands to Finder's empty-space context menu.
- The permission model relies on bookmarks shared from the host app to the extension.

## License

No license file is included yet.
