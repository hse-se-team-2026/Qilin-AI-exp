#!/usr/bin/env bash
# E4 epic check: on the current tree (main after all E4 stories)
#  1. integrity: every E4 acceptance file and the E4 acceptance tests have the sha256 fixed when the
#     acceptance branch ai/E4-acceptance was written, and acceptance/E3/E3_e2e.sh is the E3 one (it
#     carries the hashes of the E3 checks and tests and of acceptance/E2/E2_e2e.sh, which carries E1/E2).
#     The hash of THIS file is in docs/ai/tickets/E4.md, so the epic verifier checks it from outside;
#  2. every E4 story check (S1 ... S6), each with its own log; S6 reuses the benchmark run of S5
#     (acceptance/E4/out/bench) for its reproducibility check;
#  3. the E3 epic check acceptance/E3/E3_e2e.sh (which runs the E2 and E1 regressions) still passes.
# acceptance/E4/probe_jdk.sh is a non-blocking measurement and is not run here.
#
# The whole run takes more than 10 minutes (about 30 on the planner's machine). An agent whose tool
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
ea905931f3810f1a022f0d2ec14240a92a0069939e0893a9e6a832b81efd0a25  acceptance/E4/doc_check.py
7341a26f7abd21a8e5d4477c903154ac9b1888f56aef67e2991676e7d22d097b  acceptance/E4/lib.sh
ed66a5f146a5287f797ca755becd25b803b406da6a9871b829a960f58b337e5c  acceptance/E4/probe_jdk.sh
7704942b3d37aa4e521f1fb85a6d0555795da575de41403c5f60fadef1b34c7a  acceptance/E4/prog/e4prog/DispatchProg.java
4b6db73d2e4635275bb9a9a558390bac9ae9d100d8543e1178fb3e7c7a168677  acceptance/E4/S1_ucfs_pta.sh
6c5e78608f5cd0f7e5501ab263bf6a27dc6a626611819282464a96660b2e84d2  acceptance/E4/S2_cli_ucfs.sh
c4e60571d2802f97cd8591bb0612dbf4d94d863ef31735b8e1c2dadfae3b71b7  acceptance/E4/S3_compare.sh
61a04245400ba982331388134b982e461b765ee0124c83764076b7b39657ae73  acceptance/E4/S4_dispatch.sh
f88dfb29265626db6c989d98fb37f73e58bd629ca9108df6bfbfee9e7d12e873  acceptance/E4/S5_bench.sh
fc4b609dde435ad175d5e14ec5a8fe726119e9d1b82d99a050d433b6f01d0654  acceptance/E4/S6_doc.sh
848c22021e3a7f390c02b017b61f669cb0f56fea4b5f14e9e95753970faa3544  acceptance/E4/tables.py
bede91cb9ff70f5fa54e35750ce0b0f7b2e2cc35345329c12b910e240c8ea42b  qilin.pta/test/qilin/test/ucfs/E4UcfsPtaTest.java
8421e207724ed516129d1b20399e11fc730b97ff1eb1366a2edfaebc11ffe6bd  qilin.pta/test/qilin/test/ucfs/E4UcfsCompareTest.java
94ceba62a36f518313bea9cb5b533093a677dc69e1094c9ef498234abaf5842e  qilin.pta/test/qilin/test/ucfs/E4DispatchTest.java
4306e18f0b5d7d100e0c1e5f9bea4f18929c57746647a4865848690016a02902  acceptance/E3/E3_e2e.sh
SUMS
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"

# --- 2. story checks -----------------------------------------------------------------------------
for s in S1_ucfs_pta S2_cli_ucfs S3_compare S4_dispatch S5_bench S6_doc; do
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
