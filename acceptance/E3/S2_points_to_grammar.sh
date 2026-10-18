#!/usr/bin/env bash
# E3-S2 acceptance: the points-to grammar and explicit start vertices.
#  1. `gradle clean build` green; qilin.ucfs.acceptance.E3GrammarTest PASSED (6 cases):
#     PointsToGrammar(k) (flowsTo of Sridharan et al. 2005, Fig. 3, fields 0 until k) on UCFS =
#     an independent worklist CFL-reachability solver over the grammar normalized by hand, on hand
#     cases and on 300 random graphs with fixed seeds; the same UcfsSolver on four more grammars
#     (a^n b^n, Dyck-2 with epsilon, ambiguous S -> S S | a, regular new assign*) = the same
#     reference on 120 random graphs each; reachablePairs(edges, grammar, startVertices) = the
#     all-pairs answer restricted to the start vertices; 2000 fields build and answer;
#  2. no regression: E2UcfsSolverTest (7) still passes; qilin.ucfs >= 13 tests, 0 skipped/failed;
#     qilin.pta >= 101 tests, <= 11 skipped, 0 failed;
#  3. PointsToGrammar is compiled Kotlin of qilin.ucfs;
#  4. tracked files unchanged by the check.
# Usage: bash acceptance/E3/S2_points_to_grammar.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

expect_cases qilin.ucfs qilin.ucfs.acceptance.E3GrammarTest pointsToHandCases pointsToRandomGraphsWithBars \
    pointsToRandomGraphsAnyLabels otherGrammarsAgainstReference explicitStartVertices manyFields
expect_cases qilin.ucfs qilin.ucfs.acceptance.E2UcfsSolverTest chainAABB unbalancedChain cycleTerminates
junit_stdout "$(xml_dir_of qilin.ucfs)" qilin.ucfs.acceptance.E3GrammarTest "E3GrammarTest " | sed 's/^/  /'
check_totals 101 13

kotlin_class_in_ucfs_jar qilin/ucfs/grammar/PointsToGrammar.class

tree_clean
finish S2_points_to_grammar
