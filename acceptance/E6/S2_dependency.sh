#!/usr/bin/env bash
# E6-S2 acceptance: cfl-idr-with-gll as a library of qilin.ucfs, with the UCFS of Qilin
# (docs/ai/tickets/E6-S2.md; plan E6.md D2, D3; revision r2 of planner-E6-fix: 3b).
#  1. scripts/cflidr/cflidr.properties: cflidrVersion=0.1.0-ai-SNAPSHOT, cflidrCommit = 40 hex digits,
#     cflidrGitUrl = https://github.com/hse-se-team-2026/cfl-idr-with-gll-AI-exp.git;
#  2. from scratch (.cflidr removed), `bash scripts/cflidr/bootstrap.sh` exits 0 and publishes
#     .cflidr/m2/org/cfl_idr_with_gll/cfl-idr-with-gll/<v>/cfl-idr-with-gll-<v>.jar whose manifest says
#     CflIdr-Commit = cflidrCommit, CflIdr-Dirty = false, UCFS-Commit = ucfsCommit of gradle.properties;
#     a second run changes nothing (same jar bytes) and prints "nothing to do";
#  3. the pinned commit is on main of cfl-idr-with-gll-AI-exp (ancestor of origin/main in .cflidr/src),
#     and its acceptance/E6/S1_ucfs_main.sh is the E6-S1 check (sha256 = CFLIDR_S1_SHA of lib.sh);
#  3b. (r2, Codex review of the plan) with a local edit of a tracked file in .cflidr/src and no published
#     jar, bootstrap.sh exits non-zero, says "local changes" and keeps the edit; with
#     CFLIDR_SRC=<path of a local copy of the repository> it clones from that path (origin of .cflidr/src =
#     the path) and publishes the pinned commit (manifest as in 2); afterwards origin is set back to
#     cflidrGitUrl;
#  4. `gradle clean build` green; E6CflIdrLibraryTest: the figures of the cfl-idr repository give the
#     pairs its author's tests assert, one org.ucfs.parser.Gll and one cfl-idr on the class path, from
#     .ucfs/m2 and .cflidr/m2, manifest = the pin; no regression: qilin.pta >= MIN_PTA tests, <= 11
#     skipped, 0 failed; qilin.ucfs >= MIN_UCFS tests, 0 failed/skipped;
#  5. the fat jar (build -x test, fatJar -x test) contains org/cfl_idr_with_gll/ApproximationKt.class
#     byte-equal to the published jar's, and org/ucfs/parser/Gll.class byte-equal to .ucfs/m2's solver
#     (one UCFS, the one of ucfsCommit); `gradle :qilin.pta:dependencies --configuration runtimeClasspath`
#     resolves org.ucfs:solver to exactly 0.1.0-ai-SNAPSHOT and has no ch.qos.logback;
#  6. .cflidr/ is git-ignored, the check leaves the tracked files unchanged;
#  7. regression of the build configuration: acceptance/E1/S4_ucfs_smoke.sh passes (among others, the
#     UCFS version string 0.1.0-ai-SNAPSHOT occurs in exactly one build file - gradle.properties - so the
#     cfl-idr version is read from scripts/cflidr/cflidr.properties, not written into a *.gradle file).
# Usage: bash acceptance/E6/S2_dependency.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
MIN_PTA=113
MIN_UCFS=20

