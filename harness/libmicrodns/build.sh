#!/usr/bin/env bash
# Build the libmicrodns libFuzzer harness without requiring meson/ninja.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/libmicrodns}"
if [ ! -f "$SRC_DIR/src/mdns.c" ]; then
    SRC_DIR="$ROOT/targets/targets/libmicrodns"
fi
OUT="$ROOT/build/fuzz_mdns"

if [ ! -f "$SRC_DIR/src/mdns.c" ]; then
    echo "error: libmicrodns source not found. Expected targets/libmicrodns or targets/targets/libmicrodns." >&2
    exit 1
fi

mkdir -p "$ROOT/build"

"$LLVM_BIN/clang" \
    -g -O1 \
    ${SDKROOT:+-isysroot "$SDKROOT"} \
    -fsanitize=fuzzer,address \
    -DHAVE_POLL=1 \
    -DHAVE_STRUCT_POLLFD=1 \
    -I "$SRC_DIR/include" \
    -I "$SRC_DIR/compat" \
    -I "$SRC_DIR/src" \
    "$ROOT/harness/libmicrodns/fuzz_mdns.c" \
    "$SRC_DIR/src/mdns.c" \
    "$SRC_DIR/src/rr.c" \
    "$SRC_DIR/compat/compat.c" \
    -o "$OUT"

echo "built: $OUT"
