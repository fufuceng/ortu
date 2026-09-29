#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FORMAT_BASE=${ORTU_FORMAT_BASE:-}

cd "$PROJECT_DIR"

if [ "${ORTU_FORMAT_ALL:-0}" = "1" ]; then
    swift format lint \
        --configuration .swift-format \
        --recursive \
        --strict \
        --parallel \
        Sources Tests scripts/prepare-lace-pack.swift Package.swift
    exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "No Git worktree found; incremental format check skipped. Use ORTU_FORMAT_ALL=1 for a full audit."
    exit 0
fi

if [ -z "$FORMAT_BASE" ]; then
    if git rev-parse HEAD^ >/dev/null 2>&1; then
        FORMAT_BASE=HEAD^
    else
        echo "No base revision found; incremental format check skipped."
        exit 0
    fi
fi

if ! git cat-file -e "$FORMAT_BASE^{commit}" 2>/dev/null; then
    echo "Base revision $FORMAT_BASE is unavailable; incremental format check skipped."
    exit 0
fi

changed_files=$(git diff --name-only --diff-filter=ACMR "$FORMAT_BASE" HEAD -- '*.swift')
if [ -z "$changed_files" ]; then
    echo "No changed Swift files to lint."
    exit 0
fi

echo "$changed_files" | while IFS= read -r file; do
    [ -f "$file" ] || continue
    echo "linting $file"
    swift format lint --configuration .swift-format --strict "$file"
done
