#!/usr/bin/env bash
# Run the zlib libFuzzer harness. Default: 10 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/fuzz_zlib"
WORK="$ROOT/build/corpus/zlib"
SEEDS="$ROOT/corpus/zlib/seeds"
FINDINGS="$ROOT/build/findings/zlib"
LOGDIR="$ROOT/build/logs/zlib"
DICT="$ROOT/harness/zlib/zlib.dict"
TIME="${TIME:-600}"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found. Run harness/zlib/build.sh first." >&2
    exit 1
fi

mkdir -p "$WORK" "$FINDINGS" "$LOGDIR"
LOG="$LOGDIR/fuzz-$(date +%Y%m%d-%H%M%S).log"

echo "logging to: $LOG"
echo "max time:   ${TIME}s"
echo

exec "$BIN" \
    -max_total_time="$TIME" \
    -max_len=4096 \
    -dict="$DICT" \
    -artifact_prefix="$FINDINGS/" \
    -print_final_stats=1 \
    "$WORK" "$SEEDS" 2>&1 | tee "$LOG"
