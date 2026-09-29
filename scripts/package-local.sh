#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/Ortu.app"
STAGING_ROOT="$BUILD_DIR/package-stage"
STAGED_APP="$STAGING_ROOT/Ortu.app"
CONTENTS_DIR="$STAGED_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"

swift build \
    --disable-sandbox \
    --scratch-path "$BUILD_DIR" \
    --configuration release

rm -rf "$STAGING_ROOT"
install -d "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BUILD_DIR/release/Ortu" "$MACOS_DIR/Ortu"
install -m 644 "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$BUILD_DIR/release/Ortu_Ortu.bundle" "$RESOURCES_DIR/Ortu_Ortu.bundle"

codesign --force --sign - --timestamp=none "$STAGED_APP"

rm -rf "$APP_DIR"
install -d "$PROJECT_DIR/dist"
mv "$STAGED_APP" "$APP_DIR"
rm -rf "$STAGING_ROOT"

echo "$APP_DIR"
