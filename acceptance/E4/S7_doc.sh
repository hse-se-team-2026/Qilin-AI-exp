#!/usr/bin/env bash
# E4-S7 acceptance: the comparison document docs/ucfs-integration/ucfs-vs-spark.md on the committed
# results of the full run (docs/ucfs-integration/e4-results/, E4-S6; docs/ai/tickets/E4-S7.md).
#  1. the document and the results exist;
#  2. python3 acceptance/E4/doc_check.py <doc> <results> -> exit 0: results (12 benchmarks x 5 runs,
#     ucfs-ANALYSIS on >= 2 benchmarks with D3 coverage >= 50 %), headings and section words, the six
#     tables of acceptance/E4/tables.py verbatim (T5 in section 1, T6 in section 2), the PROBE lines of
#     probe_jdk.txt, examples, dispatch lines, code references, bib keys, mentions, sources of
#     "проверено:", claim sweep, numbers of the prose against the results, wording; it prints the
#     JUDGE:/CLAIM:/NUMBER: lines that the verifier judges;
#  3. tracked files unchanged by the check.
# The results themselves (and their reproduction) are checked by acceptance/E4/S6_results.sh.
# Usage: bash acceptance/E4/S7_doc.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
DOC=docs/ucfs-integration/ucfs-vs-spark.md
RES=docs/ucfs-integration/e4-results
for f in "$DOC" "$RES/runs.tsv" "$RES/values.tsv" "$RES/examples.tsv" "$RES/probe_jdk.txt"; do
    [ -f "$f" ] && pass "$f exists" || fail "$f missing"
done
if [ "$FAILS" -eq 0 ]; then
    python3 acceptance/E4/doc_check.py "$DOC" "$RES" > "$LOGS/S7-doc_check.txt" 2>&1
    rc=$?
    grep -v '^PASS' "$LOGS/S7-doc_check.txt" | grep -v '^JUDGE\|^CLAIM\|^NUMBER' | sed 's/^/  /'
    echo "  JUDGE lines: $(grep -c '^JUDGE' "$LOGS/S7-doc_check.txt"), CLAIM lines: $(grep -c '^CLAIM' "$LOGS/S7-doc_check.txt"), NUMBER lines: $(grep -c '^NUMBER' "$LOGS/S7-doc_check.txt") (full list: $LOGS/S7-doc_check.txt)"
    [ $rc -eq 0 ] && pass "doc_check.py" || fail "doc_check.py (see $LOGS/S7-doc_check.txt)"
fi
tree_clean
finish S7_doc
