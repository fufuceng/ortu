#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"

forbidden_runtime='(^import (Network|WebKit)$)|(URLSession|NWConnection|WKWebView|webSocketTask|Timer\.scheduledTimer|DispatchSource\.makeTimerSource)'
if find Sources -type f -name '*.swift' -exec grep -nE "$forbidden_runtime" {} +; then
    echo "A network, web-view, or recurring-timer API violates an Örtü product invariant." >&2
    echo "Document and review the architecture/energy decision before changing this gate." >&2
    exit 1
fi

if find Sources Tests scripts -type f -name '*.swift' -exec grep -nE '(try!|as!)' {} +; then
    echo "Force try or force cast found. Model the failure explicitly." >&2
    exit 1
fi

echo "Product invariants passed"
