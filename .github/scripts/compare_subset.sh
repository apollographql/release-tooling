#!/usr/bin/env bash

set -uo pipefail

COMBINED_FILE=$1
SPLIT_FILE=$2
KEY=$3

function run_comparison() {
    COMBINED_FILE=$1
    SPLIT_FILE=$2
    KEY=$3

    diff --new-line-format="%L" --old-line-format="" --unchanged-line-format="" \
      <(yq "$KEY" "$COMBINED_FILE") <(yq "$KEY" "$SPLIT_FILE")
}

# Compare split to combined
S_TO_C_COMPARE_MARKER=$(run_comparison "$SPLIT_FILE" "$COMBINED_FILE" "$KEY" | wc -l)
# Compare combined to split
C_TO_S_COMPARE_MARKER=$(run_comparison "$COMBINED_FILE" "$SPLIT_FILE" "$KEY" | wc -l)

# If either of the two (or both) come back as 0 then we have a subset. Annoyingly we can't use the result directly
# as Bash's handling of booleans leaves something to be desired
if [ "$S_TO_C_COMPARE_MARKER" -eq "0" ] || [ "$C_TO_S_COMPARE_MARKER" -eq "0" ]
then
    echo "✅ $SPLIT_FILE is a subset of $COMBINED_FILE at key $KEY"
    exit 0
else
    echo "❌ $SPLIT_FILE is a NOT a subset of $COMBINED_FILE at key $KEY"
    echo "Comparing Split File To Combined:"
    run_comparison "$SPLIT_FILE" "$COMBINED_FILE" "$KEY"
    echo "Comparing Combined File To Split:"
    run_comparison "$COMBINED_FILE" "$SPLIT_FILE" "$KEY"
    exit 1
fi
