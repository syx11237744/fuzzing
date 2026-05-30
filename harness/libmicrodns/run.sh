#!/usr/bin/env bash
# Run the libmicrodns libFuzzer harness. Default: 10 minutes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/fuzz_mdns"
WORK="$ROOT/build/corpus/libmicrodns"
SEEDS="$ROOT/corpus/libmicrodns/seeds"
FINDINGS="$ROOT/build/findings/libmicrodns"
LOGDIR="$ROOT/build/logs/libmicrodns"
DICT="$ROOT/harness/libmicrodns/dns.dict"
TIME="${TIME:-600}"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found. Run harness/libmicrodns/build.sh first." >&2
    exit 1
fi

mkdir -p "$WORK" "$FINDINGS" "$LOGDIR"
LOG="$LOGDIR/fuzz-$(date +%Y%m%d-%H%M%S).log"

echo "logging to: $LOG"
echo "max time:   ${TIME}s"
echo

exec "$BIN" \
    -fork=1 \
    -ignore_crashes=1 \
    -ignore_timeouts=1 \
    -max_total_time="$TIME" \
    -max_len=4096 \
    -dict="$DICT" \
    -artifact_prefix="$FINDINGS/" \
    -print_final_stats=1 \
    "$WORK" "$SEEDS" 2>&1 | tee "$LOG"
