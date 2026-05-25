#!/usr/bin/env bash
# Build the libexpat libFuzzer harness.
# Requires: brew-installed llvm on PATH, libexpat already built at
# targets/libexpat/expat/build-fuzz/libexpat.a with the same sanitizers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LLVM_BIN="${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}"
EXPAT_DIR="$ROOT/targets/libexpat/expat"
LIB="$EXPAT_DIR/build-fuzz/libexpat.a"
OUT="$ROOT/build/fuzz_xml"

if [ ! -f "$LIB" ]; then
    echo "error: $LIB not found. Build libexpat first." >&2
    exit 1
fi

mkdir -p "$ROOT/build"

"$LLVM_BIN/clang" \
    -g -O1 \
    -fsanitize=fuzzer,address \
    -I "$EXPAT_DIR/lib" \
    "$ROOT/harness/libexpat/fuzz_xml.c" \
    "$LIB" \
    -o "$OUT"

echo "built: $OUT"