# --- 1. pin ---------------------------------------------------------------------------------------
V="$(cflidr_prop cflidrVersion)"
C="$(cflidr_prop cflidrCommit)"
U="$(cflidr_prop cflidrGitUrl)"
[ "$V" = 0.1.0-ai-SNAPSHOT ] && pass "cflidrVersion = $V" || fail "cflidrVersion '$V' (scripts/cflidr/cflidr.properties)"
echo "$C" | grep -qxE '[0-9a-f]{40}' && pass "cflidrCommit = $C" || fail "cflidrCommit '$C' is not 40 hex digits"
[ "$U" = https://github.com/hse-se-team-2026/cfl-idr-with-gll-AI-exp.git ] && pass "cflidrGitUrl = $U" || fail "cflidrGitUrl '$U'"
[ -f scripts/cflidr/bootstrap.sh ] || fail "no scripts/cflidr/bootstrap.sh"
[ "$FAILS" -eq 0 ] || finish S2_dependency

# --- 2. bootstrap from scratch, then again ---------------------------------------------------------
UC="$(sed -n 's/^ucfsCommit=//p' gradle.properties | tail -n 1 | tr -d '\r')"
rm -rf .cflidr
bash scripts/cflidr/bootstrap.sh > "$LOGS/bootstrap1.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "bootstrap from scratch" || fail "bootstrap exit $rc (log: $LOGS/bootstrap1.log)"
J="$(cflidr_jar)"
if [ -f "$J" ]; then
    [ "$(manifest_attr "$J" CflIdr-Commit)" = "$C" ] && pass "CflIdr-Commit = cflidrCommit" || fail "CflIdr-Commit '$(manifest_attr "$J" CflIdr-Commit)'"
    [ "$(manifest_attr "$J" CflIdr-Dirty)" = false ] && pass "CflIdr-Dirty = false" || fail "CflIdr-Dirty '$(manifest_attr "$J" CflIdr-Dirty)'"
    [ "$(manifest_attr "$J" UCFS-Commit)" = "$UC" ] && pass "UCFS-Commit = ucfsCommit $UC" || fail "UCFS-Commit '$(manifest_attr "$J" UCFS-Commit)'"
    h1="$(sha256sum "$J" | cut -d' ' -f1)"
    bash scripts/cflidr/bootstrap.sh > "$LOGS/bootstrap2.log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && grep -q 'nothing to do' "$LOGS/bootstrap2.log" && [ "$(sha256sum "$J" | cut -d' ' -f1)" = "$h1" ] \
        && pass "second bootstrap: nothing to do, same jar" || fail "second bootstrap rebuilt or failed (exit $rc, log: $LOGS/bootstrap2.log)"
else
    fail "no $J"
fi

# --- 3. the pinned commit is on cfl-idr-with-gll-AI-exp main and carries the E6-S1 check ---------------
if [ -d .cflidr/src/.git ]; then
    git -C .cflidr/src fetch -q origin main > "$LOGS/fetch.log" 2>&1 || die_env "fetch origin main of .cflidr/src (network?)"
    git -C .cflidr/src merge-base --is-ancestor "$C" FETCH_HEAD && pass "cflidrCommit is on origin/main of cfl-idr-with-gll-AI-exp" \
        || fail "cflidrCommit $C is not an ancestor of origin/main"
    got="$(git -C .cflidr/src show "$C:acceptance/E6/S1_ucfs_main.sh" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    [ "$got" = "$CFLIDR_S1_SHA" ] && pass "pinned commit has the E6-S1 check acceptance/E6/S1_ucfs_main.sh" \
        || fail "acceptance/E6/S1_ucfs_main.sh at the pin: sha256 $got, expected $CFLIDR_S1_SHA"
else
    fail "no .cflidr/src checkout"
fi

# --- 3b. local edits are kept, CFLIDR_SRC is honoured -----------------------------------------------
if [ -d .cflidr/src/.git ] && [ -f "$J" ]; then
    COPY="$OUT/cflidr-src-copy"
    rm -rf "$COPY" && cp -a .cflidr/src "$COPY" && git -C "$COPY" branch -f e6-s2-pin "$C" > /dev/null
    MARK="# local edit by acceptance/E6/S2_dependency.sh"
    echo "$MARK" >> .cflidr/src/README.md
    rm -rf .cflidr/m2/org/cfl_idr_with_gll
    bash scripts/cflidr/bootstrap.sh > "$LOGS/bootstrap-edit.log" 2>&1
    rc=$?
    [ $rc -ne 0 ] && grep -q 'local changes' "$LOGS/bootstrap-edit.log" && [ "$(tail -n 1 .cflidr/src/README.md)" = "$MARK" ] \
        && pass "bootstrap with a local edit in .cflidr/src: exit $rc, 'local changes', edit kept" \
        || fail "bootstrap with a local edit in .cflidr/src: exit $rc, edit $( [ "$(tail -n 1 .cflidr/src/README.md)" = "$MARK" ] && echo kept || echo lost) (log: $LOGS/bootstrap-edit.log)"
    rm -rf .cflidr
    CFLIDR_SRC="$COPY" bash scripts/cflidr/bootstrap.sh > "$LOGS/bootstrap-src.log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ "$(git -C .cflidr/src remote get-url origin)" = "$COPY" ] \
        && [ "$(manifest_attr "$J" CflIdr-Commit)" = "$C" ] && [ "$(manifest_attr "$J" CflIdr-Dirty)" = false ] \
        && [ "$(manifest_attr "$J" UCFS-Commit)" = "$UC" ] \
        && pass "CFLIDR_SRC=<local copy>: cloned from it, pinned commit published" \
        || fail "CFLIDR_SRC=<local copy>: exit $rc, origin '$(git -C .cflidr/src remote get-url origin 2>/dev/null)' (log: $LOGS/bootstrap-src.log)"
    git -C .cflidr/src remote set-url origin "$U" 2> /dev/null
    rm -rf "$COPY"
else
    fail "3b skipped: no .cflidr/src or no published jar"
fi

# --- 4. build and the library test ----------------------------------------------------------------
clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
expect_cases qilin.ucfs qilin.ucfs.acceptance.E6CflIdrLibraryTest \
    figure10UnderAndOverApproximations figure5OverApproximationAndOnDemand oneUcfsAndThePinnedCflIdr
check_totals "$MIN_PTA" "$MIN_UCFS"
no_ignored_tests qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E6CflIdrLibraryTest.kt

# --- 5. fat jar and resolved dependencies -----------------------------------------------------------
FRESH="$OUT/qilin-fat.jar"
if fresh_fatjar "$FRESH"; then
    S="$ROOT/.ucfs/m2/org/ucfs/solver/$(ucfs_version)/solver-$(ucfs_version).jar"
    cmp -s <(unzip -p "$FRESH" org/cfl_idr_with_gll/ApproximationKt.class) <(unzip -p "$J" org/cfl_idr_with_gll/ApproximationKt.class) \
        && [ -n "$(unzip -Z1 "$FRESH" org/cfl_idr_with_gll/ApproximationKt.class 2>/dev/null)" ] \
        && pass "fat jar: cfl-idr ApproximationKt = the published one" || fail "fat jar: cfl-idr ApproximationKt missing or different"
    cmp -s <(unzip -p "$FRESH" org/ucfs/parser/Gll.class) <(unzip -p "$S" org/ucfs/parser/Gll.class) \
        && pass "fat jar: org.ucfs.parser.Gll = the solver of ucfsCommit" || fail "fat jar: org.ucfs.parser.Gll differs from .ucfs/m2"
else
    fail "fat jar build"
fi
gradle :qilin.pta:dependencies --configuration runtimeClasspath > "$LOGS/deps.log" 2>&1
vs="$(resolved_versions "$LOGS/deps.log" org.ucfs:solver)"
[ "$vs" = 0.1.0-ai-SNAPSHOT ] && pass "runtimeClasspath: org.ucfs:solver resolves to $vs only" || fail "org.ucfs:solver versions: '$vs'"
grep -q 'ch.qos.logback' "$LOGS/deps.log" && fail "logback on the runtime class path of qilin.pta" || pass "no logback on the runtime class path"
grep -q 'org.cfl_idr_with_gll:cfl-idr-with-gll:0.1.0-ai-SNAPSHOT' "$LOGS/deps.log" \
    && pass "runtimeClasspath has org.cfl_idr_with_gll:cfl-idr-with-gll" || fail "cfl-idr-with-gll not on the runtime class path"

# --- 6. hygiene -----------------------------------------------------------------------------------
git check-ignore -q .cflidr && pass ".cflidr/ is git-ignored" || fail ".cflidr/ is not git-ignored"
# --- 7. E1-S4 (build configuration of the UCFS dependency) ---------------------------------------------
bash acceptance/E1/S4_ucfs_smoke.sh > "$LOGS/S2-E1-S4.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "acceptance/E1/S4_ucfs_smoke.sh" \
    || { fail "acceptance/E1/S4_ucfs_smoke.sh exit $rc (log: $LOGS/S2-E1-S4.log)"; grep -E '^FAIL' "$LOGS/S2-E1-S4.log" | head -n 3; }
tree_clean
finish S2_dependency
