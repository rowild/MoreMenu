#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_PROJECT="$ROOT_DIR/MoreMenu/MoreMenu.xcodeproj"
SCHEME="${SCHEME:-MoreMenu}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
APP_NAME="MoreMenu.app"
PRODUCT_NAME="MoreMenu"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/release-derived-data}"
BUILD_PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_PATH="$BUILD_PRODUCTS_DIR/$APP_NAME"
EXTENSION_PATH="$APP_PATH/Contents/PlugIns/MoreMenuExtension.appex"
APP_ENTITLEMENTS_PATH="$ROOT_DIR/MoreMenu/MoreMenu/MoreMenu.entitlements"
EXTENSION_ENTITLEMENTS_PATH="$ROOT_DIR/MoreMenu/MoreMenuExtension/MoreMenuExtension.entitlements"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
STAGE_DIR="$ROOT_DIR/.build/dmg-stage"
VERSION="${VERSION:-$(grep -m1 'MARKETING_VERSION' "$XCODE_PROJECT/project.pbxproj" | sed 's/.*MARKETING_VERSION = //;s/;//;s/[[:space:]]//g')}"
DMG_NAME="${DMG_NAME:-${PRODUCT_NAME}-v${VERSION}.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

if [[ -z "$VERSION" ]]; then
  echo "Could not determine MARKETING_VERSION from project.pbxproj."
  exit 1
fi

echo "==> Building $APP_NAME ($CONFIGURATION) — version $VERSION"
rm -rf "$DERIVED_DATA_PATH"
xcodebuild \
  -project "$XCODE_PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but the app bundle was not found at:"
  echo "  $APP_PATH"
  exit 1
fi

echo "==> Applying ad hoc bundle signatures for distributable packaging"
# Sign extension first (inner bundles must be signed before the container)
codesign --force --sign - --timestamp=none \
  --entitlements "$EXTENSION_ENTITLEMENTS_PATH" \
  "$EXTENSION_PATH"
codesign --force --sign - --timestamp=none \
  --entitlements "$APP_ENTITLEMENTS_PATH" \
  "$APP_PATH"

echo "==> Preparing DMG staging folder"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "$PRODUCT_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Created DMG:"
echo "  $DMG_PATH"
echo
echo "Next step:"
echo "  Upload this DMG to a GitHub Release."
