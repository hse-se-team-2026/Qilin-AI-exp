#!/usr/bin/env bash
# E1-S4 acceptance: Qilin-AI-exp resolves org.ucfs:solver:<pinned version> from a project-local
# Maven repository (default .ucfs/m2, filled by scripts/ucfs/bootstrap.sh; -PucfsRepo=<dir>
# overrides it) and calls UCFS from Java (qilin.test.ucfs.UcfsDependencySmokeTest).
#
# Precondition: UCFS is published into M2_REPO. Either run `bash scripts/ucfs/bootstrap.sh`
# (M2_REPO defaults to .ucfs/m2) or publish UCFS-AI-dev with acceptance/E1/S3_publish_local.sh
# and pass that directory as M2_REPO.
# FULL=1 additionally runs the whole Qilin build with all existing tests (needs submodules
# qilin.microben and artifact/benchmarks, see BOOT-build-Qilin-AI-exp).
# Usage: [M2_REPO=/path/to/m2] [FULL=1] bash acceptance/E1/S4_ucfs_smoke.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

M2_REPO="$(realpath -m "${M2_REPO:-$ROOT/.ucfs/m2}")"
POM="$M2_REPO/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.pom"
[ -f "$POM" ] || die_env "precondition: $POM not found; run 'bash scripts/ucfs/bootstrap.sh' or publish UCFS-AI-dev (acceptance/E1/S3_publish_local.sh) and set M2_REPO"
echo "using M2_REPO=$M2_REPO"

RES=qilin.pta/build/test-results/test
LOGS=acceptance/E1/out/logs; mkdir -p "$LOGS"   # not under build/: FULL=1 runs clean
CLS=qilin.test.ucfs.UcfsDependencySmokeTest

# --- build configuration (static) ---------------------------------------------------------
BUILD_FILES=$(git ls-files '*.gradle' '*.gradle.kts' 'settings.gradle*')

[ "$(ucfs_prop ucfsVersion)" = "$UCFS_VERSION" ] && pass "gradle.properties: ucfsVersion=$UCFS_VERSION" \
    || fail "gradle.properties has no ucfsVersion=$UCFS_VERSION"
ucfs_prop ucfsCommit | grep -qxE '[0-9a-f]{40}' && pass "gradle.properties: ucfsCommit=$(ucfs_prop ucfsCommit | cut -c1-12)" \
    || fail "gradle.properties has no ucfsCommit=<40-hex sha of UCFS-AI-dev>"
[ -n "$(ucfs_prop ucfsGitUrl)" ] && pass "gradle.properties: ucfsGitUrl=$(ucfs_prop ucfsGitUrl)" \
    || fail "gradle.properties has no ucfsGitUrl"

# The version is declared in exactly one build file (not counting this acceptance test).
n=$(grep -lF "$UCFS_VERSION" $BUILD_FILES gradle.properties 2>/dev/null | wc -l)
[ "$n" -eq 1 ] && pass "UCFS version declared in one build file" || fail "UCFS version declared in $n build files (need exactly 1)"

[ -f scripts/ucfs/bootstrap.sh ] && git ls-files --error-unmatch scripts/ucfs/bootstrap.sh >/dev/null 2>&1 \
    && pass "scripts/ucfs/bootstrap.sh is committed" || fail "scripts/ucfs/bootstrap.sh is missing or not committed"
git check-ignore -q .ucfs/m2/probe && git check-ignore -q .ucfs/src/probe && pass ".ucfs/ is git-ignored" \
    || fail ".ucfs/ (bootstrap output) is not git-ignored"

# No mavenLocal() at all: ~/.m2 is shared between agents and would silently shadow Maven Central.
ml=$(grep -l 'mavenLocal' $BUILD_FILES 2>/dev/null)
[ -z "$ml" ] && pass "no mavenLocal() in build files" || fail "mavenLocal() used in: $(echo $ml)"

# Every maven { } block that uses ucfsRepo is restricted to group org.ucfs, either inside the
# block (content { includeGroup 'org.ucfs' }) or by an enclosing exclusiveContent { } block.
# shellcheck disable=SC2086
python3 - $BUILD_FILES <<'PY' && pass "ucfsRepo repository restricted to org.ucfs" || fail "ucfsRepo repository missing or not restricted to org.ucfs"
import re, sys
def blocks(text, word):
    for m in re.finditer(r"\b" + word + r"\s*(\([^)]*\))?\s*\{", text):
        i, depth = m.end(), 1
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        yield m.start(), i
inc = re.compile(r"includeGroup\s*\(?\s*['\"]org\.ucfs['\"]")
found, bad = 0, []
for f in sys.argv[1:]:
    t = re.sub(r"//[^\n]*", "", open(f).read())
    excl = [(a, b) for a, b in blocks(t, "exclusiveContent") if inc.search(t[a:b])]
    for a, b in blocks(t, "maven"):
        if "ucfsRepo" not in t[a:b]:
            continue
        found += 1
        if not (inc.search(t[a:b]) or any(x <= a and b <= y for x, y in excl)):
            bad.append(f)
print("  ucfsRepo maven blocks:", found, "unrestricted in:", bad)
sys.exit(0 if found and not bad else 1)
PY

# --- smoke test and resolution ----------------------------------------------------------------
rm -rf "$RES"   # old XML must not count
gradle :qilin.pta:test --rerun --tests "$CLS" "-PucfsRepo=$M2_REPO" > $LOGS/S4.log 2>&1
rc=$?
echo "gradle :qilin.pta:test --tests $CLS exit code: $rc (log: $LOGS/S4.log)"
grep -E 'error:|What went wrong' -A2 $LOGS/S4.log | head -n 12
[ $rc -eq 0 ] && pass "smoke test task" || fail "smoke test task exit $rc"

for t in solvesAnBnOnHandBuiltGraph solvesAnBnOnDotInput resolvedArtifactIsThePinnedVersion; do
    st=$(junit_case_status "$RES" "$CLS" "$t")
    [ "$st" = PASSED ] && pass "$t: $st" || fail "$t: $st"
done

gradle :qilin.pta:dependencies --configuration testRuntimeClasspath "-PucfsRepo=$M2_REPO" > $LOGS/S4-deps.log 2>&1
if grep -qE "org\.ucfs:solver:$UCFS_VERSION( |$)" $LOGS/S4-deps.log && ! grep -q 'FAILED' $LOGS/S4-deps.log; then
    pass "testRuntimeClasspath resolves org.ucfs:solver:$UCFS_VERSION"
else
    fail "testRuntimeClasspath does not resolve org.ucfs:solver:$UCFS_VERSION (see $LOGS/S4-deps.log)"
fi
grep -E 'org\.ucfs|kotlin-stdlib|antlr4' $LOGS/S4-deps.log | sort -u | head -n 8

if [ "${FULL:-0}" = 1 ]; then
    [ -d qilin.microben/build/classes/java/main ] && [ -d artifact/benchmarks/JREs/jre1.6.0_45 ] \
        || die_env "FULL=1 needs: git submodule update --init qilin.microben && git submodule update --init --depth 1 artifact/benchmarks"
    gradle clean build "-PucfsRepo=$M2_REPO" > $LOGS/S4-full.log 2>&1
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
