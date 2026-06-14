#!/bin/bash
# Differential test driver: generate a fuzz corpus, run it through the Go
# reference (which matches Apple), then run the Swift differential test to
# confirm the Swift port agrees on every URL (accepted bytes + rejections).
set -euo pipefail

# GO_DIR must point at a checkout of the upstream Go reference
# (https://github.com/rs/appclipcode) with cmd/diffhelper present.
SWIFT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="${GO_DIR:-$SWIFT_DIR/../appclipcode-main}"
CORPUS="${TMPDIR:-/tmp}/acc_corpus.txt"
EXPECTED="${TMPDIR:-/tmp}/acc_expected.tsv"

echo "Generating corpus..."
python3 "$SWIFT_DIR/scripts/gen_corpus.py" > "$CORPUS"

echo "Running Go reference oracle..."
( cd "$GO_DIR" && go run ./cmd/diffhelper < "$CORPUS" > "$EXPECTED" )

ACCEPTED=$(grep -vc $'\tERROR' "$EXPECTED" || true)
REJECTED=$(grep -c $'\tERROR' "$EXPECTED" || true)
echo "Go oracle: $ACCEPTED accepted, $REJECTED rejected"

echo "Running Swift differential test..."
( cd "$SWIFT_DIR" && ACC_EXPECTED="$EXPECTED" swift test --filter testDifferentialAgainstGoReference 2>&1 | grep -E "differential:|Test Case|Executed|error:|mismatch" || true )
