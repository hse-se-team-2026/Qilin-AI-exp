#!/usr/bin/env bash
# E3 epic check: on the current tree (main after all E3 stories)
#  1. integrity: every E3 acceptance file and the E3 acceptance tests have the sha256 fixed when the
#     acceptance branch ai/E3-acceptance-r2 was written, and acceptance/E2/E2_e2e.sh is the E2 one
#     (it carries the hashes of the E1/E2 checks, the old tests, the wrapper, the reference jar and
#     bootstrap.sh). The hash of THIS file is in docs/ai/tickets/E3.md, so the epic verifier checks it
#     from outside the repository;
#  2. every E3 story check (S1, S2, S3, S3b, S4, S5), each with its own log;
#  3. the E2 epic check acceptance/E2/E2_e2e.sh (which also runs the E1 regression) still passes.
# acceptance/E3/probe_scale.sh is a non-blocking measurement and is not run here.
#
# The whole run takes more than 10 minutes (about 20 on the planner's machine). An agent whose tool
# call is limited to 10 minutes starts it detached and waits in several calls (procedure: E3.md,
# criterion 1):
#   mkdir -p acceptance/E3/out && setsid nohup bash -c 'echo $$ > acceptance/E3/out/e2e.pid; exec bash acceptance/E3/E3_e2e.sh' \
#       > acceptance/E3/out/e2e.log 2>&1 < /dev/null &
#   timeout 590 tail --pid="$(cat acceptance/E3/out/e2e.pid)" -f /dev/null; tail -n 3 acceptance/E3/out/e2e.log
# (repeat the second line until the log ends with "RESULT: ..."; $! of the first line is not the job:
# setsid forks, so the job writes its own pid)
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh
# Usage: bash acceptance/E3/E3_e2e.sh          (exit 0 = PASS)
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
a888b9df89402a815bdb15d30c5280b090be11655ab4cc2299ce748d44cd6ed4  acceptance/E3/.gitignore
b0e35040770da890da1381a9a01ecfa2457e297ac41f3ebb563239ef60da3152  acceptance/E3/lib.sh
df62721fb3b0195b1da70ae6c3f3f544518e053f77d0708c5f6fd9aad29de095  acceptance/E3/S1_pag_export.sh
e85558bba9a4b36e9d02f1ad86f8966172ba2e2f1440694ba3e96c4cda2c7aff  acceptance/E3/S2_points_to_grammar.sh
88b19ea35335e28475042134305fe5679cb5de7af97a688e96b226f8c2a2616a  acceptance/E3/S3_ucfs_pointsto.sh
f76943fa1761ec01500d629382685686a425ebecfda508bad92e33795b3d1893  acceptance/E3/S3b_receiver_assign.sh
b98cac2041de57aa7c6f19deb5471adcf1f4ad51f19d76e02a119d73c26e6aa9  acceptance/E3/S4_cli_ucfspt.sh
05158cac1cfbe3c46ac7afa49145f467892616e0a647d89acaee7e213473b3f6  acceptance/E3/DotCheck.java
595dbdceb52d0846a93f6b47443420ebbba35c39da23efd331738d46f060d86d  acceptance/E3/probe_scale.sh
3f4e5ce67d4fe5eb94d6202df12d367b504d229d0d1442d12ac352561814e552  acceptance/E3/S5_ucfs_doc.sh
3137d177d1f8c4ccaaeab1441a3e5ff963d1b9a4dcc0b7a97887b7401491c3ce  acceptance/E3/doc_check.py
75a8d10134ce30fff7f5bf424aad93a89a16db35e44c414d4cb8898a9b46c6d8  acceptance/E3/bib_keys.txt
8e71fe561c57fcfbdc184f9dc2a663ae1c01d4b9d1af8856845387982ed0e551  qilin.pta/test/qilin/test/ucfs/E3PagExportTest.java
d73a1f7505037a588329917c63348ff2c77a8b8a908ccba0c070d698b004a3e7  qilin.pta/test/qilin/test/ucfs/E3UcfsPointsToTest.java
7e07afd4400f4149a116c191598006f88b1b0726aa112e6259d8c71d9a3b0687  qilin.pta/test/qilin/test/ucfs/E3ReceiverAssignTest.java
96e2ca14866e0001b23b970ed3520a4fc8cb71733a12b15d5e884c6117d9326e  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E3GrammarTest.kt
0693c7ea41fa255954bf9828eccd2e45ddb323965801be61a203d0e81c1e167c  acceptance/E2/E2_e2e.sh
SUMS
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"

# --- 2. story checks -----------------------------------------------------------------------------
for s in S1_pag_export S2_points_to_grammar S3_ucfs_pointsto S3b_receiver_assign S4_cli_ucfspt S5_ucfs_doc; do
    start=$(date +%s)
    bash "acceptance/E3/$s.sh" > "$LOGS/e2e-$s.log" 2>&1
    rc=$?
    echo "  $s: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-$s.log")"
    [ $rc -eq 0 ] && pass "$s" || { fail "$s (see $LOGS/e2e-$s.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-$s.log" | head -n 5; }
done

# --- 3. E2 (and E1) regression -------------------------------------------------------------------
start=$(date +%s)
bash acceptance/E2/E2_e2e.sh > "$LOGS/e2e-E2_e2e.log" 2>&1
rc=$?
echo "  E2_e2e: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-E2_e2e.log")"
[ $rc -eq 0 ] && pass "E2 regression (acceptance/E2/E2_e2e.sh)" || { fail "E2 regression (see $LOGS/e2e-E2_e2e.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E2_e2e.log" | head -n 5; }

tree_clean
finish E3_e2e
