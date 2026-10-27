#!/usr/bin/env bash
# E6-S3 acceptance: the FIELDS export (qilin.ucfs.idr.IdrExport.export(pta, IdrCalls.ERASED)) and the
# in-process run of cfl-idr-with-gll (qilin.ucfs.idr.IdrSolve) (docs/ai/tickets/E6-S3.md; E6.md D4, D5, D7).
#  1. `gradle clean build` green; qilin.test.ucfs.E6IdrFieldsTest PASSED:
#     fieldsExportEqualsAndersen - on the 61 programs of E6Reference, cfl-idr's under- and
#       over-approximation (grammar parity) restricted to (object, variable) pairs both equal the
#       Andersen fixpoint of the test over the same CI PAG (E6Reference.fieldsReference), which
#       contains E3's REF2;
#     solveIsCflIdrOnTheExportedGraph - IdrSolve returns exactly what cfl-idr's getUnderApprox /
#       getMROverApprox give on the edge list rebuilt by the test;
#     fieldsGraphShape - labels and layer transitions of the FIELDS encoding (E6.md D4, D5);
#     sparkWithinFieldsExport (r2, critic MAJOR-2) - on the 61 programs every pair of Spark's CI points-to
#       sets (insens, the same run) is in cfl-idr's over-approximation on the FIELDS export (anchor: same
#       call graph, receivers bound along it, exceptions without the catch type, no type filter);
#  2. no regression: qilin.pta >= 117 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 20, 0 failed/skipped;
#     no @Ignore/@Disabled in the E6 tests.
# Usage: bash acceptance/E6/S3_fields.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
need_cflidr

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
expect_cases qilin.pta qilin.test.ucfs.E6IdrFieldsTest \
    fieldsExportEqualsAndersen solveIsCflIdrOnTheExportedGraph fieldsGraphShape sparkWithinFieldsExport
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E6IdrFieldsTest "E6IdrFieldsTest total" | sed 's/^/  /'
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E6IdrFieldsTest "E6IdrFieldsTest spark" | sed 's/^/  /'
check_totals 117 20
no_ignored_tests qilin.pta/test/qilin/test/ucfs/E6IdrFieldsTest.java qilin.pta/test/qilin/test/ucfs/E6Reference.java
tree_clean
finish S3_fields
