#!/usr/bin/env bash
# E6-S7 acceptance (mechanics of the judgment story): the document docs/ucfs-integration/cflidr-export.md
# against the code at its pins and the committed probe results docs/ucfs-integration/e6-results
# (docs/ai/tickets/E6-S7.md). Runs acceptance/E6/doc_check.py (rules in its docstring) and prints its
# JUDGE:, CLAIM: and NUMBER: lines for the verifier, who judges all prose of sections 1-7.
# Usage: bash acceptance/E6/S7_doc.sh          (exit 0 = PASS; seconds; needs .cflidr/src at cflidrCommit)
source "$(dirname "$0")/lib.sh"
DOC="$ROOT/docs/ucfs-integration/cflidr-export.md"
R="$ROOT/docs/ucfs-integration/e6-results"
[ -f "$DOC" ] && pass "document exists" || { fail "no $DOC"; finish S7_doc; }
[ -f "$R/runs.tsv" ] && pass "results exist" || { fail "no results in $R"; finish S7_doc; }
[ -d "$ROOT/.cflidr/src/.git" ] || die_env "no .cflidr/src: run 'bash scripts/cflidr/bootstrap.sh'"
python3 acceptance/E6/doc_check.py "$DOC" "$R" > "$LOGS/S7-doc_check.txt" 2>&1
rc=$?
grep -E '^(FAIL|JUDGE|CLAIM|NUMBER):' "$LOGS/S7-doc_check.txt" | head -n 400
echo "  doc_check: $(grep -c '^JUDGE:' "$LOGS/S7-doc_check.txt") JUDGE, $(grep -c '^CLAIM:' "$LOGS/S7-doc_check.txt") CLAIM, $(grep -c '^NUMBER:' "$LOGS/S7-doc_check.txt") NUMBER (full log: $LOGS/S7-doc_check.txt)"
[ $rc -eq 0 ] && pass "doc_check.py" || fail "doc_check.py exit $rc"
tracked_clean S7
finish S7_doc
