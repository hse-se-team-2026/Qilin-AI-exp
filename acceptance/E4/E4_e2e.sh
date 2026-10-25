#!/usr/bin/env bash
# E4 epic check: on the current tree (main after all E4 stories)
#  1. integrity: every E4 acceptance file and the E4 acceptance tests have the sha256 fixed when the
#     acceptance branch ai/E4-acceptance-r2 was written (r3 adds the check of E4-S3b: S3b_weak_type.sh,
#     WeakTypeProbe.java, prog/e4prog/WeakCastProg.java), and acceptance/E3/E3_e2e.sh is the E3 one (it
#     carries the hashes of the E3 checks and tests and of acceptance/E2/E2_e2e.sh, which carries E1/E2).
#     The hash of THIS file is in docs/ai/tickets/E4.md, so the epic verifier checks it from outside;
#  2. every E4 story check (S1, S2, S3, S3b, S4 ... S7), each with its own log; S6 reuses the benchmark run of S5
#     (acceptance/E4/out/bench, made at the same HEAD) for its reproducibility check;
#  3. the E3 epic check acceptance/E3/E3_e2e.sh (which runs the E2 and E1 regressions) still passes.
# acceptance/E4/probe_jdk.sh is the measurement of S6 (its output is committed) and is not run here.
#
# The whole run takes more than 10 minutes (about 35 on the planner's machine). An agent whose tool
# call is limited to 10 minutes starts it detached and waits in several calls (E4.md, criterion 1):
#   mkdir -p acceptance/E4/out && setsid nohup bash -c 'echo $$ > acceptance/E4/out/e2e.pid; exec bash acceptance/E4/E4_e2e.sh' \
#       > acceptance/E4/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E4/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E4/out/e2e.log
# (repeat the second line until the log ends with "RESULT: ..."; $! of the first line is not the job:
# setsid forks, so the job writes its own pid)
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh;
#   GNU time at /usr/bin/time.
# Usage: bash acceptance/E4/E4_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

# --- 1. integrity --------------------------------------------------------------------------------
nbad=0; nok=0
while read -r h f; do
    [ -n "$f" ] || continue
    if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$h" ]; then
        nok=$((nok + 1))
    else
        fail "protected file changed or missing: $f"; nbad=$((nbad + 1))
    fi
done <<'SUMS'
c2f324a0dc977f1ffb1285317965fa235e1a28103f551017c6ced481d3554fb5  acceptance/E4/AndersenCheck.java
5376556e494825db57c7c132f6e16b7dab32978fb111572f7ee356e153f45748  acceptance/E4/doc_check.py
7341a26f7abd21a8e5d4477c903154ac9b1888f56aef67e2991676e7d22d097b  acceptance/E4/lib.sh
ed66a5f146a5287f797ca755becd25b803b406da6a9871b829a960f58b337e5c  acceptance/E4/probe_jdk.sh
32b59002c51e66dd4f3020e0271f506c0d4cf4b2b1e5d269cd36c9cdf1f6dfff  acceptance/E4/prog/e4prog/DispatchProg.java
646b4732ce758dca83785c9b2606316c54a6045aa7b55ebda9bf0194eea1ccf7  acceptance/E4/prog/e4prog/EmptyArrayProg.java
5f6c324f815487887046b8aee27c66d600671f8539c6148d41a4605f5182ea6c  acceptance/E4/prog/e4prog/WeakCastProg.java
4b6db73d2e4635275bb9a9a558390bac9ae9d100d8543e1178fb3e7c7a168677  acceptance/E4/S1_ucfs_pta.sh
6c5e78608f5cd0f7e5501ab263bf6a27dc6a626611819282464a96660b2e84d2  acceptance/E4/S2_cli_ucfs.sh
55e988a330d7114c9d744192c88e5d6e83ad84b9eb769ea923492fdb32373920  acceptance/E4/S3_compare.sh
a2b93c49844874b2c5a79bb1b8bdd2aea96d6702c693e59d99c7455b7182215f  acceptance/E4/S3b_weak_type.sh
92847fe7d33fad22c21fff3cfba496ac63c0fee0be4b314d9c32cab180c7e3dc  acceptance/E4/S4_dispatch.sh
aa49a8c95a34176a58b2d26627f82cc9abb43ae163c1563302eb74b4e3ed8771  acceptance/E4/S5_bench.sh
327b52d35355cbd6ad590c7f981e214ce3567810e8b069688fe9b6dc9d7b3297  acceptance/E4/S6_results.sh
5a4abcb3f7d78b9e9a312a05b8e827392ae7ac8ba4772d94ca58d51a912661e5  acceptance/E4/S7_doc.sh
283064866d76b0a1c684c11b96f0003650b0125ec6d10084299d12c130f84c01  acceptance/E4/SeedCheck.java
02b4b498bfcdda85d73c230aee4dedfe4e0ec7782b997998e968b999b1018c5c  acceptance/E4/tables.py
67d6729d1639069db2dde8d71309a9a9f1c434af3f6deb75e3d2fa6150d84be0  acceptance/E4/WeakTypeProbe.java
bede91cb9ff70f5fa54e35750ce0b0f7b2e2cc35345329c12b910e240c8ea42b  qilin.pta/test/qilin/test/ucfs/E4UcfsPtaTest.java
f2488eb9ea5b70b23e39af9cbee1df3d9ff7f5b64ea44f5a10269d537f2fd3e1  qilin.pta/test/qilin/test/ucfs/E4UcfsCompareTest.java
94ceba62a36f518313bea9cb5b533093a677dc69e1094c9ef498234abaf5842e  qilin.pta/test/qilin/test/ucfs/E4DispatchTest.java
4306e18f0b5d7d100e0c1e5f9bea4f18929c57746647a4865848690016a02902  acceptance/E3/E3_e2e.sh
SUMS
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"

# --- 2. story checks -----------------------------------------------------------------------------
for s in S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type S4_dispatch S5_bench S6_results S7_doc; do
    start=$(date +%s)
    bash "acceptance/E4/$s.sh" > "$LOGS/e2e-$s.log" 2>&1
    rc=$?
    echo "  $s: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-$s.log")"
    [ $rc -eq 0 ] && pass "$s" || { fail "$s (see $LOGS/e2e-$s.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-$s.log" | head -n 5; }
done

# --- 3. E3 (and E2, E1) regression ---------------------------------------------------------------
start=$(date +%s)
bash acceptance/E3/E3_e2e.sh > "$LOGS/e2e-E3_e2e.log" 2>&1
rc=$?
echo "  E3_e2e: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-E3_e2e.log")"
[ $rc -eq 0 ] && pass "E3 regression (acceptance/E3/E3_e2e.sh)" || { fail "E3 regression (see $LOGS/e2e-E3_e2e.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E3_e2e.log" | head -n 5; }

tree_clean
finish E4_e2e
