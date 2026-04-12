# Changelog

## Unreleased

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
