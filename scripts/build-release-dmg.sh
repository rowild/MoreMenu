#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MoreMenu.app"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"

"$ROOT_DIR/scripts/build-app.sh"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/MoreMenu-v$VERSION.dmg"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp/}moremenu-dmg.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

# Public releases must be notarized. Credentials live in a local keychain profile.
if [[ "${MOREMENU_DISTRIBUTION:-0}" == "1" ]]; then
  : "${MOREMENU_NOTARY_PROFILE:?Set MOREMENU_NOTARY_PROFILE to a notarytool keychain profile}"
  NOTARY_OPTIONS=(--keychain-profile "$MOREMENU_NOTARY_PROFILE" --wait)
  if [[ -n "${MOREMENU_NOTARY_KEYCHAIN:-}" ]]; then
    NOTARY_OPTIONS+=(--keychain "$MOREMENU_NOTARY_KEYCHAIN")
  fi
  ditto -c -k --keepParent "$APP_PATH" "$STAGE_DIR/MoreMenu.zip"
  xcrun notarytool submit "$STAGE_DIR/MoreMenu.zip" "${NOTARY_OPTIONS[@]}"
  xcrun stapler staple "$APP_PATH"
  rm "$STAGE_DIR/MoreMenu.zip"
fi

ditto "$APP_PATH" "$STAGE_DIR/MoreMenu.app"
ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$DIST_DIR"
hdiutil create -volname MoreMenu -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
if [[ "${MOREMENU_DISTRIBUTION:-0}" == "1" ]]; then
  xcrun notarytool submit "$DMG_PATH" "${NOTARY_OPTIONS[@]}"
  xcrun stapler staple "$DMG_PATH"
fi
printf 'Created: %s\n' "$DMG_PATH"
