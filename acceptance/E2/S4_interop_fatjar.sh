#!/usr/bin/env bash
# E2-S4 acceptance: Java code of Qilin calls the Kotlin module, and the CLI jar carries it.
#  1. qilin.pta depends on qilin.ucfs; the Java test qilin.test.ucfs.E2KotlinInteropTest passes;
#     `clean build` stays green (qilin.pta >= 93 tests = 91 + 2, <= 11 skipped, 0 failed).
#  2. The runtime classpath of the root project (what fatJar packs) resolves: it has qilin.ucfs
#     and org.ucfs:solver, no logback-classic (with it Soot prints DEBUG lines: 82 on example01
#     in the planner's prototype), one kotlin-stdlib version (= solver POM).
#  3. `gradle clean fatJar -x test` in ONE run works and packs fresh classes. On base 73db8b4 it
#     fails ("Cannot expand ZIP .../qilin.pta-0.9.9-SNAPSHOT.jar as it does not exist") because
#     fatJar does not depend on the subproject jars; without clean it packs stale jars.
#  4. The fresh jar runs example01 with the same '#' statistics as the committed jar
#     (insens, E-2o) and prints no DEBUG lines; no duplicate kotlin/ classes in the jar.
#
# Needs both submodules and `bash scripts/ucfs/bootstrap.sh`.
# Usage: bash acceptance/E2/S4_interop_fatjar.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
# qilin.ucfs/build is not removed by `clean` while qilin.ucfs is not a Gradle project (base):
# drop it so that no stale jar or class from an earlier run can satisfy a check.
rm -rf "$ROOT/qilin.ucfs/build"

V="$(ucfs_version)"
STDLIB="$(pom_stdlib_version)"
[ -n "$STDLIB" ] || die_env "cannot read the kotlin-stdlib version from the solver POM"
CLS=qilin.test.ucfs.E2KotlinInteropTest

# --- 1. Java -> Kotlin -------------------------------------------------------------------------
gradle -q :qilin.pta:dependencies --configuration compileClasspath > "$LOGS/S4-pta-compile.txt" 2>&1
grep -q 'project :qilin.ucfs' "$LOGS/S4-pta-compile.txt" && pass "qilin.pta depends on qilin.ucfs" \
    || fail "qilin.pta does not depend on project :qilin.ucfs"

