#!/usr/bin/env bash
# E5 epic criterion 3 (docs/ai/tickets/E5.md): the verifier reproduces the answer and the order of magnitude of
# the committed results on this machine, with a threshold fixed before the VM run.
#  1. QILIN_JAR=<fresh fat jar of HEAD> REPS=3 WARMUP=1 RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e5-bench.sh
#     <dir> fop lusearch exits 0 and every run is ok (fop and lusearch: the two covered benchmarks with the
#     smallest sum of wall_s of ucfs-ANALYSIS in e4-results/runs.tsv, except pmd/luindex that S5_results.sh
#     repeats; fop 8.7 s, lusearch 11.6 s);
#  2. the answer keys of every repetition here = those of the committed results (R/bench, first ok
#     repetition) for both runs of both benchmarks; otherwise FAIL (exit 1);
#  3. the ratio UCFS/Spark here = median over the repetitions of UCFS-import-ucfs-ms / (1000 * qilin-pta-s) of
#     the same repetition (as table T3 of acceptance/E5/e5tables.py); it is printed next to the ratio of R
#     and the medians of UCFS-import-ucfs-ms and qilin-pta-s of both machines; the threshold: the ratio here /
#     the ratio of R in [0.5, 2] for both benchmarks. Inside -> exit 0. Outside -> exit 3 and the line
#     "RESULT: OUTSIDE-x2 (E5_repro)": not a FAIL of the epic by itself (the machines differ), but the epic
#     verifier must analyse it in the ticket (phases T4 against the phases here, load1/other-java here) and
#     the lead decides.
# Usage: bash acceptance/E5/E5_repro.sh          (exit 0 = within x2, 3 = outside, 1 = FAIL; about 5 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
R="$ROOT/docs/ucfs-integration/e5-results"
[ -f "$R/bench/values.tsv" ] || { fail "no results in $R"; finish E5_repro; }
FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish E5_repro; }
D="$OUT/repro-ratio"
safe_reset_dir "$D"
QILIN_JAR="$FRESH" REPS=3 WARMUP=1 RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e5-bench.sh "$D" fop lusearch \
    > "$LOGS/E5-repro-bench.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh fop lusearch exit 0" || fail "e5-bench.sh exit $rc (see $LOGS/E5-repro-bench.txt)"
py - "$R" "$D" > "$LOGS/E5-repro-check.txt" 2>&1 <<'PY'
import statistics, sys
import e5lib, e5tables
R, D = sys.argv[1:3]
vm, here = e5tables.Part(R + "/bench"), e5tables.Part(D)
fails, outside = 0, []
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
def ratios(p, b):
    out = []
    for k in p.okreps(b, "ucfs-ANALYSIS"):
        if k in p.okreps(b, "insens"):
            s = float(p.v[(b, "insens", k)]["qilin-pta-s"]) * 1000.0
            if s > 0:
                out.append(float(p.v[(b, "ucfs-ANALYSIS", k)]["UCFS-import-ucfs-ms"]) / s)
    return out
for b in ("fop", "lusearch"):
    for run in ("insens", "ucfs-ANALYSIS"):
        reps = here.okreps(b, run)
        ref = vm.okreps(b, run)
        com = {k: v for k, v in vm.v.get((b, run, ref[0]), {}).items() if not e5lib.is_measure(k)} if ref else {}
        got = [{k: v for k, v in here.v[(b, run, k)].items() if not e5lib.is_measure(k)} for k in reps]
        (ok if len(reps) == 3 and com and all(g == com for g in got) else ko)(
            "%s %s: %d ok repetitions here, answer keys = committed (%d keys)" % (b, run, len(reps), len(com)))
    rh, rv = ratios(here, b), ratios(vm, b)
    if not rh or not rv:
        ko("%s: no ratio (here %d, committed %d)" % (b, len(rh), len(rv))); continue
    q = statistics.median(rh) / statistics.median(rv)
    print("RATIO: %s UCFS/Spark here %.3f (UCFS %s ms, Spark %s ms), committed %.3f (UCFS %s ms, Spark %s ms), here / committed %.2f" % (
        b, statistics.median(rh), e5tables.med(here.series(b, "ucfs-ANALYSIS", "UCFS-import-ucfs-ms")),
        e5tables.med(here.series(b, "insens", "qilin-pta-s", 1000.0)), statistics.median(rv),
        e5tables.med(vm.series(b, "ucfs-ANALYSIS", "UCFS-import-ucfs-ms")),
        e5tables.med(vm.series(b, "insens", "qilin-pta-s", 1000.0)), q))
    if not 0.5 <= q <= 2.0:
        outside.append(b)
print("OUTSIDE: %s" % " ".join(outside) if outside else "WITHIN: the ratios here are within x2 of the committed ones")
sys.exit(1 if fails else (3 if outside else 0))
PY
rc=$?
cat "$LOGS/E5-repro-check.txt"
[ $rc -eq 1 ] && FAILS=$((FAILS + 1))
tracked_clean E5_repro
if [ $rc -eq 3 ] && [ "$FAILS" -eq 0 ]; then
    echo "RESULT: OUTSIDE-x2 (E5_repro): the epic verifier analyses the difference (E5.md, criterion 3)"
    exit 3
fi
finish E5_repro
