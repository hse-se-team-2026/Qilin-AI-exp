#!/usr/bin/env bash
# E2-S5 acceptance: the seam "Qilin kernel + solver -> qilin.ucfs" works in code, from Java
# production code down to Kotlin, and exports the graph E3 needs: the GLOBAL PAG of the finished
# analysis (pta.getPag() maps alloc/simple/load/store after pureRun(), i.e. the parameterized
# MethodPAG edges plus the edges the kernel derived: receiver object -> this, argument ->
# parameter, return -> receiver variable, x -> o.f and o.f -> y).
#  1. Kotlin API qilin.ucfs.QilinPagSeam.globalEdges(PTA) (compiled Kotlin, only in qilin.ucfs);
#     the Java test qilin.test.ucfs.E2PagSeamTest passes on 3 programs of qilin.microben
#     (oracles: inverse maps of the PAG, context nodes, parameterized MethodPAG edges contained,
#     fixed facts of the programs; see the test). `clean build` stays green.
#  2. Production Java code of qilin.pta calls it: the CLI option -ucfsseam prints, after the
#     analysis, the per-kind edge counts of QilinPagSeam.globalEdges as
#       #UCFS-seam-NEW: <n>   #UCFS-seam-ASSIGN: <n>   #UCFS-seam-LOAD: <n>   #UCFS-seam-STORE: <n>
#     Oracle: Qilin's own counter qilin.stat.PAGStat printed by the same run with -stats
#     (#Alloc-pag-edge, #Simple-pag-edge, #Load-pag-edge, #Store-pag-edge), for Spark (insens),
#     2-object-sensitive (2o, a larger context-sensitive PAG) and staged Eagle (E-2o) on
#     docs/example/example01. Without the option nothing is printed and the statistics do not change.
#
# Needs both submodules and `bash scripts/ucfs/bootstrap.sh`.
# Usage: bash acceptance/E2/S5_pag_seam.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
# drop stale outputs so that no jar or class from an earlier run can satisfy a check
rm -rf "$ROOT/qilin.ucfs/build"

CLS=qilin.test.ucfs.E2PagSeamTest
PR=qilin.pta/build/test-results/test

# --- 1. Kotlin seam, Java test -----------------------------------------------------------------
rm -rf qilin.pta/build/test-results qilin.ucfs/build/test-results
gradle clean build > "$LOGS/S5-build.log" 2>&1
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/S5-build.log)"
grep -E '^e: |error:|What went wrong' -A2 "$LOGS/S5-build.log" | head -n 12
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

