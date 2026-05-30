#!/usr/bin/env bash
# Build the zlib libFuzzer harness.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
SRC_DIR="${SRC_DIR:-$ROOT/targets/zlib}"
if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
    SRC_DIR="$ROOT/targets/targets/zlib"
fi
BUILD_DIR="$SRC_DIR/build-fuzz"
LIB="$BUILD_DIR/libz.a"
OUT="$ROOT/build/fuzz_zlib"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
    echo "error: zlib source not found. Expected targets/zlib or targets/targets/zlib." >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$ROOT/build"
cd "$BUILD_DIR"

cmake .. \
    -DCMAKE_C_COMPILER="$LLVM_BIN/clang" \
    ${SDKROOT:+-DCMAKE_OSX_SYSROOT="$SDKROOT"} \
    -DCMAKE_C_FLAGS="-g -O1 -fsanitize=fuzzer-no-link,address" \
    -DZLIB_BUILD_SHARED=OFF \
    -DZLIB_BUILD_STATIC=ON \
    -DZLIB_BUILD_TESTING=OFF \
    -DZLIB_INSTALL=OFF \
    >/dev/null
cmake --build . -j >/dev/null

cd "$ROOT"

"$LLVM_BIN/clang" \
    -g -O1 \
    ${SDKROOT:+-isysroot "$SDKROOT"} \
    -fsanitize=fuzzer,address \
    -I "$SRC_DIR" \
    -I "$BUILD_DIR" \
    "$ROOT/harness/zlib/fuzz_zlib.c" \
    "$LIB" \
    -o "$OUT"

echo "built: $OUT"
