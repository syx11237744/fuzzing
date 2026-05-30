#!/usr/bin/env bash
# Run Clang Static Analyzer on cJSON.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/cJSON}"
if [ ! -f "$SRC_DIR/cJSON.c" ]; then
    SRC_DIR="$ROOT/targets/targets/cJSON"
fi
REPORT="$ROOT/build/scan-report/cjson"

mkdir -p "$REPORT"

"$LLVM_BIN/scan-build" \
    --use-cc="$LLVM_BIN/clang" \
    -o "$REPORT" \
    "$LLVM_BIN/clang" ${SDKROOT:+-isysroot "$SDKROOT"} -I "$SRC_DIR" -c "$SRC_DIR/cJSON.c" -o /tmp/cjson-scan.o

echo "report directory: $REPORT"
