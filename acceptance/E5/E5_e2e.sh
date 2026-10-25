#!/usr/bin/env bash
# E5 epic check: on the current tree (main after all E5 stories)
#  1. integrity: every E5 acceptance file and the E5 acceptance test have the sha256 fixed when the acceptance
#     branch ai/E5-acceptance was written (block SUMS below), acceptance/E4/E4_e2e.sh is the E4 one, and every
#     file that its own SUMS block lists (the E4 checks and tests, acceptance/E3/E3_e2e.sh) still has its hash.
#     The hash of THIS file is in docs/ai/tickets/E5.md, so the epic verifier checks it from outside;
#  2. every E5 story check (S1 ... S6), each with its own log;
#  3. the E4 regression of E5 (E4.md "Следствие для E5"): S1, S2, S3, S3b, S4, S5 of acceptance/E4 - not S6/S7
#     and not E4_e2e.sh, which bind the committed E4 results to the E4 code;
#  4. the E3 epic check acceptance/E3/E3_e2e.sh (it runs the E2 and E1 regressions).
# The final measurement itself (scripts/ucfs/e5-full.sh on the VM, E5-S5) is not repeated here; S5 checks its
# committed results and repeats pmd/luindex for the answer.
#
# The run takes about an hour (S4 clones the benchmarks submodule and builds in an isolated Gradle home) and
# needs the network. Start it detached and wait in several calls:
#   mkdir -p acceptance/E5/out && setsid nohup bash -c 'echo $$ > acceptance/E5/out/e2e.pid; exec bash acceptance/E5/E5_e2e.sh' \
#       > acceptance/E5/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E5/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E5/out/e2e.log
# (repeat the second line until the log ends with "RESULT: ...").
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh;
#   GNU time at /usr/bin/time; JAVA_HOME = JDK 21.
# Usage: bash acceptance/E5/E5_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

# --- 1. integrity --------------------------------------------------------------------------------
nbad=0; nok=0
check_sum() {
    if [ -f "$2" ] && [ "$(sha256sum "$2" | cut -d' ' -f1)" = "$1" ]; then
        nok=$((nok + 1))
    else
        fail "protected file changed or missing: $2"; nbad=$((nbad + 1))
    fi
}
while read -r h f; do
    [ -n "$f" ] && check_sum "$h" "$f"
done <<'SUMS'
cb53b5e44605fcb1ecad0be6a4e5225623f7882a7e7625e4587726b5bbf74141  acceptance/E5/lib.sh
3a2040abb45e22926476524f03d09f2b7591b2c4428d92c33258f9faae307a57  acceptance/E5/e5lib.py
33e9806f02bf8dec90b243e4861e4e2f26d30efafc4d1094ac84acab942cfe71  acceptance/E5/S1_phases.sh
36987f9ec84b0407edb4bf2c737bd9cdca2713a9bff9d8a8b56f1e2045f286b1  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E5PhaseTimesTest.kt
e41973f542548d7447f9be944597c5af766d85908dd48a788f9fe65a985bdda2  acceptance/E5/S2_bench.sh
ac7127c79c8582aa0a71955990e0abe277f491fecf57a2bffd249d0f24474cf7  acceptance/E5/S3_minheap.sh
9020dfe232122fd3a2b211bc7d9673d7a01fde182469279eb358d32c79535bda  acceptance/E5/S4_setup.sh
33f7290d9d07feba8fa609d96c8fe5280d93c87f57246057daf26a8550a9b8db  acceptance/E5/S5_results.sh
a2e03d2a3d6f732b00dea782e9b11496d3b7fbd09fb5570932fa264e69b4d11f  acceptance/E5/e5tables.py
2a242c8452bac8fd78dddc9a1348dc46d402219da43a659b1f9641b295ed796f  acceptance/E5/S6_doc.sh
d8ad0e2f71f88c55f4d2b04f29bb165a63e4c018a8eb9363bb47d9fab9d8522e  acceptance/E5/doc_check.py
67cf7bb33a60af5f231826b3e8da75e3af81163a4c8efbed95d68451a54ea584  acceptance/E4/E4_e2e.sh
SUMS
# the SUMS block of acceptance/E4/E4_e2e.sh (whose own hash is in the block above)
while read -r h f; do
    [ -n "$f" ] && check_sum "$h" "$f"
done < <(sed -n "/^done <<'SUMS'$/,/^SUMS$/p" acceptance/E4/E4_e2e.sh | grep -E '^[0-9a-f]{64} ')
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"
no_ignored_tests qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E5PhaseTimesTest.kt

# --- 2. E5 story checks --------------------------------------------------------------------------
run_check() {
    local s="$1" start rc
    start=$(date +%s)
    bash "$s" > "$LOGS/e2e-$(basename "$(dirname "$s")")-$(basename "$s" .sh).log" 2>&1
    rc=$?
    local log="$LOGS/e2e-$(basename "$(dirname "$s")")-$(basename "$s" .sh).log"
    echo "  $s: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$log")"
    [ $rc -eq 0 ] && pass "$s" || { fail "$s (see $log)"; grep -E '^(FAIL|ENV):' "$log" | head -n 5; }
}
for s in S1_phases S2_bench S3_minheap S4_setup S5_results S6_doc; do
    run_check "acceptance/E5/$s.sh"
done

# --- 3. E4 regression (without S6/S7) -------------------------------------------------------------
for s in S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type S4_dispatch S5_bench; do
    run_check "acceptance/E4/$s.sh"
done

# --- 4. E3 (and E2, E1) regression ---------------------------------------------------------------
run_check acceptance/E3/E3_e2e.sh

tree_clean
finish E5_e2e
