#!/usr/bin/env bash
# Run the libucl libFuzzer harness for 12 hours.
#
# Usage:
#   tmux new -s uclfuzz
#   ./harness/libucl/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/fuzz_ucl"
WORK="$ROOT/build/corpus/libucl"
SEEDS="$ROOT/corpus/libucl/seeds"
FINDINGS="$ROOT/build/findings/libucl"
LOGDIR="$ROOT/build/logs/libucl"
DICT="$ROOT/harness/libucl/ucl.dict"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found. Run harness/libucl/build.sh first." >&2
    exit 1
fi

mkdir -p "$WORK" "$FINDINGS" "$LOGDIR"
LOG="$LOGDIR/fuzz-$(date +%Y%m%d-%H%M%S).log"

echo "logging to: $LOG"
echo "corpus:     $WORK"
echo "seeds:      $SEEDS"
echo "findings:   $FINDINGS"
echo

exec "$BIN" \
    -max_total_time=43200 \
    -max_len=4096 \
    -dict="$DICT" \
    -artifact_prefix="$FINDINGS/" \
    -print_final_stats=1 \
    "$WORK" "$SEEDS" 2>&1 | tee "$LOG"
