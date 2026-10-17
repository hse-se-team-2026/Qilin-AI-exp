#!/usr/bin/env bash
# E1-S4 acceptance: Qilin-AI-exp resolves org.ucfs:solver:<pinned version> from a local Maven
# repository and calls UCFS from Java (qilin.test.ucfs.UcfsDependencySmokeTest).
#
# Precondition: UCFS is published into M2_REPO (UCFS-AI-dev: bash acceptance/E1/S3_publish_local.sh,
# or ./gradlew publishToMavenLocal). M2_REPO defaults to ~/.m2/repository.
# FULL=1 additionally runs the whole Qilin build with all existing tests (needs submodules
# qilin.microben and artifact/benchmarks, see BOOT-build-Qilin-AI-exp).
# Usage: M2_REPO=/path/to/m2 [FULL=1] bash acceptance/E1/S4_ucfs_smoke.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

M2_REPO="${M2_REPO:-$HOME/.m2/repository}"
POM="$M2_REPO/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.pom"
[ -f "$POM" ] || die_env "precondition: $POM not found; publish UCFS-AI-dev first (acceptance/E1/S3_publish_local.sh)"
echo "using M2_REPO=$M2_REPO"

RES=qilin.pta/build/test-results/test
LOGS=acceptance/E1/out/logs; mkdir -p "$LOGS"   # not under build/: FULL=1 runs clean
CLS=qilin.test.ucfs.UcfsDependencySmokeTest

gradle :qilin.pta:test --rerun --tests "$CLS" "-Dmaven.repo.local=$M2_REPO" > $LOGS/S4.log 2>&1
rc=$?
echo "gradle :qilin.pta:test --tests $CLS exit code: $rc (log: $LOGS/S4.log)"
grep -E 'error:|What went wrong' -A2 $LOGS/S4.log | head -n 12
[ $rc -eq 0 ] && pass "smoke test task" || fail "smoke test task exit $rc"

for t in solvesAnBnOnHandBuiltGraph solvesAnBnOnDotInput resolvedArtifactIsThePinnedVersion; do
    st=$(junit_case_status "$RES" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done

gradle :qilin.pta:dependencies --configuration testRuntimeClasspath "-Dmaven.repo.local=$M2_REPO" > $LOGS/S4-deps.log 2>&1
if grep -qE "org\.ucfs:solver:$UCFS_VERSION( |$)" $LOGS/S4-deps.log && ! grep -q 'FAILED' $LOGS/S4-deps.log; then
    pass "testRuntimeClasspath resolves org.ucfs:solver:$UCFS_VERSION"
else
    fail "testRuntimeClasspath does not resolve org.ucfs:solver:$UCFS_VERSION (see $LOGS/S4-deps.log)"
fi
grep -E 'org\.ucfs|kotlin-stdlib|antlr4' $LOGS/S4-deps.log | sort -u | head -n 8

# The version is declared in exactly one build file (not counting this acceptance test).
n=$(grep -rlF "$UCFS_VERSION" --include='*.gradle' --include='*.gradle.kts' --include='gradle.properties' . 2>/dev/null | grep -v '/build/' | wc -l)
[ "$n" -eq 1 ] && pass "UCFS version declared in one build file" || fail "UCFS version declared in $n build files (need exactly 1)"

# mavenLocal() must be restricted to group org.ucfs wherever it is used.
bad=""
for f in $(grep -rl 'mavenLocal' --include='*.gradle' --include='*.gradle.kts' . 2>/dev/null | grep -v '/build/'); do
    grep -qE "includeGroup[ (]*['\"]org\.ucfs['\"]" "$f" || bad="$bad $f"
done
if [ -z "$(grep -rl 'mavenLocal' --include='*.gradle' --include='*.gradle.kts' . 2>/dev/null | grep -v '/build/')" ]; then
    fail "no mavenLocal() repository declared"
elif [ -z "$bad" ]; then
    pass "mavenLocal() restricted to org.ucfs"
else
    fail "mavenLocal() without includeGroup 'org.ucfs' in:$bad"
fi

if [ "${FULL:-0}" = 1 ]; then
    [ -d qilin.microben/build/classes/java/main ] && [ -d artifact/benchmarks/JREs/jre1.6.0_45 ] \
        || die_env "FULL=1 needs: git submodule update --init qilin.microben && git submodule update --init --depth 1 artifact/benchmarks"
    gradle clean build "-Dmaven.repo.local=$M2_REPO" > $LOGS/S4-full.log 2>&1
    rc=$?
    read -r t s f e <<<"$(junit_summary "$RES")"
    echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e (gradle exit $rc)"
    # 88 tests / 11 skipped on f93367e (BOOT-build-Qilin-AI-exp) + 3 smoke tests.
    if [ $rc -eq 0 ] && [ "$t" -ge 91 ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ]; then
        pass "full Qilin build: >= 91 tests, <= 11 skipped, 0 failed"
    else
        fail "full Qilin build (need exit 0, >= 91 tests, <= 11 skipped, 0 failed)"
    fi
fi

finish S4_ucfs_smoke
