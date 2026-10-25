#!/usr/bin/env bash
# E5-S6 acceptance (mechanics of the judgment story): the benchmark document
# docs/ucfs-integration/e5-benchmarks.md against the committed results docs/ucfs-integration/e5-results
# (docs/ai/tickets/E5-S6.md). Runs acceptance/E5/doc_check.py (rules in its docstring) and prints its
# JUDGE:, CLAIM: and NUMBER: lines for the verifier, who judges all prose of sections 2-7.
# Usage: bash acceptance/E5/S6_doc.sh          (exit 0 = PASS; seconds)
source "$(dirname "$0")/lib.sh"
DOC="$ROOT/docs/ucfs-integration/e5-benchmarks.md"
R="$ROOT/docs/ucfs-integration/e5-results"
[ -f "$DOC" ] && pass "document exists" || { fail "no $DOC"; finish S6_doc; }
[ -f "$R/bench/meta.tsv" ] && pass "results exist" || { fail "no results in $R"; finish S6_doc; }
python3 acceptance/E5/doc_check.py "$DOC" "$R" > "$LOGS/S6-doc_check.txt" 2>&1
rc=$?
grep -E '^(FAIL|JUDGE|CLAIM|NUMBER):' "$LOGS/S6-doc_check.txt" | head -n 400
echo "  doc_check: $(grep -c '^JUDGE:' "$LOGS/S6-doc_check.txt") JUDGE, $(grep -c '^CLAIM:' "$LOGS/S6-doc_check.txt") CLAIM, $(grep -c '^NUMBER:' "$LOGS/S6-doc_check.txt") NUMBER (full log: $LOGS/S6-doc_check.txt)"
[ $rc -eq 0 ] && pass "doc_check.py" || fail "doc_check.py exit $rc"
tracked_clean S6
finish S6_doc
