#!/usr/bin/env bash
# E5-S1 acceptance: phase times of the UCFS part of -pta=ucfs, and the answer unchanged
# (docs/ai/tickets/E5-S1.md).
#  1. `gradle clean build` exits 0; qilin.pta >= 113 tests, <= 11 skipped, 0 failed; qilin.ucfs >= 17 tests,
#     0 skipped, 0 failed; the three cases of qilin.ucfs.acceptance.E5PhaseTimesTest PASSED (the solver call
#     with phase times answers as the call without them; its phases are rsm, input, parse, roots in this
#     order; the phase rsm holds the lazy RSM build of a fresh grammar and is not repeated for the same
#     instance; on a long chain of assignments parse holds the GLL run: >= 2 x (input + roots), every phase
#     > 0);
#  2. CLI, fresh fat jar: -pta=ucfs (D3 options of E4: acceptance/E4/lib.sh dacapo_args, RUNPY_OPTS,
#     JDK_EXCLUDE, -ucfsseam) on pmd and luindex in both bindings: exit 0 and the lines
#     "#UCFS-phase-<p>-ms: <ms, three decimals>" for p = export grammar rsm input parse roots pairs import,
#     then total, once each and in this order, after #UCFS-import-ucfs-ms; every phase > 0.000; the phases sum
#     to the total within max(5 ms, 1 %) and not above it; total within max(5 ms, 1 %) of #UCFS-import-ucfs-ms
#     and not above it by more than 1.5 ms (e5lib.phase_problems); the Spark kernel and the UCFS part lie
#     inside the evaluator's time of pureRun: UCFS-import-spark-ms + UCFS-import-ucfs-ms <= 1000 *
#     qilin-pta-s + 2 and qilin-pta-s <= qilin-main-pta-s (e5lib.time_problems); -pta=insens prints no
#     #UCFS-phase- line;
#  3. the answer is the one of the code before E5: every answer key of these runs (all keys except those
#     ending in -ms, -s, -mb) equals the value of the committed full E4 run
#     docs/ucfs-integration/e4-results/values.tsv (git-head 557de3d) for the same benchmark and run, and the
#     run has exactly the E4 keys without -ucfscompare/-ucfspt keys;
#  4. the E4 runner on the new code: `RUNS="insens ucfs-ANALYSIS ucfs-CALL_GRAPH" bash scripts/ucfs/e4-bench.sh
#     <dir> pmd luindex` gives for every key of values.tsv that is not an E4 time key (-ms$|time|Time) the
#     committed E4 value, the same key set as E4 for these runs, and the committed examples.tsv rows (the
#     comparison classes and examples of -ucfscompare did not change);
#  5. tracked files unchanged by the check.
# Usage: bash acceptance/E5/S1_phases.sh          (exit 0 = PASS; about 5 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"

clean_build
rc=$?
[ $rc -eq 0 ] && pass "gradle clean build" || fail "gradle clean build exit $rc (see $LOGS/build.log)"
check_totals 113 17
expect_cases qilin.ucfs qilin.ucfs.acceptance.E5PhaseTimesTest timedCallAnswersAsUntimed rsmPhaseHoldsTheRsmBuild \
    parsePhaseHoldsGllOnALongChain

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S1_phases; }

for b in pmd luindex; do
    for B in ANALYSIS CALL_GRAPH; do
        run_cli "$FRESH" "S1-$b-$B" -pta=ucfs -ucfsbinding=$B $RUNPY_OPTS $(dacapo_args $b) -ucfsseam "-exclude=$JDK_EXCLUDE"
        rc=$?
        [ $rc -eq 0 ] && pass "$b -pta=ucfs -ucfsbinding=$B exit 0" || fail "$b $B exit $rc"
    done
done
run_cli "$FRESH" "S1-pmd-insens" -pta=insens $RUNPY_OPTS $(dacapo_args pmd) -ucfsseam "-exclude=$JDK_EXCLUDE"
rc=$?
[ $rc -eq 0 ] && pass "pmd -pta=insens exit 0" || fail "pmd -pta=insens exit $rc"

