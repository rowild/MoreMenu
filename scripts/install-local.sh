#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MoreMenu.app"
APP_SRC="$ROOT_DIR/.build/release-derived-data/Build/Products/Release/$APP_NAME"
APP_DST="$HOME/Applications/$APP_NAME"
EXTENSION_ID="GMX.MoreMenu.MoreMenuExtension"
INSTALLED_EXTENSION="$APP_DST/Contents/PlugIns/MoreMenuExtension.appex"
BUILT_EXTENSION="$APP_SRC/Contents/PlugIns/MoreMenuExtension.appex"

"$ROOT_DIR/scripts/build-release-dmg.sh"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Built app was not found at:"
  echo "  $APP_SRC"
  exit 1
fi

echo "==> Installing $APP_NAME to $HOME/Applications"
killall MoreMenu 2>/dev/null || true
killall MoreMenuExtension 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

echo "==> Removing stale MoreMenuExtension registrations from DerivedData"
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*$APP_NAME/Contents/PlugIns/MoreMenuExtension.appex" \
    -type d \
    -print | while IFS= read -r stale_extension; do
      pluginkit -r "$stale_extension" || true
    done
fi

pluginkit -r "$BUILT_EXTENSION" 2>/dev/null || true
sleep 1

echo "==> Registering installed Finder extension"
pluginkit -a "$INSTALLED_EXTENSION"
pluginkit -e use -i "$EXTENSION_ID"
sleep 1

echo "==> Restarting Finder"
killall Finder
sleep 1

echo
echo "Installed:"
echo "  $APP_DST"
echo
echo "Registered extension:"
pluginkit -mAvvv -i "$EXTENSION_ID"
