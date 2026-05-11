# MoreMenu

MoreMenu adds new-file commands directly to Finder's first-level right-click menu on macOS.

Instead of digging through `Services` or another submenu, you can create a file exactly where you are working and open it immediately in the assigned app. That keeps the workflow short: right-click, choose the file type, start typing.

## What It Does

- adds new-file commands to Finder's top-level context menu
- works on empty space in a Finder window, on the Desktop, and on a selected file or folder
- creates the new file in the current location
- opens the created file right away in the default app for that file type
- auto-increments names: `untitled.ext`, `untitled_0001.ext`, `untitled_0002.ext`, and so on

## Screenshots

### Finder Context Menu

The file types you enable appear directly in Finder's first-level context menu.

![Finder context menu showing MoreMenu commands](assets/moremenu-screenshot-02.png)

### File-Type Settings

The MoreMenu app lets you decide which file types should appear.

![MoreMenu settings window with file-type checkboxes](assets/moremenu-screenshot-01.png)

## File Types

MoreMenu includes three core types out of the box:

- `Text (.txt)`
- `Markdown (.md)`
- `Rich Text (.rtf)`

You can also enable common developer-oriented file types, including:

- `JSON`, `YAML`, `TOML`, `XML`, `CSV`, `LOG`
- `HTML`, `CSS`, `SCSS`
- `JavaScript`, `JSX`
- `TypeScript`, `TSX`
- `Vue (.vue)`
- `Shell Script (.sh)`
- `Python (.py)`

## How To Manage File Extensions

1. Open `MoreMenu.app`
2. Turn `Enable MoreMenu in Finder` on or off
3. Check the file types you want to see in Finder
4. Right-click in Finder

Changes apply the next time you open the context menu.

Built-in file types stay enabled by default. The larger web and framework-oriented list is opt-in, so the menu does not get crowded unless you want it to.

## How To Use It

Right-click in Finder and choose the file type you want:

- inside a Finder window
- on the Desktop
- on a file or folder

MoreMenu creates the file in that location and immediately opens it in the app currently assigned to that extension.

## Why It Is Useful

macOS normally pushes similar actions into less direct places such as `Services`, or only exposes them when a folder is selected.

MoreMenu keeps those commands at the first menu level and opens the result immediately, which makes repetitive file creation much faster and less interruptive when you are already working in Finder.

## Setup

1. Install `MoreMenu.app`
2. Open `System Settings -> Privacy & Security -> Extensions -> Finder Extensions`
3. Enable `MoreMenu`

After that, right-click in Finder and choose the file type you want.

## Scope

MoreMenu creates files inside visible top-level folders in your Home folder — for example `~/Desktop`, `~/Documents`, `~/Downloads`, and their subfolders. It intentionally does not monitor `~/Library` or `~/Applications`, because those locations can make macOS classify the Finder extension as accessing other apps' data at login.

External drives under `/Volumes/*` are **not** supported in this build. MoreMenu items should be hidden there. Supporting `/Volumes/*` cleanly on macOS Tahoe requires a signed Developer ID build; see [DEVELOPER.md](DEVELOPER.md) if you're interested in the technical reason.

## First-Install Prompt

The current local build avoids the AppData prompt by keeping the Finder Sync monitored scope away from app-data roots. If macOS shows a "MoreMenu.app would like to access data from other apps" prompt after install or restart, that is a bug.

For local installs, `scripts/install-local.sh` uses a free `Apple Development` signing identity when one is available in your keychain. That gives macOS a stable app identity without requiring a paid Developer ID certificate.

If the app is installed from an older ad-hoc-signed DMG, unrelated one-time privacy prompts may still appear after an update because macOS can only identify that exact build.

## Notes

- Finder Sync is an app extension, not a macOS system extension.
- If macOS shows a System Extensions warning, that is not the setting MoreMenu uses.
- The relevant switch is always in `Finder Extensions`.

## Technical Docs

Developer-oriented build, release, architecture, and troubleshooting notes are in [DEVELOPER.md](DEVELOPER.md).
