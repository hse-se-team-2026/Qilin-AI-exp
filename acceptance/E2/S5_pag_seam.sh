#!/usr/bin/env bash
# E2-S5 acceptance: the seam "Qilin kernel + solver -> qilin.ucfs" works in code. After Spark
# (pta.pureRun(), kernel layers 3-4) Kotlin code of qilin.ucfs (qilin.ucfs.QilinPagSeam,
# compiled Kotlin) reads the context-insensitive PAG of the finished analysis and gets the same
# per-kind edge counts as a Java reference walk (qilin.test.ucfs.E2PagSeamTest, 2 programs of
# qilin.microben). The whole build stays green (qilin.pta >= 95 tests = 91 + 2 + 2, <= 11
# skipped, 0 failed).
#
# Needs both submodules and `bash scripts/ucfs/bootstrap.sh`.
# Usage: bash acceptance/E2/S5_pag_seam.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
# qilin.ucfs/build is not removed by `clean` while qilin.ucfs is not a Gradle project (base):
# drop it so that no stale jar or class from an earlier run can satisfy a check.
rm -rf "$ROOT/qilin.ucfs/build"

CLS=qilin.test.ucfs.E2PagSeamTest
PR=qilin.pta/build/test-results/test

rm -rf qilin.pta/build/test-results qilin.ucfs/build/test-results
gradle clean build > "$LOGS/S5-build.log" 2>&1
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/S5-build.log)"
grep -E '^e: |error:|What went wrong' -A2 "$LOGS/S5-build.log" | head -n 12
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

for t in instanceStore instanceLoad; do
    st=$(junit_case_status "$PR" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done
# the per-kind counts the test printed (for the report; the test itself compares them)
python3 - "$PR/TEST-$CLS.xml" <<'PY' 2>/dev/null
import sys, xml.etree.ElementTree as ET
so = ET.parse(sys.argv[1]).getroot().find("system-out")
for l in (so.text or "").splitlines() if so is not None else []:
    if l.startswith("E2PagSeamTest "):
        print("  " + l)
PY
read -r t s f e <<<"$(junit_summary "$PR")"
echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e"
[ "$t" -ge 95 ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
    && pass "qilin.pta: >= 95 tests, <= 11 skipped, 0 failed" || fail "qilin.pta: need >= 95 tests, <= 11 skipped, 0 failed"
read -r t s f e <<<"$(junit_summary qilin.ucfs/build/test-results/test)"
[ "$t" -ge 7 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] && pass "qilin.ucfs tests still pass ($t)" || fail "qilin.ucfs tests: need >= 7, 0 failed"

# QilinPagSeam is Kotlin code of qilin.ucfs, not a Java helper elsewhere
J=$(ls qilin.ucfs/build/libs/qilin.ucfs-*.jar 2>/dev/null | grep -v -- '-sources\|-javadoc' | head -n 1)
[ -n "$J" ] && kotlin_metadata_class "$J" qilin/ucfs/QilinPagSeam.class \
    && pass "qilin/ucfs/QilinPagSeam.class is compiled Kotlin in $(basename "$J")" \
    || fail "qilin.ucfs jar has no Kotlin class qilin/ucfs/QilinPagSeam.class"
if find qilin.pta/src qilin.core/src -name 'QilinPagSeam*' 2>/dev/null | grep -q .; then
    fail "QilinPagSeam must live only in qilin.ucfs"
else
    pass "QilinPagSeam lives only in qilin.ucfs"
fi
gradle -q :qilin.ucfs:dependencies --configuration compileClasspath > "$LOGS/S5-ucfs-compile.txt" 2>&1
grep -q 'project :qilin.pta' "$LOGS/S5-ucfs-compile.txt" && fail "qilin.ucfs depends on qilin.pta" \
    || pass "qilin.ucfs still does not depend on qilin.pta"

finish S5_pag_seam
