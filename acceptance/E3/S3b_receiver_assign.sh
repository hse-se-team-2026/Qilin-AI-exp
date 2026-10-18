#!/usr/bin/env bash
# E3-S3b acceptance: the second export mode PagExport.export(pta, ReceiverBinding.CALL_GRAPH),
# without the "new" edges receiver object -> this made by Spark's solver from points-to sets
# (E3.md B1, D2). Receiver variable -> this "assign" edges along Spark's call graph instead.
#  1. `gradle clean build` green; qilin.test.ucfs.E3ReceiverAssignTest PASSED (3 cases). For each
#     of the 43 programs of E3UcfsPointsToTest: the export equals the graph built by the test
#     (PAG maps without the receiver new edges, plus receiver variable -> this from Soot's call
#     graph and the Jimple invoke base); no new edge into a this node except ROOT's
#     (derivedNewIntoThis = 0); UCFS called directly = Andersen without filters on the same input
#     (REF2) = UcfsPointsTo.solve(graph, PointsToGrammar); Spark subset of UCFS; the answer of the
#     main mode subset of this one, growth printed (class R3); Receiver2This hand facts
#     (A.foo's notAlias becomes may-alias, R3); every mayAlias assertion holds;
#  2. prints per program "E3ReceiverAssignTest <program>: ... receiverAssign=.. derivedNewIntoThis=..
#     derivedNewException=.. ucfsPairs1=.. ucfsPairs2=.. growthR3=.. missing=.." and a total line;
#  3. no regression: qilin.pta >= 107 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 14;
#  4. ReceiverBinding is compiled Kotlin of qilin.ucfs;
#  5. tracked files unchanged by the check.
# Usage: bash acceptance/E3/S3b_receiver_assign.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

expect_cases qilin.pta qilin.test.ucfs.E3ReceiverAssignTest callGraphBindingAllPrograms \
    receiver2ThisCallGraphBinding mayAliasAssertionsHoldCallGraphBinding
expect_cases qilin.pta qilin.test.ucfs.E3UcfsPointsToTest allProgramsAgainstReferences
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E3ReceiverAssignTest "E3ReceiverAssignTest " | sed 's/^/  /'
check_totals 107 14

kotlin_class_in_ucfs_jar qilin/ucfs/ReceiverBinding.class

tree_clean
finish S3b_receiver_assign
