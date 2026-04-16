# Changelog

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
