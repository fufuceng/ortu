#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <semantic-version>" >&2
    exit 64
fi

VERSION=$1
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Release version must use x.y.z format: $VERSION" >&2
    exit 64
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$PROJECT_DIR/.build/release-universal"
STAGING_ROOT="$PROJECT_DIR/.build/release-stage"
APP_DIR="$STAGING_ROOT/Ortu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_ROOT="$STAGING_ROOT/dmg"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="Ortu-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
BUILD_NUMBER=${GITHUB_RUN_NUMBER:-1}

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"

swift build \
    --disable-sandbox \
    --scratch-path "$BUILD_DIR" \
    --configuration release \
    --arch arm64 \
    --arch x86_64

BIN_DIR=$(swift build \
    --disable-sandbox \
    --scratch-path "$BUILD_DIR" \
    --configuration release \
    --arch arm64 \
    --arch x86_64 \
    --show-bin-path)

rm -rf "$STAGING_ROOT"
install -d "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_ROOT" "$DIST_DIR"
install -m 755 "$BIN_DIR/Ortu" "$MACOS_DIR/Ortu"
install -m 644 "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$BIN_DIR/Ortu_Ortu.bundle" "$RESOURCES_DIR/Ortu_Ortu.bundle"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

# Ad-hoc signing preserves bundle integrity but does not establish an Apple-verified developer identity.
codesign --force --deep --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
lipo "$MACOS_DIR/Ortu" -verify_arch arm64 x86_64

ditto "$APP_DIR" "$DMG_ROOT/Ortu.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
    -volname "Örtü $VERSION" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "$DMG_PATH"
echo "$DMG_PATH.sha256"
