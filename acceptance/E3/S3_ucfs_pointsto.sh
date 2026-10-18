#!/usr/bin/env bash
# E3-S3 acceptance: UCFS computes points-to sets of the 43 small programs of qilin.microben core.
#  1. `gradle clean build` green; qilin.test.ucfs.E3UcfsPointsToTest PASSED (3 cases). For every
#     program (Spark insens, then UcfsPointsTo.solve = PagExport + PointsToGrammar + UCFS):
#     UCFS called by the test itself (UcfsSolver.reachablePairs, E2 API) = field-sensitive Andersen
#     without type filter computed by the test from the PAG maps (REF), and solve(pta) returns the
#     same map; the same fixpoint with Qilin's filters (REF_T) = Spark; every extra pair of UCFS
#     over Spark gets one class (R4b, R1, R2, R5) by switching the filters on one by one; a second
#     grammar (new assign*, defined in the test) = BFS over new/assign; the new edges made by the
#     solver from points-to sets are counted (derivedNew, derivedNewIntoThis, ...) and UCFS without
#     them = REF without them; every mayAlias assertion holds; hand facts of Receiver2This and
#     ArrayElemTypeFiltering (no type filter, E3.md R1);
#  2. prints per program "E3UcfsPointsToTest <program>: ... ucfsPairs=.. sparkPairs=.. missing=..
#     extra=.. extraR4b=.. extraR1=.. extraR2=.. extraR5=.. derivedNew=.. derivedNewIntoThis=..
#     pairsWithoutDerivedNew=..", one line "E3UcfsPointsToTest extra <program> class=<R..> removedAloneBy=[..] <var> <- <obj>"
#     per extra pair and the total line (the numbers of E3.md "Расхождения" and of the S5 document);
#  3. no regression: qilin.pta >= 104 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 14;
#  4. UcfsPointsTo is compiled Kotlin of qilin.ucfs; in its bytecode solve(PTA) returns the value
#     of solve(UcfsGraph, Grammar), and solve(UcfsGraph, Grammar) calls UcfsSolver.reachablePairs
#     (critic-E3 M1: an own fixpoint in solve(pta) fails here);
#  5. tracked files unchanged by the check.
# Usage: bash acceptance/E3/S3_ucfs_pointsto.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

expect_cases qilin.pta qilin.test.ucfs.E3UcfsPointsToTest allProgramsAgainstReferences \
    handFactsReceiver2ThisAndArrayElemTypeFiltering mayAliasAssertionsHold
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E3UcfsPointsToTest "E3UcfsPointsToTest " | sed 's/^/  /'
check_totals 104 14

kotlin_class_in_ucfs_jar qilin/ucfs/UcfsPointsTo.class
jar="$(ucfs_jar)"
out=$(bytecode_check "$jar" qilin.ucfs.UcfsPointsTo solve "(Lqilin/core/PTA;)" returns \
    'Method (qilin/ucfs/UcfsPointsTo\.)?solve:\(Lqilin/ucfs/UcfsGraph;Lorg/ucfs/grammar/combinator/Grammar;\)')
rc=$?; echo "  $out"
[ $rc -eq 0 ] && pass "UcfsPointsTo.solve(PTA) returns solve(UcfsGraph, Grammar)" \
    || fail "UcfsPointsTo.solve(PTA) must return the value of solve(UcfsGraph, Grammar)"
out=$(bytecode_check "$jar" qilin.ucfs.UcfsPointsTo solve "(Lqilin/ucfs/UcfsGraph;Lorg/ucfs/grammar/combinator/Grammar;)" invokes \
    'Method qilin/ucfs/UcfsSolver\.reachablePairs:')
rc=$?; echo "  $out"
[ $rc -eq 0 ] && pass "UcfsPointsTo.solve(UcfsGraph, Grammar) calls UcfsSolver.reachablePairs" \
    || fail "UcfsPointsTo.solve(UcfsGraph, Grammar) must call UcfsSolver.reachablePairs"

tree_clean
finish S3_ucfs_pointsto