for t in virtualCall1 instanceStore instanceLoad; do
    st=$(junit_case_status "$PR" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done
python3 - "$PR/TEST-$CLS.xml" <<'PY' 2>/dev/null
import sys, xml.etree.ElementTree as ET
so = ET.parse(sys.argv[1]).getroot().find("system-out")
for l in (so.text or "").splitlines() if so is not None else []:
    if l.startswith("E2PagSeamTest "):
        print("  " + l)
PY
read -r t s f e <<<"$(junit_summary "$PR")"
echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e"
[ "$t" -ge 96 ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
    && pass "qilin.pta: >= 96 tests (91 + 2 + 3), <= 11 skipped, 0 failed" || fail "qilin.pta: need >= 96 tests, <= 11 skipped, 0 failed"
read -r t s f e <<<"$(junit_summary qilin.ucfs/build/test-results/test)"
[ "$t" -ge 7 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] && pass "qilin.ucfs tests still pass ($t)" || fail "qilin.ucfs tests: need >= 7, 0 failed"

J=$(ls qilin.ucfs/build/libs/qilin.ucfs-*.jar 2>/dev/null | grep -v -- '-sources\|-javadoc' | head -n 1)
[ -n "$J" ] && kotlin_metadata_class "$J" qilin/ucfs/QilinPagSeam.class \
    && pass "qilin/ucfs/QilinPagSeam.class is compiled Kotlin in $(basename "$J")" \
    || fail "qilin.ucfs jar has no Kotlin class qilin/ucfs/QilinPagSeam.class"
if find qilin.pta/src qilin.core/src qilin.util/src -name 'QilinPagSeam*' 2>/dev/null | grep -q .; then
    fail "QilinPagSeam must live only in qilin.ucfs"
else
    pass "QilinPagSeam lives only in qilin.ucfs"
fi
gradle -q :qilin.ucfs:dependencies --configuration compileClasspath > "$LOGS/S5-ucfs-compile.txt" 2>&1
grep -q 'project :qilin.pta' "$LOGS/S5-ucfs-compile.txt" && fail "qilin.ucfs depends on qilin.pta" \
    || pass "qilin.ucfs still does not depend on qilin.pta"

# --- 2. production Java caller and the CLI -----------------------------------------------------
callers=$(grep -rlE 'qilin\.ucfs\.QilinPagSeam|import qilin\.ucfs\.\*;' qilin.pta/src --include='*.java' 2>/dev/null)
[ -n "$callers" ] && pass "production Java code calls QilinPagSeam: $(echo $callers)" \
    || fail "no Java file under qilin.pta/src uses qilin.ucfs.QilinPagSeam"

FRESH="$OUT/qilin-fat.jar"
build_fatjar "$FRESH" clean fatJar -x test
rc=$?
echo "gradle clean fatJar -x test exit code: $rc (log: $LOGS/fatjar.log)"
if [ $rc -ne 0 ] || [ ! -f "$FRESH" ]; then
    fail "clean fatJar -x test (exit $rc)"
    finish S5_pag_seam
fi

# metric <metrics.txt> <name> -> the number after "<name>:" (first match), or empty
metric() {
    sed -nE "s/^[[:space:]]*$2:[[:space:]]+([0-9]+)[[:space:]]*$/\1/p" "$1" | head -n 1
}

for p in insens 2o E-2o; do
    run_qilin "$FRESH" "seam-$p" -pta="$p" -se -stats -ucfsseam; rc=$?
    m="$OUT/run-seam-$p/metrics.txt"
    if [ $rc -ne 0 ]; then
        fail "$p: '-pta=$p -se -stats -ucfsseam' exit $rc (see $OUT/run-seam-$p/out.txt)"
        continue
    fi
    nseam=$(grep -cE '^#UCFS-seam-(NEW|ASSIGN|LOAD|STORE):[[:space:]]+[0-9]+[[:space:]]*$' "$m")
    [ "$nseam" -eq 4 ] && pass "$p: -ucfsseam prints the 4 lines #UCFS-seam-{NEW,ASSIGN,LOAD,STORE}" \
        || fail "$p: expected 4 lines '#UCFS-seam-<KIND>: <n>', found $nseam"
    for pair in NEW:Alloc-pag-edge ASSIGN:Simple-pag-edge LOAD:Load-pag-edge STORE:Store-pag-edge; do
        k="${pair%%:*}"; q="${pair#*:}"
        a="$(metric "$m" "#UCFS-seam-$k")"; b="$(metric "$m" "#$q")"
        if [ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ]; then
            pass "$p: #UCFS-seam-$k = #$q of qilin.stat.PAGStat ($a)"
        else
            fail "$p: #UCFS-seam-$k = '$a', but Qilin's #$q = '$b'"
        fi
    done
    [ "$(metric "$m" "#UCFS-seam-NEW")" != 0 ] && [ "$(metric "$m" "#UCFS-seam-ASSIGN")" != 0 ] \
        && pass "$p: NEW and ASSIGN edges exported (non-empty graph)" || fail "$p: empty export"
done

# without the option: no seam lines, the rest of the statistics as with it (same analysis)
run_qilin "$FRESH" "noseam-insens" -pta=insens -se -stats; rc=$?
grep -q '^#UCFS-seam-' "$OUT/run-noseam-insens/metrics.txt" \
    && fail "seam lines printed without -ucfsseam" || pass "no seam lines without -ucfsseam"
stable() { grep -v '^#UCFS-seam-' "$1"; }
if [ $rc -eq 0 ] && [ -n "$(stable "$OUT/run-noseam-insens/metrics.txt")" ] \
    && [ "$(stable "$OUT/run-noseam-insens/metrics.txt")" = "$(stable "$OUT/run-seam-insens/metrics.txt")" ]; then
    pass "statistics without -ucfsseam = with it ($(stable "$OUT/run-noseam-insens/metrics.txt" | wc -l) lines compared)"
else
    fail "statistics differ with and without -ucfsseam (exit $rc)"
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] && pass "working tree clean after the check" \
    || fail "tracked files changed by the check: $(git status --porcelain --untracked-files=no | head -3)"

finish S5_pag_seam
