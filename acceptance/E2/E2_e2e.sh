#!/usr/bin/env bash
# E2 epic check: runs every E2 story check on the current tree (main after all E2 stories) and
# the E1 regression (acceptance/E1/S4_ucfs_smoke.sh with FULL=1). Each step writes its own log.
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh
# Usage: bash acceptance/E2/E2_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

for s in S1_core_map S2_cli_equals S3_ucfs_module S4_interop_fatjar S5_pag_seam; do
    start=$(date +%s)
    bash "acceptance/E2/$s.sh" > "$LOGS/e2e-$s.log" 2>&1
    rc=$?
    echo "  $s: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-$s.log")"
    [ $rc -eq 0 ] && pass "$s" || { fail "$s (see $LOGS/e2e-$s.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-$s.log" | head -n 5; }
done

start=$(date +%s)
FULL=1 bash acceptance/E1/S4_ucfs_smoke.sh > "$LOGS/e2e-E1-S4-full.log" 2>&1
rc=$?
echo "  E1 S4_ucfs_smoke FULL=1: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-E1-S4-full.log")"
[ $rc -eq 0 ] && pass "E1 regression (S4_ucfs_smoke FULL=1)" || fail "E1 regression (see $LOGS/e2e-E1-S4-full.log)"

[ -z "$(git status --porcelain --untracked-files=no)" ] && pass "working tree clean" \
    || fail "tracked files changed: $(git status --porcelain --untracked-files=no | head -3)"

finish E2_e2e
