#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <semantic-version> <dmg-path> <output-path>" >&2
    exit 64
fi

VERSION=$1
DMG_PATH=$2
OUTPUT_PATH=$3

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Cask version must use x.y.z format: $VERSION" >&2
    exit 64
fi
if [ ! -f "$DMG_PATH" ]; then
    echo "DMG not found: $DMG_PATH" >&2
    exit 66
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$PROJECT_DIR/Packaging/Homebrew/ortu.rb.template"
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')

mkdir -p "$(dirname -- "$OUTPUT_PATH")"
sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__SHA256__/$SHA256/g" \
    "$TEMPLATE" > "$OUTPUT_PATH"

ruby -c "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
