#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DERIVED_DATA="${MOREMENU_TEST_DERIVED_DATA:-$ROOT_DIR/.build/test-derived-data}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Xcode registers built apps with Launch Services. The unsigned test copy shares the
# installed extension's bundle ID, so Finder could load it and TCC would see a new identity.
unregister_test_products() {
  local result=$?
  local products="$TEST_DERIVED_DATA/Build/Products"
  if [[ -d "$products" ]]; then
    find "$products" -name '*.appex' -type d -prune -print |
      while IFS= read -r extension; do
        pluginkit -r "$extension" 2>/dev/null || true
      done
    find "$products" -name '*.app' -type d -prune -print |
      while IFS= read -r app; do
        "$LSREGISTER" -u "$app" 2>/dev/null || true
      done
  fi
  return "$result"
}
trap unregister_test_products EXIT

for script in "$ROOT_DIR"/scripts/*.sh; do
  zsh -n "$script"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT_DIR/scripts/tests" -v
xcodebuild -project "$ROOT_DIR/MoreMenu/MoreMenu.xcodeproj" -scheme MoreMenu \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO -only-testing:MoreMenuTests test
