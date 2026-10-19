#!/usr/bin/env bash
# E4-S6 acceptance: the comparison document docs/ucfs-integration/ucfs-vs-spark.md and its committed
# results docs/ucfs-integration/e4-results/{runs,values,examples}.tsv (docs/ai/tickets/E4-S6.md).
#  1. the four files exist;
#  2. acceptance/E4/doc_check.py <doc> <results>: the results cover the 12 benchmarks x 3 runs, the
#     tables of acceptance/E4/tables.py are in the document verbatim, examples are rows of examples.tsv,
#     dispatch lines, code references, bib keys, mentions, claim sweep (prints JUDGE:/CLAIM: lines for
#     the verifier);
#  3. reproducibility: a fresh run of scripts/ucfs/e4-bench.sh on pmd and luindex (the run of
#     S5_bench.sh in acceptance/E4/out/bench when it is there, else one made here) gives the committed
#     values for those two benchmarks: every key that is not a time (keys matching -ms, time, Time) has
#     the same value, the same set of keys, and the same examples.tsv rows;
#  4. tracked files unchanged by the check.
# Usage: bash acceptance/E4/S6_doc.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
DOC=docs/ucfs-integration/ucfs-vs-spark.md
RES=docs/ucfs-integration/e4-results
for f in "$DOC" "$RES/runs.tsv" "$RES/values.tsv" "$RES/examples.tsv"; do
    [ -f "$f" ] && pass "$f exists" || fail "$f missing"
done
if [ "$FAILS" -eq 0 ]; then
    python3 acceptance/E4/doc_check.py "$DOC" "$RES" > "$LOGS/S6-doc_check.txt" 2>&1
    rc=$?
    grep -v '^PASS' "$LOGS/S6-doc_check.txt" | grep -v '^JUDGE\|^CLAIM' | sed 's/^/  /'
    echo "  JUDGE lines: $(grep -c '^JUDGE' "$LOGS/S6-doc_check.txt"), CLAIM lines: $(grep -c '^CLAIM' "$LOGS/S6-doc_check.txt") (full list: $LOGS/S6-doc_check.txt)"
    [ $rc -eq 0 ] && pass "doc_check.py" || fail "doc_check.py (see $LOGS/S6-doc_check.txt)"

    REPRO="$OUT/bench"
    if [ ! -f "$REPRO/runs.tsv" ] || [ "$(cut -f1 "$REPRO/runs.tsv" | sort -u | tr '\n' ' ')" != "bench luindex pmd " ]; then
        FRESH="$OUT/qilin-fat.jar"
        fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S6_doc; }
        REPRO="$OUT/bench-s6"
        safe_reset_dir "$REPRO"
        QILIN_JAR="$FRESH" TIMEOUT=600 XMX=8g bash scripts/ucfs/e4-bench.sh "$REPRO" pmd luindex > "$LOGS/S6-bench.txt" 2>&1 \
            || fail "e4-bench.sh pmd luindex (see $LOGS/S6-bench.txt)"
    fi
    echo "  reproducibility run: $REPRO"
    python3 - "$RES" "$REPRO" <<'PY'
import os, re, sys
res, rep = sys.argv[1:3]
TIME = re.compile(r"-ms$|time|Time")
def vals(d):
    out = {}
    for l in open(os.path.join(d, "values.tsv")):
        f = l.rstrip("\n").split("\t")
        if len(f) == 4 and f[0] in ("pmd", "luindex") and not TIME.search(f[2]):
            out[(f[0], f[1], f[2])] = f[3]
    return out
def ex(d):
    return sorted(l for l in open(os.path.join(d, "examples.tsv")) if l.split("\t")[0] in ("pmd", "luindex"))
a, b = vals(res), vals(rep)
bad = 0
if set(a) != set(b):
    print("FAIL: keys differ: committed only %s, fresh only %s" % (sorted(set(a) - set(b))[:5], sorted(set(b) - set(a))[:5])); bad += 1
diff = [(k, a[k], b[k]) for k in sorted(set(a) & set(b)) if a[k] != b[k]]
for d in diff[:5]:
    print("FAIL: %s committed %s, fresh %s" % d)
bad += len(diff)
if ex(res) != ex(rep):
    print("FAIL: examples.tsv rows of pmd/luindex differ"); bad += 1
print(("PASS: committed values of pmd and luindex reproduced (%d keys, examples equal)" % len(a)) if not bad else "RESULT-PY: FAIL")
sys.exit(1 if bad else 0)
PY
    rc=$?
    [ $rc -eq 0 ] && pass "committed results reproduced on pmd and luindex" || fail "results not reproduced"
fi
tree_clean
finish S6_doc
