#!/usr/bin/env bash
# E6 epic criterion 1 (docs/ai/tickets/E6.md): cfl-idr-with-gll receives the graph of Qilin and works.
#  1. integrity: sha256 of every acceptance/E6 file (except this script), of the E6 tests and of
#     acceptance/E5/E5_e2e.sh, plus the SUMS block of E5_e2e.sh (E5 files, E4_e2e.sh) and of E4_e2e.sh;
#  2. E6-S1 at the pinned commit of cfl-idr-with-gll-AI-exp: `bash acceptance/E6/S1_ucfs_main.sh` in
#     .cflidr/src (UCFS_M2=.ucfs/m2), after `bash scripts/cflidr/bootstrap.sh`;
#  3. the Qilin story checks S2_dependency, S3_fields, S4_cs, S5_cli, S6_probe, S7_doc;
#  4. regression (E6.md "Регрессия"): E5 S1_phases S2_bench S3_minheap, S5a_vmrun on the committed VM
#     results, S6_doc (the links of e5-benchmarks.md); E4 S1_ucfs_pta S2_cli_ucfs S3_compare S3b_weak_type
#     S4_dispatch S5_bench; acceptance/E3/E3_e2e.sh (with E2, E1). Not: E4 S6/S7, E4_e2e, E5 S4_setup,
#     S5_results, E5_repro, E5_e2e (they bind committed results or document links to the code of E4/E5,
#     or need the VM; E4.md "Следствие для E5", E5.md "Решение лида", E9 #43).
# Takes about 1.5 h and needs the network (submodule of .cflidr/src, Gradle dependencies). An agent with a
# 10-minute call limit runs it detached:
#   mkdir -p acceptance/E6/out && setsid nohup bash -c 'echo $$ > acceptance/E6/out/e2e.pid; exec bash acceptance/E6/E6_e2e.sh' \
#       > acceptance/E6/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E6/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E6/out/e2e.log
# Usage: bash acceptance/E6/E6_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
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
834e182326cd3d615aa8911611dfbacaf35539cd9065222ad687560f873369c7  acceptance/E6/lib.sh
9d8bfa0da55a4949dad46e3ab423c67afd9578587e68b13b9122d07fd9226131  acceptance/E6/S2_dependency.sh
2caef8f980d981342839c87a541d1919789c70a588d8d9ca66220ecbc6e24692  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E6CflIdrLibraryTest.kt
3a5c75a04306ba600a6b20d079afa3f6b5e4d385bf49947a0e10e862237ed0d8  acceptance/E6/S3_fields.sh
d5f42e412b19a072203a6e264341f4eea6c3d804c572d486787ffae33cffce96  qilin.pta/test/qilin/test/ucfs/E6Reference.java
46b10d022c895223853f52c77bad12b4f5b13eae526df5ddd02c95bef9a30a67  qilin.pta/test/qilin/test/ucfs/E6IdrFieldsTest.java
5fb450dc2588f1039fb2c8e7e2969a7432f13471098016e64e26983e61913eaf  acceptance/E6/S4_cs.sh
0ad76167b3f23eb1de3dd5182f6a00360cc9deb2fbfa7589a93510504f550e39  qilin.pta/test/qilin/test/ucfs/E6IdrCsTest.java
1b97659b38de77b1fe445437ee0be9534659f8488b233a6614a48265effd97e8  acceptance/E6/S5_cli.sh
f9f21e8356dec45c7fd815ddff194510fc2fd08259237647b617dd11d5d01918  acceptance/E6/prog/e6prog/CsFacts.java
4628303a587f2a7dba205a1241f4feb2754da574252a33d7842f0262dd28785a  acceptance/E6/S6_probe.sh
a189e2ea6813507e520b123b0e0b6b7f0571fe1db257cb067698a7f6a29f17d9  acceptance/E6/IdrDyckCheck.java
0c7811eea25018ac37628ef102dfd1f4c3ecdd57c576aa5d52f759737157ee69  acceptance/E6/e6tables.py
4f2cebad07c2a956fb75a8537aaa4d993075feb0d08baccce327022ed8a54709  acceptance/E6/S7_doc.sh
a263b68c313563989bf4cdd4d469235bf42516a83a8e13849083f5deab1c3439  acceptance/E6/doc_check.py
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
for s in S2_dependency S3_fields S4_cs S5_cli S6_probe S7_doc; do
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
