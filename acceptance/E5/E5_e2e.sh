#!/usr/bin/env bash
# E5 epic check: on the current tree (main after all E5 stories)
#  1. integrity: every E5 acceptance file and the E5 acceptance test have the sha256 fixed when the acceptance
#     branch ai/E5-acceptance-r2 was written (block SUMS below), acceptance/E4/E4_e2e.sh is the E4 one, and every
#     file that its own SUMS block lists (the E4 checks and tests, acceptance/E3/E3_e2e.sh) still has its hash.
#     The hash of THIS file is in docs/ai/tickets/E5.md, so the epic verifier checks it from outside;
#  2. every E5 story check, each with its own log: S1 S2 S3 S4, S5a (S5a_vmrun.sh on the committed results
#     themselves: they are the copy of the VM run, results-manifest-sha256; not run for the local fallback of the
#     lead, which has fallback.txt and no vm-run.tsv), S5b (S5_results.sh), S6;
#  3. criterion 3 of E5.md: acceptance/E5/E5_repro.sh (fop, lusearch here); exit 3 (the ratio UCFS/Spark here
#     is outside x2 of the committed one) is printed as NOTE and is not a FAIL of this script: the epic
#     verifier analyses it in the ticket; exit 1 (answer differs) is a FAIL;
#  4. the E4 regression of E5 (E4.md "Следствие для E5"): S1, S2, S3, S3b, S4, S5 of acceptance/E4 - not S6/S7
#     and not E4_e2e.sh, which bind the committed E4 results to the E4 code;
#  5. the E3 epic check acceptance/E3/E3_e2e.sh (it runs the E2 and E1 regressions).
# The final measurement itself (scripts/ucfs/e5-full.sh on the VM, E5-S5a) is not repeated here; S5b checks its
# committed results and repeats pmd/luindex for the answer, E5_repro.sh repeats fop/lusearch.
#
# The run takes about 1.5 hours (S3 searches heaps, S4 clones the benchmarks submodule and builds in an
# isolated Gradle home) and needs the network. Start it detached and wait in several calls:
#   mkdir -p acceptance/E5/out && setsid nohup bash -c 'echo $$ > acceptance/E5/out/e2e.pid; exec bash acceptance/E5/E5_e2e.sh' \
#       > acceptance/E5/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E5/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E5/out/e2e.log
# (repeat the second line until the log ends with "RESULT: ...").
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh;
#   GNU time at /usr/bin/time; JAVA_HOME = JDK 21; JAVA_TOOL_OPTIONS, _JAVA_OPTIONS, JDK_JAVA_OPTIONS unset.
# Usage: bash acceptance/E5/E5_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean

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
c17f7c81d388e3168ead5a53015ad308d375a3302d22e45f4f53ddee94961514  acceptance/E5/lib.sh
5c36f1cf506bf88593db4e959f31a1d867e74a35658b1bfcf230ec415182a1b2  acceptance/E5/e5lib.py
1940f9241e49c4c9b7a976cc44ccb328ed6da92a228881b5b8e0383690b9dcf3  acceptance/E5/S1_phases.sh
152357861a9c099480177370e7b490e1628dae063418236121c9cd503dd4f766  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E5PhaseTimesTest.kt
bd2ea1296a0ae2ad14cdd37039130d1ac21ea3f7ef67360b2d46935686f9ed37  acceptance/E5/S2_bench.sh
6b370c1679cde1d042d3078c49d39ce170e54d86f7b694da87411c6e335bb567  acceptance/E5/S3_minheap.sh
58519b9d250f83096f732cbcc9e01c45ed1fb64151d15c943734965d43f6ba3d  acceptance/E5/S4_setup.sh
0034f7601bea5a4e96421f248b293e163e9e20b06b8f44f3e5751e2edf132904  acceptance/E5/S5a_vmrun.sh
511f9034f86631296484c56714e79f62857ddd6ab8b6604c464a1e2ff7c9f2d3  acceptance/E5/e5vm.py
36b732d29804bf71bbebe4f467aecb3333a6d15886c5f9d19eea01444e0e667b  acceptance/E5/S5_results.sh
33da99e9d99719a3c1c7fba9462d6130f5d1e86a782f2d32b930de86f4120acf  acceptance/E5/e5tables.py
2a242c8452bac8fd78dddc9a1348dc46d402219da43a659b1f9641b295ed796f  acceptance/E5/S6_doc.sh
61bdf95913ca0d0f7cd58160cff672aa7638cb5784f66896969eaea0bc77b94a  acceptance/E5/doc_check.py
c50d1abc6cf159a5ccab1cddea628f3d41681a96e28905750a2a3c8eab12fac2  acceptance/E5/E5_repro.sh
67cf7bb33a60af5f231826b3e8da75e3af81163a4c8efbed95d68451a54ea584  acceptance/E4/E4_e2e.sh
SUMS
# the SUMS block of acceptance/E4/E4_e2e.sh (whose own hash is in the block above)
while read -r h f; do
    [ -n "$f" ] && check_sum "$h" "$f"