BD="$OUT/e4bench"
safe_reset_dir "$BD"
QILIN_JAR="$FRESH" TIMEOUT=600 XMX=8g RUNS="insens ucfs-ANALYSIS ucfs-CALL_GRAPH" \
    bash scripts/ucfs/e4-bench.sh "$BD" pmd luindex > "$LOGS/S1-e4bench.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e4-bench.sh pmd luindex exit 0" || fail "e4-bench.sh exit $rc (see $LOGS/S1-e4bench.txt)"

py - "$OUT" "$E4_RESULTS" "$BD" > "$LOGS/S1-check.txt" 2>&1 <<'PY'
import os, sys
import e5lib
out, e4dir, bd = sys.argv[1:4]
e4 = e5lib.e4_values(e4dir)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)

for b in ("pmd", "luindex"):
    for B in ("ANALYSIS", "CALL_GRAPH"):
        p = os.path.join(out, "run-S1-%s-%s" % (b, B), "out.txt")
        if not os.path.exists(p):
            ko("%s %s: no out.txt" % (b, B)); continue
        kv = e5lib.parse_out(open(p, errors="replace").read())
        probs = e5lib.time_problems("ucfs-" + B, kv, float("inf"))
        if probs:
            ko("%s %s phases: %s" % (b, B, "; ".join(probs)))
        else:
            d = dict(kv)
            ok("%s %s phases: %s" % (b, B, " ".join("%s=%s" % (k[len("UCFS-phase-"):-3], d[k])
                                                     for k, _ in kv if k.startswith("UCFS-phase-"))))
        ans = {k: v for k, v in kv if not e5lib.is_measure(k)}
        ref = e5lib.e4_answer(e4, b, "ucfs-" + B)
        if not ref:
            ko("%s ucfs-%s: no E4 values" % (b, B))
        elif ans == ref:
            ok("%s ucfs-%s: %d answer keys = E4 committed" % (b, B, len(ans)))
        else:
            diff = sorted(set(ans) ^ set(ref)) + sorted(k for k in set(ans) & set(ref) if ans[k] != ref[k])
            ko("%s ucfs-%s: answer differs from E4 in %s" % (b, B, diff[:8]))
p = os.path.join(out, "run-S1-pmd-insens", "out.txt")
kv = e5lib.parse_out(open(p, errors="replace").read()) if os.path.exists(p) else []
if any(k.startswith("UCFS-phase-") for k, _ in kv) or not kv:
    ko("pmd -pta=insens: phase lines present or no output")
else:
    ok("pmd -pta=insens prints no #UCFS-phase- line")
ans = {k: v for k, v in kv if not e5lib.is_measure(k)}
ref = e5lib.e4_answer(e4, "pmd", "insens")
(ok if ans == ref and ref else ko)("pmd insens: %d answer keys vs E4 %d" % (len(ans), len(ref)))

# 4. the E4 runner on the new code against the committed E4 results
try:
    rows = e5lib.read_tsv(os.path.join(bd, "values.tsv"))
except OSError:
    rows = []
    ko("e4-bench values.tsv missing")
new = {}
for r in rows:
    if not e5lib.E4_TIME.search(r["key"]):
        new.setdefault((r["bench"], r["run"]), {})[r["key"]] = r["value"]
for b in ("pmd", "luindex"):
    for run in ("insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH"):
        ref = {k: v for k, v in e4.get((b, run), {}).items() if not e5lib.E4_TIME.search(k)}
        got = new.get((b, run), {})
        if ref and got == ref:
            ok("e4-bench %s %s: %d keys = E4 committed" % (b, run, len(ref)))
        else:
            diff = sorted(set(got) ^ set(ref)) + sorted(k for k in set(got) & set(ref) if got[k] != ref[k])
            ko("e4-bench %s %s: differs from E4 in %s" % (b, run, diff[:8]))
def ex(path):
    try:
        return sorted(tuple(r.values()) for r in e5lib.read_tsv(path) if r["bench"] in ("pmd", "luindex"))
    except OSError:
        return None
a, z = ex(os.path.join(bd, "examples.tsv")), ex(os.path.join(e4dir, "examples.tsv"))
(ok if a is not None and a == z else ko)("e4-bench examples.tsv pmd/luindex: %s rows vs E4 %d" % (
    None if a is None else len(a), len(z)))
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S1-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S1
finish S1_phases
