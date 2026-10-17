#!/usr/bin/env bash
# E2-S3 acceptance: Qilin has a Kotlin module qilin.ucfs that depends on qilin.core (not on
# qilin.pta) and on org.ucfs:solver from the project-local repository, and runs UCFS through
# its own API (qilin.ucfs.UcfsSolver + qilin.ucfs.grammar.AnBnGrammar):
#   qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E2UcfsSolverTest.kt (7 cases).
# The whole Qilin build stays green: `clean build` exit 0, qilin.pta >= 91 tests, <= 11 skipped,
# 0 failed (91/11/0 on base 73db8b4), and the E1 check acceptance/E1/S4_ucfs_smoke.sh passes.
#
# Needs both submodules and `bash scripts/ucfs/bootstrap.sh`.
# Usage: bash acceptance/E2/S3_ucfs_module.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
# qilin.ucfs/build is not removed by `clean` while qilin.ucfs is not a Gradle project (base):
# drop it so that no stale jar or class from an earlier run can satisfy a check.
rm -rf "$ROOT/qilin.ucfs/build"

V="$(ucfs_version)"
STDLIB="$(pom_stdlib_version)"
[ -n "$STDLIB" ] || die_env "cannot read the kotlin-stdlib version from the solver POM"
CLS=qilin.ucfs.acceptance.E2UcfsSolverTest
CASES="chainAABB unbalancedChain cycleTerminates foreignLabelsBreakPaths terminalNamesComeFromTheGrammar emptyGraph repeatedQueriesGiveTheSameAnswer"

# --- module layout (static) ------------------------------------------------------------------
grep -qE "^\s*include\s*\(?\s*['\"]:?qilin\.ucfs['\"]" settings.gradle \
    && pass "settings.gradle includes qilin.ucfs" || fail "settings.gradle does not include 'qilin.ucfs'"
[ -f qilin.ucfs/build.gradle ] || [ -f qilin.ucfs/build.gradle.kts ] \
    && pass "qilin.ucfs has a build script" || fail "qilin.ucfs/build.gradle(.kts) is missing"
grep -qE "org\.jetbrains\.kotlin\.jvm|kotlin\(\"jvm\"\)" qilin.ucfs/build.gradle* 2>/dev/null \
    && pass "qilin.ucfs applies the Kotlin JVM plugin" || fail "qilin.ucfs does not apply org.jetbrains.kotlin.jvm"
nkt=$(find qilin.ucfs/src/main/kotlin -name '*.kt' 2>/dev/null | wc -l)
njava=$(find qilin.ucfs/src/main -name '*.java' 2>/dev/null | wc -l)
[ "$nkt" -ge 1 ] && [ "$njava" -eq 0 ] && pass "main sources are Kotlin ($nkt .kt, 0 .java)" \
    || fail "main sources of qilin.ucfs must be Kotlin in src/main/kotlin ($nkt .kt, $njava .java)"
[ -f qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E2UcfsSolverTest.kt ] \
    && pass "acceptance test is in place" || fail "acceptance test qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E2UcfsSolverTest.kt is missing"
if grep -rqE '@(Ignore|Disabled)' qilin.ucfs/src/test 2>/dev/null; then
    fail "@Ignore/@Disabled in qilin.ucfs tests"
else
    pass "no @Ignore/@Disabled in qilin.ucfs tests"
fi
grep -q 'gradle-8.12-bin.zip' gradle/wrapper/gradle-wrapper.properties \
    && pass "Gradle wrapper is still 8.12" || fail "Gradle wrapper changed (must stay 8.12)"

# --- dependencies ------------------------------------------------------------------------------
gradle -q :qilin.ucfs:dependencies --configuration compileClasspath > "$LOGS/S3-ucfs-compile.txt" 2>&1
gradle -q :qilin.ucfs:dependencies --configuration runtimeClasspath > "$LOGS/S3-ucfs-runtime.txt" 2>&1
rc=$?
if [ $rc -eq 0 ] && ! grep -q 'FAILED' "$LOGS/S3-ucfs-runtime.txt" "$LOGS/S3-ucfs-compile.txt"; then
    pass ":qilin.ucfs compile/runtime classpaths resolve"
