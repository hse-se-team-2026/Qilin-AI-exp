#!/usr/bin/env bash
# E3-S3 acceptance: UCFS computes points-to sets of the 43 small programs of qilin.microben core.
#  1. `gradle clean build` green; qilin.test.ucfs.E3UcfsPointsToTest PASSED (3 cases). For every
#     program (Spark insens, then UcfsPointsTo.solve = PagExport + PointsToGrammar + UCFS):
#     UCFS = field-sensitive Andersen without type filter computed by the test from the PAG maps
#     (REF); the same fixpoint with Qilin's filters (REF_T) = Spark; Spark subset of UCFS; a second
#     grammar (new assign*, defined in the test) through the same export and solver = BFS over
#     new/assign; every mayAlias assertion of the sources holds under UCFS; hand facts of
#     Receiver2This (receiver binding) and ArrayElemTypeFiltering (no type filter, E3.md R1);
#  2. prints the per-program line "E3UcfsPointsToTest <program>: ... ucfsPairs=.. sparkPairs=..
#     missing=.. extra=.." (the numbers of E3.md "Расхождения" are reproduced by this script);
#  3. no regression: qilin.pta >= 104 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 13;
#  4. UcfsPointsTo is compiled Kotlin of qilin.ucfs and runs UCFS (UcfsSolver.reachablePairs);
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
check_totals 104 13

kotlin_class_in_ucfs_jar qilin/ucfs/UcfsPointsTo.class
src=$(grep -rlE '^\s*object UcfsPointsTo\b' qilin.ucfs/src/main 2>/dev/null | head -n 1)
if [ -n "$src" ] && grep -qE 'UcfsSolver\.reachablePairs|Gll\.gll' "$src"; then
    pass "UcfsPointsTo ($src) runs UCFS"
else
    fail "UcfsPointsTo must run UCFS (UcfsSolver.reachablePairs or Gll.gll), source: '${src:-not found}'"
fi

tree_clean
finish S3_ucfs_pointsto
