#!/usr/bin/env bash
# E3-S1 acceptance: export of the global PAG of a finished analysis to the labeled graph handed to
# UCFS (Kotlin qilin.ucfs.PagExport.export(PTA): UcfsGraph; labels qilin.ucfs.PtLabels).
#  1. `gradle clean build` green; qilin.test.ucfs.E3PagExportTest (5 programs of qilin.microben,
#     Spark insens) PASSED: graph = PAG rebuilt from the inverse maps (CI projection, ContextField
#     edges dropped, FieldRefNode collapsed to store_i/load_i, every edge also reversed "_bar"),
#     dense ids, and facts derived by hand from the program sources (E3.md D1-D4);
#  2. no regression: qilin.pta >= 101 tests (96 + 5), <= 11 skipped, 0 failed; qilin.ucfs >= 7;
#     the E2 seam test E2PagSeamTest still passes;
#  3. PagExport, UcfsGraph, PtLabels are compiled Kotlin of qilin.ucfs, not Java of other modules;
#  4. tracked files unchanged by the check.
# Usage: bash acceptance/E3/S1_pag_export.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"

expect_cases qilin.pta qilin.test.ucfs.E3PagExportTest fieldSensitivity1 receiver2This arrayIndex staticStore instanceStore
expect_cases qilin.pta qilin.test.ucfs.E2PagSeamTest virtualCall1 instanceStore instanceLoad
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E3PagExportTest "E3PagExportTest " | sed 's/^/  /'
check_totals 101 7

kotlin_class_in_ucfs_jar qilin/ucfs/PagExport.class qilin/ucfs/UcfsGraph.class qilin/ucfs/PtLabels.class
if grep -rlE '\b(class|interface|enum|record) (PagExport|UcfsGraph|PtLabels)\b' qilin.pta/src qilin.core/src qilin.util/src 2>/dev/null | grep -q .; then
    fail "PagExport/UcfsGraph/PtLabels must live only in qilin.ucfs"
else
    pass "PagExport/UcfsGraph/PtLabels live only in qilin.ucfs"
fi

tree_clean
finish S1_pag_export
