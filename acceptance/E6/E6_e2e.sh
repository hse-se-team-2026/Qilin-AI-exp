#!/usr/bin/env bash
# E6 epic criterion 1 (docs/ai/tickets/E6.md; revision r2 of planner-E6-fix): cfl-idr-with-gll receives the graph
# of Qilin and works. Heavy (xalan with -Xmx16g in S6a/S6b, benchmarks of the E4/E5 regression): the whole run holds
# the machine lock (heavy_lock of lib.sh: flock /home/usatovpavel/edu/.heavy-run.lock unless HEAVY_LOCK_HELD=1);
# the checks inside see HEAVY_LOCK_HELD=1 and do not wait for it again.
#  1. integrity: sha256 of every acceptance/E6 file (except this script), of the E6 tests and of
#     acceptance/E5/E5_e2e.sh, plus the SUMS block of E5_e2e.sh (E5 files, E4_e2e.sh) and of E4_e2e.sh;
#  2. E6-S1 at the pinned commit of cfl-idr-with-gll-AI-exp: `bash acceptance/E6/S1_ucfs_main.sh` in
#     .cflidr/src (UCFS_M2=.ucfs/m2), after `bash scripts/cflidr/bootstrap.sh`;
#  3. the Qilin story checks S2_dependency, S3_fields, S4_cs, S5_cli, S6a_probe_script, S6b_results, S7_doc;
#  4. regression (E6.md "Регрессия"): E5 S1_phases S2_bench S3_minheap, S5a_vmrun on the committed VM
#     results, S6_doc (the links of e5-benchmarks.md); E4 S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type
#     S4_dispatch S5_bench; acceptance/E3/E3_e2e.sh (with E2, E1). Not: E4 S6/S7, E4_e2e, E5 S4_setup,
#     S5_results, E5_repro, E5_e2e (they bind committed results or document links to the code of E4/E5,
#     or need the VM; E4.md "Следствие для E5", E5.md "Решение лида", E9 #43).
# Takes about 1.5-2 h (plus the wait for the lock) and needs the network (submodule of .cflidr/src, Gradle
# dependencies). An agent with a 10-minute call limit runs it detached:
#   mkdir -p acceptance/E6/out && setsid nohup bash -c 'echo $$ > acceptance/E6/out/e2e.pid; exec flock /home/usatovpavel/edu/.heavy-run.lock env HEAVY_LOCK_HELD=1 bash acceptance/E6/E6_e2e.sh' \
#       > acceptance/E6/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E6/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E6/out/e2e.log
# Usage: bash acceptance/E6/E6_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
heavy_lock "$@"
need_submodules
need_ucfs
java_env_clean
GRADLE_OPTS="${GRADLE_OPTS:-}"
export GRADLE_OPTS

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
ff06174cc67734dfa889f882e5c71dc69dd6f448e746896b077790ce0db5aa36  acceptance/E6/lib.sh
defd8af482e22376756388393fb8ca0e8cbecf9206ee092bde69a80130648269  acceptance/E6/S2_dependency.sh
2caef8f980d981342839c87a541d1919789c70a588d8d9ca66220ecbc6e24692  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E6CflIdrLibraryTest.kt
a196093dfb40ec88fc34eeb22caced60d0af9ce2f1a9bf29224a086a9115bfe3  acceptance/E6/S3_fields.sh
edda94c0b09e01af220df5df29e6b7fe2d4cf912b22614c1efc220747b6eace8  qilin.pta/test/qilin/test/ucfs/E6Reference.java
5653e26525f6b368d4d8a4412507ad1f5fc2af4ebf77d22c8ad90f708717fc0f  qilin.pta/test/qilin/test/ucfs/E6IdrFieldsTest.java
c75a38e97f2532d668a680e07ed36d9a812bea885661189e6b587609c13e3a54  acceptance/E6/S4_cs.sh
b922471879bca6309ea525775131c0b90b3917ff8cc7d16e62ac05acc0102bc5  qilin.pta/test/qilin/test/ucfs/E6IdrCsTest.java
c7a9c3db47566ee8c46c8ddd01a5306ab29f51b17ee8c7d8da3882caa431b0e0  acceptance/E6/S5_cli.sh
f9f21e8356dec45c7fd815ddff194510fc2fd08259237647b617dd11d5d01918  acceptance/E6/prog/e6prog/CsFacts.java
357c6c3df0a1409440f80e573bf16f09ce8e45d928cba2a848e81f7c532c4b5b  acceptance/E6/S6a_probe_script.sh
a189e2ea6813507e520b123b0e0b6b7f0571fe1db257cb067698a7f6a29f17d9  acceptance/E6/IdrDyckCheck.java
29e46a8c676796f5a4b15a23e9a0c2ff762e60ded86c7cf6fd67475c44af2ea7  acceptance/E6/e6raw.py
2c420b271955fd663963cddcb4aa804b1e7ea18fda5cd1f88067e0d097190f82  acceptance/E6/S6b_results.sh
01973259227812de95fd653c8d99dcb3debb9779d122c74dabc862636dcf3f61  acceptance/E6/e6tables.py
4f2cebad07c2a956fb75a8537aaa4d993075feb0d08baccce327022ed8a54709  acceptance/E6/S7_doc.sh
6b962d8275458bd813c359f6e47a3ae0f850b38bfc5404e2b1880c3829e289c6  acceptance/E6/doc_check.py
1da34f6fac5436339f4b924842363259e4379920f39763f2e69f6ff170234bd3  acceptance/E5/E5_e2e.sh
SUMS
for e in acceptance/E5/E5_e2e.sh acceptance/E4/E4_e2e.sh; do
    while read -r h f; do
        [ -n "$f" ] && check_sum "$h" "$f"
    done < <(sed -n "/^done <<'SUMS'$/,/^SUMS$/p" "$e" | grep -E '^[0-9a-f]{64} ')
