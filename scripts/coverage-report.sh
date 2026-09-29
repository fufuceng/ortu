#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MINIMUM_LINE_COVERAGE=${MINIMUM_LINE_COVERAGE:-55}

cd "$PROJECT_DIR"

test_binary=$(find .build -type f -path '*OrtuPackageTests.xctest/Contents/MacOS/OrtuPackageTests' | head -n 1)
profile=$(find .build -type f -path '*/codecov/default.profdata' | head -n 1)

if [ -z "$test_binary" ] || [ -z "$profile" ]; then
    echo "coverage artifacts were not found; run 'swift test --enable-code-coverage' first" >&2
    exit 1
fi

report=$(xcrun llvm-cov report "$test_binary" \
    -instr-profile "$profile" \
    -ignore-filename-regex='Tests|resource_bundle_accessor')
printf '%s\n' "$report"

line_coverage=$(printf '%s\n' "$report" | awk '$1 == "TOTAL" { value=$10; gsub("%", "", value); print value }')
if [ -z "$line_coverage" ]; then
    echo "could not read total line coverage" >&2
    exit 1
fi

if ! awk -v actual="$line_coverage" -v minimum="$MINIMUM_LINE_COVERAGE" \
    'BEGIN { exit !(actual + 0 >= minimum + 0) }'; then
    echo "line coverage ${line_coverage}% is below the ${MINIMUM_LINE_COVERAGE}% floor" >&2
    exit 1
fi

echo "line coverage ${line_coverage}% meets the ${MINIMUM_LINE_COVERAGE}% floor"
