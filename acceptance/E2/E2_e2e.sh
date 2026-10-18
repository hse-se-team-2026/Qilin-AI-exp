#!/usr/bin/env bash
# E2 epic check: on the current tree (main after all E2 stories)
#  1. integrity: every E2 acceptance file, the acceptance tests, the E1 checks, the existing
#     qilin.pta tests, the Gradle wrapper, the committed reference jar and bootstrap.sh have the
#     sha256 fixed when the acceptance branch ai/E2-acceptance-r2 was written (list below), and
#     the ucfs* values of gradle.properties are unchanged. The hash of THIS file is in
#     docs/ai/tickets/E2.md, so the epic verifier checks it from outside the repository;
#  2. every E2 story check (S1a, S1b, S2..S5) and the E1 regression
#     (acceptance/E1/S4_ucfs_smoke.sh with FULL=1). Each step writes its own log.
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh
# Usage: bash acceptance/E2/E2_e2e.sh          (exit 0 = PASS)
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
070907700d4bcfbf6dda01a6e65cde1e762450fecd65b70320d9440ca623e3f7  acceptance/E1/E1_e2e.sh
a888b9df89402a815bdb15d30c5280b090be11655ab4cc2299ce748d44cd6ed4  acceptance/E1/.gitignore
54e7f03ec8f39f9f23f060554e6e09677499d21ee832006685d2091185843c6f  acceptance/E1/lib.sh
2aa23ba3e34a801e057bd8107ebd7375b92916b82203970cd1b3554ae9b8d45f  acceptance/E1/S4_fresh_clone.sh
9b4608a65929740f79dddc76df871bf91ff778bebc90bb2ee7e48b31bde3b410  acceptance/E1/S4_ucfs_smoke.sh
700d6dcdd9785667796efebff8233eda7de720e7e241c160b3f55c1a0b4f359a  acceptance/E2/core_map_check.py
744a1502c1d7ad664e0677975e40beb6cf6abfe3f49da5311af22b109a50af68  acceptance/E2/.gitignore
10109450945d13f53816a2773eb14527c274d7e49bb743d35f3f5a75ea6433dd  acceptance/E2/lib.sh
a2a2898843d1277a1bcbc2521627b9c055f0d4504e10e976f0f11a4b3f021d62  acceptance/E2/S1a_core_map.sh
e843babfe7ae9927e889fc2b355d793de95993c7df406526a6e044d2f969f738  acceptance/E2/S1b_core_map.sh
fa7f73f025f340d4618f2f6b9536c444030780ae11f335ac43489abc43158b74  acceptance/E2/S2_cli_equals.sh
b05c7f25a302aa26b664095c69f7272c5198a97caa93eadace84c4f81650005e  acceptance/E2/S3_ucfs_module.sh
19849045954ed2e439bcee50f7d3c5a5f5ec1198b97b9b012b9c9ce02224672e  acceptance/E2/S4_interop_fatjar.sh
a98daa94d0311432c99ae81ca78866ef0b92048e72b89337cd18cdfd50bbe2e1  acceptance/E2/S5_pag_seam.sh
8148f17ae6abb769e724dfb2a93d0aa355ba6c2c83a1fd0a48a54a28a0ff4323  artifact/Qilin-0.9.9-SNAPSHOT.jar
45de8dabeb3362cefb01a108a835e3e83a6a55ea5f68974703bb7a49833125ee  gradle/wrapper/gradle-wrapper.properties
e827210b6bc2e50eafc963c3e273395fa54bb6626e787746045a6c9ba3e3b5dc  qilin.pta/test/qilin/test/context/CFATests.java
37e4ea29481b17eee5af394e9b7b693ac2e955542f56a43cf30c7af79e9167b3  qilin.pta/test/qilin/test/context/CollectionsTests.java
912c619f74e7fa0990e354ad76494f295c2698dc0e1d4a2a83063bf21c67e8f2  qilin.pta/test/qilin/test/context/HybTests.java
f6a44de4c269c5479ad589545fbe6e1775c6180bc82d26c8d5d2cbd2f9a74090  qilin.pta/test/qilin/test/context/OBJTests.java
4c742f8c358c6509238d16295aae4255ffad5fdb654418b6adf8667b48472932  qilin.pta/test/qilin/test/context/TypeTests.java
158f99f5a66df83e582d10e14e53cbf45eca5678e201e75af45bb17f317b8293  qilin.pta/test/qilin/test/core/ArrayTests.java
8ba781bf428bc0e45d0da0e6d52aef7d20f33bd43275881b7d0a283fc5f91dda  qilin.pta/test/qilin/test/core/AssignTests.java
4d1b9ecc2b396883877f2db2d06206cee4e4fd258568b01023719e94c6a66afd  qilin.pta/test/qilin/test/core/CallTests.java
add2ca8db74f37f08f747c036d036171822850aa31c2cd2e93e8954f2ad0ba01  qilin.pta/test/qilin/test/core/ClinitTests.java
2e1ec45217a1696d4df20993b5c45cd484fcf27a9cda55ee4fe751a54c7e78d8  qilin.pta/test/qilin/test/core/ExceptionTests.java
6e7db9f05037adf2bd60c7608a767310d774b6616e4208aa0202565ecb82a5ae  qilin.pta/test/qilin/test/core/FieldTests.java
a71de7b245ff9bc1bfb1463a06ee547891b1ded1aac74cb265264a845d2dfe4f  qilin.pta/test/qilin/test/core/GlobalTests.java
d1d698f98683f61dc2bd6bc5d332be32f2d291b8cdc5a5747128807bc338c3dd  qilin.pta/test/qilin/test/core/NativeTests.java
6e0ff45a89bebb9a090fb04bb14f9ae5e3ec6ba8a25f1b0b7da2898a365ca15d  qilin.pta/test/qilin/test/core/ReflogTests.java
c1d3df82950e53a3303f8f436fbee29825bc10f20c39724369040d0aff4ddfe3  qilin.pta/test/qilin/test/FlowSensTests.java
969cfc5b8fa1f85b82b5d2a1da2b17ffafcb6029428f9016146a5c5bf5963c2a  qilin.pta/test/qilin/test/ucfs/E2KotlinInteropTest.java
b473be40f762bc1d052e14d841308dd74253916f9f7cdadc56fbae021c91122b  qilin.pta/test/qilin/test/ucfs/E2PagSeamTest.java
4e2c98e1c0c2ac94cfe2b90aefd49faade8f487935a19dfdbbad8c0d217f5f47  qilin.pta/test/qilin/test/ucfs/UcfsDependencySmokeTest.java
dd7e4f80a4b881fc65dab5f9dc587b9cdb18d9fdad67b6a06cdb6651692786a2  qilin.pta/test/qilin/test/util/AliasAssertion.java
ca6ac14400ca7d3fa7f25f7dd6998fbd6cd01b406cf3e17edf10a3f6386c74c4  qilin.pta/test/qilin/test/util/AssertionsParser.java
72398b8f93b08b89d8eda680925036a7ba750fdc92f807d9fe9c386121a74954  qilin.pta/test/qilin/test/util/IAssertion.java
281cb48a9af88b2a641ddf11ddfa90c4997c0d9858b514bccb6dbbe393212a48  qilin.pta/test/qilin/test/util/JunitTests.java
118ec849b1602528499fdc962f06da60c523b64c224d394313e4c1b7566fade9  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E2UcfsSolverTest.kt
e1b1652f0252b74da2bec59004e3c5e0ebd21bb4a5d6b166617d856e4f012176  scripts/ucfs/bootstrap.sh
SUMS
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"
[ "$(grep '^ucfs' gradle.properties | sha256sum | cut -d' ' -f1)" = bbe410460cd5c8ed8fbfec26f9873cd06b3894d7ca28e045f5a8224cef14f7d8 ] \
    && pass "ucfs* values in gradle.properties unchanged" || fail "ucfs* values in gradle.properties changed"

# --- 2. story checks and the E1 regression -------------------------------------------------------
for s in S1a_core_map S1b_core_map S2_cli_equals S3_ucfs_module S4_interop_fatjar S5_pag_seam; do
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