done
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"
no_ignored_tests qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E6CflIdrLibraryTest.kt qilin.pta/test/qilin/test/ucfs/E6*.java

run_check() {
    local s="$1" start log
    shift
    start=$(date +%s)
    log="$LOGS/e2e-$(basename "$(dirname "$s")")-$(basename "$s" .sh).log"
    bash "$s" "$@" > "$log" 2>&1
    RC=$?
    echo "  $s: exit $RC, $(( $(date +%s) - start )) s, $(tail -n 1 "$log")"
    [ $RC -eq 0 ] && pass "$s" || { fail "$s"; grep -E '^(FAIL|ENV):' "$log" | head -n 5; }
    return 0
}

# --- 2. E6-S1 in cfl-idr-with-gll-AI-exp at the pin ------------------------------------------------
bash scripts/cflidr/bootstrap.sh > "$LOGS/e2e-bootstrap.log" 2>&1 || fail "scripts/cflidr/bootstrap.sh (log: $LOGS/e2e-bootstrap.log)"
start=$(date +%s)
(cd .cflidr/src && UCFS_M2="$ROOT/.ucfs/m2" bash acceptance/E6/S1_ucfs_main.sh) > "$LOGS/e2e-cflidr-S1.log" 2>&1
RC=$?
echo "  .cflidr/src acceptance/E6/S1_ucfs_main.sh: exit $RC, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-cflidr-S1.log")"
[ $RC -eq 0 ] && pass "cfl-idr E6-S1 at cflidrCommit" || { fail "cfl-idr E6-S1 at cflidrCommit"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-cflidr-S1.log" | head -n 5; }

# --- 3. E6 story checks in Qilin -----------------------------------------------------------------
for s in S2_dependency S3_fields S4_cs S5_cli S6a_probe_script S6b_results S7_doc; do
    run_check "acceptance/E6/$s.sh"
done

# --- 4. regression -------------------------------------------------------------------------------
for s in S1_phases S2_bench S3_minheap S6_doc; do
    run_check "acceptance/E5/$s.sh"
done
run_check acceptance/E5/S5a_vmrun.sh docs/ucfs-integration/e5-results
for s in S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type S4_dispatch S5_bench; do
    run_check "acceptance/E4/$s.sh"
done
run_check acceptance/E3/E3_e2e.sh

tree_clean
finish E6_e2e
