#!/usr/bin/env bash
# Run the libconfig libFuzzer harness for 12 hours.
#
# Layout matches harness/libexpat/run.sh; see that file for rationale.
#
# Usage:
#   tmux new -s confuzz
#   ./harness/libconfig/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/build/fuzz_config"
WORK="$ROOT/build/corpus/libconfig"
SEEDS="$ROOT/corpus/libconfig/seeds"
FINDINGS="$ROOT/build/findings/libconfig"
LOGDIR="$ROOT/build/logs/libconfig"
DICT="$ROOT/harness/libconfig/config.dict"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found. Run harness/libconfig/build.sh first." >&2
    exit 1
fi

mkdir -p "$WORK" "$FINDINGS" "$LOGDIR"
LOG="$LOGDIR/fuzz-$(date +%Y%m%d-%H%M%S).log"

echo "logging to: $LOG"
echo "corpus:     $WORK"
echo "seeds:      $SEEDS"
echo "findings:   $FINDINGS"
echo

# fork mode: keep fuzzing through crashes/exits.
#   -fork=1            parent + 1 worker; worker dies → parent respawns
#   -ignore_crashes=1  parent doesn't propagate worker's crash exit
#   -ignore_timeouts=1 same for timeouts
# We expect libconfig to hit `yy_fatal_error → exit()` whenever the flex
# lexer chokes on malformed input; without fork mode the run stops at the
# first such hit. Dedup happens post-run via dedup.sh.
exec "$BIN" \
    -fork=1 \
    -ignore_crashes=1 \
    -ignore_timeouts=1 \
    -max_total_time=43200 \
    -max_len=4096 \
    -dict="$DICT" \
    -artifact_prefix="$FINDINGS/" \
    -print_final_stats=1 \
    "$WORK" "$SEEDS" 2>&1 | tee "$LOG"
