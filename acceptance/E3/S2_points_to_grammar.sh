#!/usr/bin/env bash
# E3-S2 acceptance: the points-to grammar and explicit start vertices.
#  1. `gradle clean build` green; qilin.ucfs.acceptance.E3GrammarTest PASSED (7 cases):
#     PointsToGrammar(k) (flowsTo of Sridharan et al. 2005, Fig. 3, fields 0 until k) on UCFS =
#     an independent worklist CFL-reachability solver over the grammar normalized by hand, on hand
#     cases and on 300 random graphs with fixed seeds; the same UcfsSolver on nine more grammars
#     (a^n b^n, Dyck-2 with epsilon, ambiguous S -> S S | a, regular new assign*, hidden left
#     recursion, a cycle of unit rules, S -> S S | a | eps, nested stars, right recursion) = the
#     same reference on 120 random graphs each, >= 30 of them with a pair (u, v), u != v;
#     reachablePairs(edges, grammar, startVertices) = the all-pairs answer restricted to the start
#     vertices; 2000 fields build, answer and keep different fields apart; the points-to grammar
#     of the UCFS team (cfpq-paths-app Main.kt, generalized to k fields) gives the reversed pairs;
#  2. no regression: E2UcfsSolverTest still passes; qilin.ucfs >= 14 tests, 0 skipped/failed;
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
    pointsToRandomGraphsAnyLabels otherGrammarsAgainstReference explicitStartVertices manyFields \
    ucfsTeamGrammarGivesReversedPairs
expect_cases qilin.ucfs qilin.ucfs.acceptance.E2UcfsSolverTest chainAABB unbalancedChain cycleTerminates
junit_stdout "$(xml_dir_of qilin.ucfs)" qilin.ucfs.acceptance.E3GrammarTest "E3GrammarTest " | sed 's/^/  /'
check_totals 101 14

kotlin_class_in_ucfs_jar qilin/ucfs/grammar/PointsToGrammar.class

tree_clean
finish S2_points_to_grammar
