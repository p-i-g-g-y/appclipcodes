#!/bin/bash
# SVG differential driver: for a sample of URLs, render with every template
# index (0..17) and both logo types via the Go reference, then confirm the Swift
# port produces byte-identical SVGs (compared via SHA-256).
set -euo pipefail

# GO_DIR must point at a checkout of the upstream Go reference
# (https://github.com/rs/appclipcode) with cmd/svghelper present.
SWIFT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="${GO_DIR:-$SWIFT_DIR/../appclipcode-main}"
CORPUS="${TMPDIR:-/tmp}/acc_corpus.txt"
SVG_INPUT="${TMPDIR:-/tmp}/acc_svg_input.tsv"
SVG_EXPECTED="${TMPDIR:-/tmp}/acc_svg_expected.tsv"

# Reuse the URL corpus if present; otherwise generate it.
if [ ! -f "$CORPUS" ]; then
    python3 "$SWIFT_DIR/scripts/gen_corpus.py" > "$CORPUS"
fi

# Build the (url, index, type) matrix. Sample every Nth accepted URL to keep the
# matrix moderate, crossed with all 18 templates and both logo types.
echo "Building SVG test matrix..."
awk 'NR % 7 == 1' "$CORPUS" | while IFS= read -r url; do
    for idx in $(seq 0 17); do
        for t in cam nfc; do
            printf '%s\t%s\t%s\n' "$url" "$idx" "$t"
        done
    done
done > "$SVG_INPUT"
echo "matrix rows: $(wc -l < "$SVG_INPUT")"

echo "Running Go SVG oracle..."
( cd "$GO_DIR" && go run ./cmd/svghelper < "$SVG_INPUT" > "$SVG_EXPECTED" )

echo "Running Swift SVG differential test..."
( cd "$SWIFT_DIR" && ACC_SVG_EXPECTED="$SVG_EXPECTED" swift test --filter testSVGDifferentialAgainstGoReference 2>&1 | grep -E "svg differential:|Test Case|Executed|error:|mismatch" || true )
