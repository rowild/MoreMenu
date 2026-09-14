#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/MoreMenu.app"
EXTENSION_PATH="$APP_PATH/Contents/PlugIns/MoreMenuExtension.appex"
CODE_SIGN_IDENTITY="${MOREMENU_CODE_SIGN_IDENTITY:-}"

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == "-" ]]; then
  echo "A certificate-backed identity for team QN24ZH7M6W is required. Set MOREMENU_CODE_SIGN_IDENTITY." >&2
  exit 1
fi
if [[ "${MOREMENU_DISTRIBUTION:-0}" == "1" && "$CODE_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Public distribution requires a Developer ID Application identity." >&2
  exit 1
fi

xcodebuild -project "$ROOT_DIR/MoreMenu/MoreMenu.xcodeproj" \
  -scheme MoreMenu -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO build

# Inner bundles first. A timestamp is required for Developer ID distribution.
SIGN_OPTIONS=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime)
if [[ "$CODE_SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  SIGN_OPTIONS+=(--timestamp)
else
  SIGN_OPTIONS+=(--timestamp=none)
fi
codesign "${SIGN_OPTIONS[@]}" --entitlements "$ROOT_DIR/MoreMenu/MoreMenuExtension/MoreMenuExtension.entitlements" "$EXTENSION_PATH"
codesign "${SIGN_OPTIONS[@]}" --entitlements "$ROOT_DIR/MoreMenu/MoreMenu/MoreMenu.entitlements" "$APP_PATH"
python3 "$ROOT_DIR/scripts/verify-signing.py" "$APP_PATH"
