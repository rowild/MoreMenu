#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
for script in "$ROOT_DIR"/scripts/*.sh; do
  zsh -n "$script"
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$ROOT_DIR/scripts/tests" -v
xcodebuild -project "$ROOT_DIR/MoreMenu/MoreMenu.xcodeproj" -scheme MoreMenu \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "${MOREMENU_TEST_DERIVED_DATA:-$ROOT_DIR/.build/test-derived-data}" \
  CODE_SIGNING_ALLOWED=NO -only-testing:MoreMenuTests test
