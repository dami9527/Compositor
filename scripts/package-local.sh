#!/bin/zsh
# Builds dist/Compositor-<version>.dmg that runs on macOS 15.7 and later.
# Ad-hoc signed: this Mac has no Developer ID certificate, so the image is not notarized.
# After merging upstream, resolve conflicts, then run this script again.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
WORK="$HOME/Library/Caches/CompositorRelease"
DIST="$PROJECT_DIR/dist"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
echo "==> $APP $VERSION ($BUILD)"

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

echo "==> Release build"
xcodebuild \
  -project "$PROJECT_DIR/$APP.xcodeproj" \
  -scheme "$APP" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$WORK/DerivedData" \
  build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGNING_REQUIRED=YES

APP_PATH="$WORK/DerivedData/Build/Products/Release/$APP.app"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Disk image"
STAGE="$WORK/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_PATH" "$STAGE/$APP.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done: $DMG"
