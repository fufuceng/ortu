#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$PROJECT_DIR"

echo "==> Checking product invariants"
"$SCRIPT_DIR/check-invariants.sh"

echo "==> Linting changed Swift sources"
"$SCRIPT_DIR/lint-changed.sh"

echo "==> Running tests with coverage and warnings as errors"
if [ "${ORTU_DISABLE_SWIFTPM_SANDBOX:-0}" = "1" ]; then
    swift test --disable-sandbox --parallel --enable-code-coverage -Xswiftc -warnings-as-errors
else
    swift test --parallel --enable-code-coverage -Xswiftc -warnings-as-errors
fi

"$SCRIPT_DIR/coverage-report.sh"

echo "==> Building and verifying the local application bundle"
"$SCRIPT_DIR/package-local.sh"
plutil -lint Packaging/Info.plist
codesign --verify --deep --strict dist/Ortu.app

echo "==> Validating built-in cover packs with the release binary"
for pack in Sources/Ortu/Resources/BuiltinPacks/*.ortupack; do
    dist/Ortu.app/Contents/MacOS/Ortu --validate-pack "$pack"
done

echo "==> All quality checks passed"
