#!/usr/bin/env bash
# Run Clang Static Analyzer on zlib.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/zlib}"
if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
    SRC_DIR="$ROOT/targets/targets/zlib"
fi
BUILD_DIR="$SRC_DIR/build-scan"
REPORT="$ROOT/build/scan-report/zlib"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$REPORT"
cd "$BUILD_DIR"

"$LLVM_BIN/scan-build" \
    --use-cc="$LLVM_BIN/clang" \
    cmake .. \
        ${SDKROOT:+-DCMAKE_OSX_SYSROOT="$SDKROOT"} \
        -DCMAKE_BUILD_TYPE=Debug \
        -DZLIB_BUILD_SHARED=OFF \
        -DZLIB_BUILD_STATIC=ON \
        -DZLIB_BUILD_TESTING=OFF \
        -DZLIB_INSTALL=OFF

"$LLVM_BIN/scan-build" \
    --use-cc="$LLVM_BIN/clang" \
    -o "$REPORT" \
    cmake --build . -j

echo "report directory: $REPORT"
