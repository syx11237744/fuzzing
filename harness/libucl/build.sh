#!/usr/bin/env bash
# Build the libucl libFuzzer harness.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
SRC_DIR="$ROOT/targets/libucl"
BUILD_DIR="$SRC_DIR/build-fuzz"
LIB="$BUILD_DIR/libucl.a"
OUT="$ROOT/build/fuzz_ucl"

if [ ! -f "$LIB" ] || [ "$(find "$SRC_DIR/src" -name '*.c' -newer "$LIB" | head -1)" ]; then
    echo "==> building instrumented libucl.a"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake .. \
        -DCMAKE_C_COMPILER="$LLVM_BIN/clang" \
        -DCMAKE_C_FLAGS="-g -O1 -fsanitize=fuzzer-no-link,address" \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_LUA=OFF \
        -DENABLE_LUAJIT=OFF \
        -DENABLE_URL_INCLUDE=OFF \
        -DENABLE_URL_SIGN=OFF \
        -DENABLE_UTILS=OFF \
        >/dev/null
    cmake --build . -j --target ucl >/dev/null
    cd "$ROOT"
fi

if [ ! -f "$LIB" ]; then
    echo "error: $LIB not produced; check $BUILD_DIR for cmake errors" >&2
    exit 1
fi

mkdir -p "$ROOT/build"

echo "==> linking fuzz_ucl"
"$LLVM_BIN/clang" \
    -g -O1 \
    -fsanitize=fuzzer,address \
    -I "$SRC_DIR/include" \
    "$ROOT/harness/libucl/fuzz_ucl.c" \
    "$LIB" \
    -lm \
    -o "$OUT"

echo "built: $OUT"