else
    fail ":qilin.ucfs dependencies do not resolve (exit $rc, see $LOGS/S3-ucfs-*.txt)"
fi
grep -q 'project :qilin.core' "$LOGS/S3-ucfs-compile.txt" && pass "qilin.ucfs depends on qilin.core" \
    || fail "qilin.ucfs does not depend on project :qilin.core"
grep -q 'project :qilin.pta' "$LOGS/S3-ucfs-compile.txt" "$LOGS/S3-ucfs-runtime.txt" \
    && fail "qilin.ucfs depends on qilin.pta (would make a cycle once qilin.pta uses qilin.ucfs)" \
    || pass "qilin.ucfs does not depend on qilin.pta"
grep -qE "org\.ucfs:solver:$V( |$)" "$LOGS/S3-ucfs-runtime.txt" && pass "runtimeClasspath has org.ucfs:solver:$V" \
    || fail "runtimeClasspath of qilin.ucfs has no org.ucfs:solver:$V"
lb="$(resolved_versions "$LOGS/S3-ucfs-runtime.txt" ch.qos.logback:logback-classic)"
[ -z "$lb" ] && pass "no logback-classic on the runtime classpath (Soot would log DEBUG through it)" \
    || fail "logback-classic $lb on the runtime classpath of qilin.ucfs"
sv="$(resolved_versions "$LOGS/S3-ucfs-runtime.txt" org.jetbrains.kotlin:kotlin-stdlib)"
[ "$sv" = "$STDLIB" ] && pass "kotlin-stdlib resolves to one version $sv (= solver POM)" \
    || fail "kotlin-stdlib resolves to '$sv', expected only $STDLIB (solver POM)"

# --- full build with tests (fresh results) -----------------------------------------------------
rm -rf qilin.pta/build/test-results qilin.ucfs/build/test-results
gradle clean build > "$LOGS/S3-build.log" 2>&1
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/S3-build.log)"
grep -E '^e: |error:|What went wrong' -A2 "$LOGS/S3-build.log" | head -n 12
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

UR=qilin.ucfs/build/test-results/test
for t in $CASES; do
    st=$(junit_case_status "$UR" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done
read -r t s f e <<<"$(junit_summary "$UR")"
echo "  qilin.ucfs: tests=$t skipped=$s failures=$f errors=$e"
[ "$f" -eq 0 ] && [ "$e" -eq 0 ] && [ "$s" -eq 0 ] && pass "qilin.ucfs: 0 failed, 0 skipped" || fail "qilin.ucfs: failures/errors/skipped present"
read -r t s f e <<<"$(junit_summary qilin.pta/build/test-results/test)"
echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e"
[ "$t" -ge 91 ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
    && pass "qilin.pta: >= 91 tests, <= 11 skipped, 0 failed" || fail "qilin.pta regressed (need >= 91 tests, <= 11 skipped, 0 failed)"

J=$(ls qilin.ucfs/build/libs/qilin.ucfs-*.jar 2>/dev/null | grep -v -- '-sources\|-javadoc' | head -n 1)
[ -n "$J" ] && kotlin_metadata_class "$J" qilin/ucfs/UcfsSolver.class \
    && pass "qilin/ucfs/UcfsSolver.class in $(basename "$J") is compiled Kotlin" \
    || fail "qilin.ucfs jar with Kotlin class qilin/ucfs/UcfsSolver.class not found"

# --- E1 regression -----------------------------------------------------------------------------
bash acceptance/E1/S4_ucfs_smoke.sh > "$LOGS/S3-E1-S4.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "acceptance/E1/S4_ucfs_smoke.sh still passes" \
    || { fail "acceptance/E1/S4_ucfs_smoke.sh exit $rc (see $LOGS/S3-E1-S4.log)"; grep -E '^FAIL' "$LOGS/S3-E1-S4.log"; }

finish S3_ucfs_module