done < <(sed -n "/^done <<'SUMS'$/,/^SUMS$/p" acceptance/E4/E4_e2e.sh | grep -E '^[0-9a-f]{64} ')
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"
no_ignored_tests qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E5PhaseTimesTest.kt

# --- 2. E5 story checks --------------------------------------------------------------------------
# run_check <script> [args...] -> its exit code in RC
run_check() {
    local s="$1" start log
    shift
    start=$(date +%s)
    log="$LOGS/e2e-$(basename "$(dirname "$s")")-$(basename "$s" .sh).log"
    bash "$s" "$@" > "$log" 2>&1
    RC=$?
    echo "  $s: exit $RC, $(( $(date +%s) - start )) s, $(tail -n 1 "$log")"
    [ $RC -eq 0 ] && pass "$s"
    return 0
}
for s in S1_phases S2_bench S3_minheap S4_setup; do
    run_check "acceptance/E5/$s.sh"
    [ $RC -eq 0 ] || { fail "acceptance/E5/$s.sh"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E5-$s.log" | head -n 5; }
done
if [ -f docs/ucfs-integration/e5-results/vm-run.tsv ] || [ ! -f docs/ucfs-integration/e5-results/fallback.txt ]; then
    run_check acceptance/E5/S5a_vmrun.sh docs/ucfs-integration/e5-results
    [ $RC -eq 0 ] || { fail "acceptance/E5/S5a_vmrun.sh"; grep -E '^(FAIL|ENV|PROBLEM):' "$LOGS/e2e-E5-S5a_vmrun.log" | head -n 5; }
else
    echo "NOTE: local fallback (fallback.txt, no vm-run.tsv): S5a_vmrun.sh does not apply; S5_results.sh checks the lead-decision line"
fi
for s in S5_results S6_doc; do
    run_check "acceptance/E5/$s.sh"
    [ $RC -eq 0 ] || { fail "acceptance/E5/$s.sh"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E5-$s.log" | head -n 5; }
done

# --- 3. criterion 3: reproduction of the answer and of the ratio UCFS/Spark here ---------------------
run_check acceptance/E5/E5_repro.sh
grep -E '^RATIO:' "$LOGS/e2e-E5-E5_repro.log"
if [ $RC -eq 3 ]; then
    echo "NOTE: E5_repro.sh: the ratio UCFS/Spark here is outside x2 of the committed one - the epic verifier analyses it (E5.md, criterion 3)"
elif [ $RC -ne 0 ]; then
    fail "acceptance/E5/E5_repro.sh"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E5-E5_repro.log" | head -n 5
fi

# --- 4. E4 regression (without S6/S7) -------------------------------------------------------------
for s in S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type S4_dispatch S5_bench; do
    run_check "acceptance/E4/$s.sh"
    [ $RC -eq 0 ] || { fail "acceptance/E4/$s.sh"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E4-$s.log" | head -n 5; }
done

# --- 5. E3 (and E2, E1) regression ---------------------------------------------------------------
run_check acceptance/E3/E3_e2e.sh
[ $RC -eq 0 ] || { fail "acceptance/E3/E3_e2e.sh"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E3-E3_e2e.log" | head -n 5; }

tree_clean
finish E5_e2e
