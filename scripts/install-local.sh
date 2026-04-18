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

# 1.2.0 migration: clean up state from the 1.1.5-1.1.7 bookmark architecture.
# The extension cached local scoped bookmarks in its private UserDefaults and
# the App Group held authorizedFolderRecords + sharedAuthorizedFolderEntries.
# None of that is used anymore; leaving it in place can only confuse things.
echo "==> Cleaning up legacy authorized-folder state"
defaults delete GMX.MoreMenu.MoreMenuExtension 2>/dev/null || true
defaults delete group.GMX.MoreMenu sharedAuthorizedFolderEntries 2>/dev/null || true
defaults delete group.GMX.MoreMenu authorizedFolderRecords 2>/dev/null || true

# Reset the TCC record that actually fires for MoreMenu on Tahoe 26.4 —
# SystemPolicyAppData, NOT SystemPolicyAppBundles. The prompt text is shared
# between these two services, which misled the 1.2.0 installer. Under ad-hoc
# signing this reset does NOT prevent the prompt (the csreq can't be made
# stable without a Developer ID), but it stops the stored csreq from getting
# stale and aligns the TCC row to the current build. See
# .claude/plans/0004_new_research_on_rightclick_permission.md §11.2 and §12.3.
tccutil reset SystemPolicyAppData GMX.MoreMenu 2>/dev/null || true
tccutil reset SystemPolicyAppData GMX.MoreMenu.MoreMenuExtension 2>/dev/null || true

echo "==> Removing stale MoreMenuExtension registrations from DerivedData and build temp"
for stale_root in "$HOME/Library/Developer/Xcode/DerivedData" "/private/tmp/moremenu-build" "$ROOT_DIR/.build"; do
  if [[ -d "$stale_root" ]]; then
    find "$stale_root" \
      -path "*$APP_NAME/Contents/PlugIns/MoreMenuExtension.appex" \
      -type d \
      -print | while IFS= read -r stale_extension; do
        pluginkit -r "$stale_extension" || true
      done
  fi
done

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
