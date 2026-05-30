#!/usr/bin/env bash
# Build the cJSON libFuzzer harness.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/cJSON}"
if [ ! -f "$SRC_DIR/cJSON.c" ]; then
    SRC_DIR="$ROOT/targets/targets/cJSON"
fi
OUT="$ROOT/build/fuzz_cjson"

if [ ! -f "$SRC_DIR/cJSON.c" ]; then
    echo "error: cJSON source not found. Expected targets/cJSON or targets/targets/cJSON." >&2
    exit 1
fi

mkdir -p "$ROOT/build"

"$LLVM_BIN/clang" \
    -g -O1 \
    ${SDKROOT:+-isysroot "$SDKROOT"} \
    -fsanitize=fuzzer,address \
    -I "$SRC_DIR" \
    "$ROOT/harness/cjson/fuzz_cjson.c" \
    "$SRC_DIR/cJSON.c" \
    -o "$OUT"

echo "built: $OUT"
