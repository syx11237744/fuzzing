#!/usr/bin/env bash
# Group fuzz crash artifacts by their ASan SUMMARY signature.
#
# Usage:
#   ./harness/libucl/dedup.sh                          # libucl, default paths
#   BIN=... FINDINGS=... ./harness/libucl/dedup.sh     # override
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${BIN:-$ROOT/build/fuzz_ucl}"
FINDINGS="${FINDINGS:-$ROOT/build/findings/libucl}"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found." >&2
    exit 1
fi

shopt -s nullglob
artifacts=("$FINDINGS"/crash-*)
if [ ${#artifacts[@]} -eq 0 ]; then
    echo "no crash artifacts in $FINDINGS"
    exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "scanning ${#artifacts[@]} crash artifact(s)..."
for f in "${artifacts[@]}"; do
    sig=$(timeout 10 "$BIN" "$f" 2>&1 \
        | grep -m1 '^SUMMARY:' \
        | sed 's/^SUMMARY: //' \
        || true)
    [ -z "$sig" ] && sig='(no SUMMARY — see log)'
    printf '%s\t%d\t%s\n' "$sig" "$(wc -c < "$f")" "$f" >> "$tmp"
done

echo
echo "=== unique bug signatures (count) ==="
cut -f1 "$tmp" | sort | uniq -c | sort -rn

echo
echo "=== one minimal representative per bug ==="
sort -t$'\t' -k1,1 -k2,2n "$tmp" \
    | awk -F'\t' '!seen[$1]++ { printf "%-80s  %4dB  %s\n", $1, $2, $3 }'