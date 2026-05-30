#!/usr/bin/env bash
# Group fuzz crash artifacts by sanitizer SUMMARY.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${BIN:-$ROOT/build/fuzz_mdns}"
FINDINGS="${FINDINGS:-$ROOT/build/findings/libmicrodns}"

shopt -s nullglob
artifacts=("$FINDINGS"/crash-*)
if [ ${#artifacts[@]} -eq 0 ]; then
    echo "no crash artifacts in $FINDINGS"
    exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for f in "${artifacts[@]}"; do
    out=$(timeout 10 "$BIN" "$f" 2>&1 || true)
    sig=$(echo "$out" | grep -m1 '^SUMMARY:' | sed 's/^SUMMARY: //' || true)
    [ -z "$sig" ] && sig='(unknown)'
    printf '%s\t%d\t%s\n' "$sig" "$(wc -c < "$f")" "$f" >> "$tmp"
done

cut -f1 "$tmp" | sort | uniq -c | sort -rn
sort -t$'\t' -k1,1 -k2,2n "$tmp" | awk -F'\t' '!seen[$1]++ { printf "%-80s  %4dB  %s\n", $1, $2, $3 }'
