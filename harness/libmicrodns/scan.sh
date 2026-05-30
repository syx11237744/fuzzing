#!/usr/bin/env bash
# Run Clang Static Analyzer on libmicrodns sources.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/libmicrodns}"
if [ ! -f "$SRC_DIR/src/mdns.c" ]; then
    SRC_DIR="$ROOT/targets/targets/libmicrodns"
fi
REPORT="$ROOT/build/scan-report/libmicrodns"

mkdir -p "$REPORT"

"$LLVM_BIN/scan-build" \
    --use-cc="$LLVM_BIN/clang" \
    -o "$REPORT" \
    "$LLVM_BIN/clang" \
        ${SDKROOT:+-isysroot "$SDKROOT"} \
        -DHAVE_POLL=1 \
        -DHAVE_STRUCT_POLLFD=1 \
        -I "$SRC_DIR/include" \
        -I "$SRC_DIR/compat" \
        -I "$SRC_DIR/src" \
        -c "$SRC_DIR/src/mdns.c" "$SRC_DIR/src/rr.c" "$SRC_DIR/compat/compat.c" \
        "$SRC_DIR/compat/inet.c"

rm -f mdns.o rr.o compat.o inet.o poll.o
echo "report directory: $REPORT"
