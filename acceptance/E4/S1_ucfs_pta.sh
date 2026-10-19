#!/usr/bin/env bash
# E4-S1 acceptance: the analysis qilin.pta.tools.UcfsPTA (import of the UCFS answer as the points-to
# sets of a Qilin analysis; docs/ai/tickets/E4-S1.md).
#  1. `gradle clean build` green; qilin.test.ucfs.E4UcfsPtaTest PASSED (2 cases): on the 43 small
#     programs of E3 and both receiver bindings, the views UCFS / UCFS_TYPED / SPARK equal Andersen
#     references computed by the test (REF / REF2 without ROOT, the same with Qilin's declared-type
#     filter at each variable, REF_T), through reachingObjects(Node), (Local) and (SootField); the
#     dropped ROOT pairs are counted; Qilin's SimplifiedEvaluator reads the view (may-fail casts and
#     average points-to = a recomputation over the view, call-graph lines independent of the view);
#  2. prints the E4UcfsPtaTest lines (per program and total);
#  3. bytecode: UcfsPTA.pureRun() itself invokes Spark's pureRun (super), PagExport.export(PTA,
#     ReceiverBinding) and UcfsPointsTo.solve(UcfsGraph, Grammar);
#  4. no regression: qilin.pta >= 109 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 14;
#  5. tracked files unchanged by the check.
# Usage: bash acceptance/E4/S1_ucfs_pta.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

expect_cases qilin.pta qilin.test.ucfs.E4UcfsPtaTest viewsAgainstReferencesBothBindings qilinEvaluatorReadsTheView
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E4UcfsPtaTest "E4UcfsPtaTest " | sed 's/^/  /'
check_totals 109 14

jar="$(ls qilin.pta/build/libs/qilin.pta-*.jar 2>/dev/null | head -n 1)"
if [ -z "$jar" ]; then
    fail "no qilin.pta jar after the build"
else
    for callee in 'qilin/pta/tools/Spark\.pureRun:\(\)V' \
                  'qilin/ucfs/PagExport\.export:\(Lqilin/core/PTA;Lqilin/ucfs/ReceiverBinding;\)' \
                  'qilin/ucfs/UcfsPointsTo\.solve:\(Lqilin/ucfs/UcfsGraph;Lorg/ucfs/grammar/combinator/Grammar;\)'; do
        out="$(bytecode_check "$jar" qilin.pta.tools.UcfsPTA pureRun "()V" invokes "$callee")" \
            && pass "$out" || fail "$out"
    done
fi

tree_clean
finish S1_ucfs_pta
