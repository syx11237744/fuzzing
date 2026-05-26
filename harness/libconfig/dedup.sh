#!/usr/bin/env bash
# Group fuzz crash artifacts by their root-cause signature.
# See harness/libucl/dedup.sh for full notes; this is the libconfig variant.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${BIN:-$ROOT/build/fuzz_config}"
FINDINGS="${FINDINGS:-$ROOT/build/findings/libconfig}"

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

NOISE_FRAMES='asan|sanitizer|FuzzerLoop|FuzzerDriver|FuzzerUtil|FuzzerMain|__cxa_finalize|dyld|libsystem|start\+|RunOneTest|ExecuteCallback|ExitCallback|PrintStackTrace'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "scanning ${#artifacts[@]} crash artifact(s)..."
for f in "${artifacts[@]}"; do
    out=$(timeout 10 "$BIN" "$f" 2>&1 || true)

    sig=$(echo "$out" | grep -m1 '^SUMMARY:' | sed 's/^SUMMARY: //' || true)

    # Generic libFuzzer SUMMARY lines lack function/line info.
    # Augment with the topmost user-code stack frame.
    if echo "$sig" | grep -qE '^libFuzzer:|^$'; then
        frame=$(echo "$out" \
            | grep -oE '#[0-9]+ 0x[0-9a-f]+ in [^[:space:]]+ [^[:space:]]+' \
            | grep -vE "$NOISE_FRAMES" \
            | head -1 \
            | sed 's/^#[0-9]* 0x[0-9a-f]* in //')
        [ -n "$frame" ] && sig="${sig:-(no SUMMARY)} @ $frame"
    fi

    [ -z "$sig" ] && sig='(unknown — see fuzzer output)'

    printf '%s\t%d\t%s\n' "$sig" "$(wc -c < "$f")" "$f" >> "$tmp"
done

echo
echo "=== unique bug signatures (count) ==="
cut -f1 "$tmp" | sort | uniq -c | sort -rn

echo
echo "=== one minimal representative per bug ==="
sort -t$'\t' -k1,1 -k2,2n "$tmp" \
    | awk -F'\t' '!seen[$1]++ { printf "%-80s  %4dB  %s\n", $1, $2, $3 }'
