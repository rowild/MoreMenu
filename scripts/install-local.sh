#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CONFIGURATION="${CONFIGURATION:-Release}"
export DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
APP_SRC="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MoreMenu.app"
INSTALL_DIR="${MOREMENU_INSTALL_DIR:-$HOME/Applications}"
APP_DST="$INSTALL_DIR/MoreMenu.app"
EXTENSION_ID="GMX.MoreMenu.MoreMenuExtension"
LEGACY_PREFERENCES="${MOREMENU_LEGACY_PREFERENCES:-$HOME/Library/Group Containers/group.GMX.MoreMenu/Library/Preferences/group.GMX.MoreMenu.plist}"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"
INSTALL_STAGE="$(mktemp -d "$INSTALL_DIR/.moremenu-install.XXXXXX")"
HAD_PREVIOUS=0
REPLACED=0
COMPLETE=0
cleanup() {
  local result=$?
  if [[ "$COMPLETE" == 0 && "$REPLACED" == 1 ]]; then
    echo "Installation failed; restoring the previous app." >&2
    rm -rf "$APP_DST"
    if [[ "$HAD_PREVIOUS" == 1 ]]; then
      mv "$INSTALL_STAGE/previous.app" "$APP_DST"
      pluginkit -a "$APP_DST/Contents/PlugIns/MoreMenuExtension.appex" || true
    fi
  fi
  rm -rf "$INSTALL_STAGE"
  return "$result"
}
trap cleanup EXIT

ditto "$APP_SRC" "$INSTALL_STAGE/MoreMenu.app"
python3 "$ROOT_DIR/scripts/verify-signing.py" "$INSTALL_STAGE/MoreMenu.app"
# Export before replacing anything. Invalid legacy data aborts without deleting it.
LEGACY_JSON="$(python3 "$ROOT_DIR/scripts/export-legacy-settings.py" "$LEGACY_PREFERENCES")"
killall MoreMenu 2>/dev/null || true
killall MoreMenuExtension 2>/dev/null || true
if [[ -e "$APP_DST" ]]; then
  mv "$APP_DST" "$INSTALL_STAGE/previous.app"
  HAD_PREVIOUS=1
fi
REPLACED=1
mv "$INSTALL_STAGE/MoreMenu.app" "$APP_DST"
"$APP_DST/Contents/MacOS/MoreMenu" --import-legacy-settings "$LEGACY_JSON"

# Unregister only this app's old development copies; leave their files intact.
for stale_root in "$HOME/Library/Developer/Xcode/DerivedData" "/private/tmp/moremenu-build" "$ROOT_DIR/.build"; do
  if [[ -d "$stale_root" ]]; then
    find "$stale_root" -path '*MoreMenu.app/Contents/PlugIns/MoreMenuExtension.appex' -type d -print |
      while IFS= read -r stale_extension; do
        pluginkit -r "$stale_extension" || true
      done
  fi
done
pluginkit -r "$APP_SRC/Contents/PlugIns/MoreMenuExtension.appex" 2>/dev/null || true
if [[ "$HAD_PREVIOUS" == 1 ]]; then
  pluginkit -r "$INSTALL_STAGE/previous.app/Contents/PlugIns/MoreMenuExtension.appex" 2>/dev/null || true
fi
pluginkit -a "$APP_DST/Contents/PlugIns/MoreMenuExtension.appex"
pluginkit -e use -i "$EXTENSION_ID"
COMPLETE=1
killall Finder 2>/dev/null || true
printf 'Installed: %s\n' "$APP_DST"
pluginkit -mAvvv -i "$EXTENSION_ID"
