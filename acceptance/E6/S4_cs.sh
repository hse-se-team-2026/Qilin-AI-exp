#!/usr/bin/env bash
# E6-S4 acceptance: the context-sensitive export (IdrCalls.CS: call-site parentheses, partial balance,
# context erasure at the context-insensitive variables) and the fully balanced diagnostic export
# (IdrCalls.BALANCED) (docs/ai/tickets/E6-S4.md; E6.md D6-D8).
#  1. `gradle clean build` green; qilin.test.ucfs.E6IdrCsTest PASSED:
#     csSoundBoundedAndPrecise - on the 61 programs: every pair of the bounded CS language
#       (E6Reference.CsModel, stacks <= 3) is in cfl-idr's over-approximation; under <= over <= FIELDS
#       reference; every mayAlias assertion holds in the over-approximation; every notAlias assertion of
#       the 18 qilin.microben.context programs holds in it, while the CI reference violates some; the
#       BALANCED export loses mayAlias facts (its semantics is fully balanced);
#     csGraphShape - the call edge of every call graph edge is op--c / cp--c at the site index of its
#       statement, the gadgets (START, END, the erasure of context-insensitive variables) as in E6.md D6;
#  2. the FIELDS test still passes; no regression: qilin.pta >= 118 tests, <= 11 skipped, 0 failed;
#     no @Ignore/@Disabled in the E6 tests.
# Usage: bash acceptance/E6/S4_cs.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
need_cflidr

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
expect_cases qilin.pta qilin.test.ucfs.E6IdrCsTest csSoundBoundedAndPrecise csGraphShape
expect_cases qilin.pta qilin.test.ucfs.E6IdrFieldsTest fieldsExportEqualsAndersen solveIsCflIdrOnTheExportedGraph fieldsGraphShape
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E6IdrCsTest "E6IdrCsTest total" | sed 's/^/  /'
check_totals 118 20
no_ignored_tests qilin.pta/test/qilin/test/ucfs/E6IdrCsTest.java
tree_clean
finish S4_cs