rm -rf qilin.pta/build/test-results qilin.ucfs/build/test-results
gradle clean build > "$LOGS/S4-build.log" 2>&1
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/S4-build.log)"
grep -E '^e: |error:|What went wrong' -A2 "$LOGS/S4-build.log" | head -n 12
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
for t in javaCallsKotlinSolver kotlinDataClassesBehaveAsValuesInJava; do
    st=$(junit_case_status qilin.pta/build/test-results/test "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done
read -r t s f e <<<"$(junit_summary qilin.pta/build/test-results/test)"
echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e"
[ "$t" -ge 93 ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
    && pass "qilin.pta: >= 93 tests, <= 11 skipped, 0 failed" || fail "qilin.pta: need >= 93 tests, <= 11 skipped, 0 failed"
read -r t s f e <<<"$(junit_summary qilin.ucfs/build/test-results/test)"
echo "  qilin.ucfs: tests=$t skipped=$s failures=$f errors=$e"
[ "$t" -ge 7 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] && pass "qilin.ucfs tests still pass" || fail "qilin.ucfs tests: need >= 7, 0 failed"

# --- 2. runtime classpath of the CLI -----------------------------------------------------------
gradle -q dependencies --configuration runtimeClasspath > "$LOGS/S4-root-runtime.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && ! grep -q FAILED "$LOGS/S4-root-runtime.txt" && pass "root runtimeClasspath resolves" \
    || fail "root runtimeClasspath does not resolve (exit $rc, see $LOGS/S4-root-runtime.txt)"
grep -q 'project :qilin.ucfs' "$LOGS/S4-root-runtime.txt" && grep -qE "org\.ucfs:solver:$V( |$)" "$LOGS/S4-root-runtime.txt" \
    && pass "root runtimeClasspath has qilin.ucfs and org.ucfs:solver:$V" || fail "root runtimeClasspath lacks qilin.ucfs or org.ucfs:solver:$V"
lb="$(resolved_versions "$LOGS/S4-root-runtime.txt" ch.qos.logback:logback-classic)"
[ -z "$lb" ] && pass "no logback-classic on the root runtime classpath" || fail "logback-classic $lb on the root runtime classpath"
sv="$(resolved_versions "$LOGS/S4-root-runtime.txt" org.jetbrains.kotlin:kotlin-stdlib)"
[ "$sv" = "$STDLIB" ] && pass "kotlin-stdlib resolves to one version $sv" || fail "kotlin-stdlib resolves to '$sv', expected only $STDLIB"

# --- 3. clean fatJar in one Gradle run ---------------------------------------------------------
FRESH="$OUT/qilin-fat.jar"
build_fatjar "$FRESH" clean fatJar -x test
rc=$?
echo "gradle clean fatJar -x test exit code: $rc (log: $LOGS/fatjar.log)"
grep -E 'What went wrong' -A2 "$LOGS/fatjar.log" | head -n 4
if [ $rc -eq 0 ] && [ -f "$FRESH" ]; then
    pass "clean fatJar -x test works in one run"
    unzip -Z1 "$FRESH" > "$OUT/fatjar-entries.txt"
    for e in driver/Main.class qilin/ucfs/UcfsSolver.class org/ucfs/parser/Gll.class kotlin/Unit.class; do
        grep -qxF "$e" "$OUT/fatjar-entries.txt" && pass "fat jar contains $e" || fail "fat jar lacks $e"
    done
    grep -q '^ch/qos/logback/' "$OUT/fatjar-entries.txt" && fail "fat jar contains ch/qos/logback" || pass "fat jar has no logback"
    nd=$(sort "$OUT/fatjar-entries.txt" | uniq -d | grep -c '^kotlin/.*\.class$')
    [ "$nd" -eq 0 ] && pass "no duplicate kotlin/ classes in the fat jar" || fail "$nd duplicate kotlin/ classes in the fat jar"
    # freshness: classes in the fat jar are the ones just compiled
    for pair in "driver/PTAOption.class|qilin.pta/build/classes/java/main" "qilin/ucfs/UcfsSolver.class|qilin.ucfs/build/classes/kotlin/main"; do
        e="${pair%%|*}"; d="${pair#*|}"
        if [ -f "$d/$e" ] && unzip -p "$FRESH" "$e" | cmp -s - "$d/$e"; then
            pass "fat jar $e = freshly compiled $d/$e"
        else
            fail "fat jar $e differs from (or no) freshly compiled $d/$e"
        fi
    done
else
    fail "clean fatJar -x test (exit $rc)"
fi
git diff --quiet HEAD -- "$COMMITTED_JAR" && pass "committed artifact jar unchanged" || fail "committed artifact jar was modified"

# --- 4. the fresh CLI jar on example01 ---------------------------------------------------------
if [ -f "$FRESH" ]; then
    for p in insens E-2o; do
        run_qilin "$COMMITTED_JAR" "$p-ref" -pta="$p" -se || die_env "reference run of the committed jar failed for -pta=$p"
        run_qilin "$FRESH" "$p-fresh" -pta "$p" -se; rc=$?
        if [ $rc -eq 0 ] && [ -s "$OUT/run-$p-fresh/metrics.txt" ] && cmp -s "$OUT/run-$p-ref/metrics.txt" "$OUT/run-$p-fresh/metrics.txt"; then
            pass "$p: fresh jar exit 0, statistics = committed jar ($(wc -l < "$OUT/run-$p-ref/metrics.txt") lines)"
        else
            fail "$p: fresh jar exit $rc or statistics differ (see $OUT/run-$p-fresh/out.txt)"
        fi
        nd=$(grep -c 'DEBUG' "$OUT/run-$p-fresh/out.txt")
        [ "$nd" -eq 0 ] && pass "$p: no DEBUG lines in the output" || fail "$p: $nd DEBUG lines in the output (logging backend on the classpath?)"
    done
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] && pass "working tree clean after the check" \
    || fail "tracked files changed by the check: $(git status --porcelain --untracked-files=no | head -3)"

finish S4_interop_fatjar
