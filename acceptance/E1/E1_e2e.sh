#!/usr/bin/env bash
# E1 epic check: from an empty local Maven repository, UCFS-AI-dev builds with all tests and
# publishes org.ucfs:solver, then Qilin-AI-exp resolves it and passes the UCFS smoke test and
# all of its existing tests; finally a fresh clone of Qilin-AI-exp becomes buildable with the
# README commands alone (scripts/ucfs/bootstrap.sh builds UCFS at the pinned ucfsCommit).
# Usage: [UCFS_SRC=<git url|path>] bash acceptance/E1/E1_e2e.sh <path to UCFS-AI-dev checkout>
#        (exit 0 = PASS). Without UCFS_SRC the fresh-clone step fetches UCFS from ucfsGitUrl (GitHub).
# Needs Qilin submodules (FULL check), see S4_ucfs_smoke.sh.
source "$(dirname "$0")/lib.sh"

UCFS_DIR="${1:?usage: E1_e2e.sh <UCFS-AI-dev checkout>}"
UCFS_DIR="$(cd "$UCFS_DIR" && pwd)" || die_env "no such dir: $1"
[ -f "$UCFS_DIR/acceptance/E1/S3_publish_local.sh" ] || die_env "$UCFS_DIR has no acceptance/E1 scripts"

M2="$ROOT/acceptance/E1/out/e1-e2e-m2"   # not under build/: S4 FULL=1 runs clean
safe_reset_dir "$M2"
echo "UCFS-AI-dev: $(git -C "$UCFS_DIR" rev-parse HEAD)  Qilin-AI-exp: $(git rev-parse HEAD)  M2=$M2"

step() { # name command...
    echo "=== $1"
    shift
    "$@" 2>&1 | grep -E '^(PASS|FAIL|ENV|RESULT|  )'
    local rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] && pass "$STEP" || fail "$STEP (exit $rc)"
}

STEP="UCFS S1 (DOT round-trip)";      step "$STEP" bash "$UCFS_DIR/acceptance/E1/S1_dot_roundtrip.sh"
STEP="UCFS S2 (merged, full build)";  step "$STEP" bash "$UCFS_DIR/acceptance/E1/S2_vkutuev_merge.sh"
STEP="UCFS S3 (publish to empty M2)"; step "$STEP" env M2_OUT="$M2" bash "$UCFS_DIR/acceptance/E1/S3_publish_local.sh"
STEP="Qilin S4 (resolve + smoke + all tests)"; step "$STEP" env M2_REPO="$M2" FULL=1 bash "$ROOT/acceptance/E1/S4_ucfs_smoke.sh"

# The commit Qilin pins must be part of the UCFS history under test and contain E1 publishing.
PIN=$(ucfs_prop ucfsCommit)
echo "=== pinned UCFS commit (gradle.properties ucfsCommit=${PIN:-<none>})"
if [ -n "$PIN" ] && git -C "$UCFS_DIR" merge-base --is-ancestor "$PIN" HEAD 2>/dev/null; then
    pass "ucfsCommit is an ancestor of the UCFS-AI-dev checkout HEAD"
else
    fail "ucfsCommit '${PIN:-<none>}' is not in the history of $UCFS_DIR HEAD"
fi
git -C "$UCFS_DIR" cat-file -e "${PIN:-none}:acceptance/E1/S3_publish_local.sh" 2>/dev/null \
    && pass "ucfsCommit contains the E1 publishing checks" || fail "ucfsCommit predates E1-S3 (no acceptance/E1/S3_publish_local.sh)"

STEP="Qilin fresh clone + README bootstrap"; step "$STEP" bash "$ROOT/acceptance/E1/S4_fresh_clone.sh"

finish E1_e2e
