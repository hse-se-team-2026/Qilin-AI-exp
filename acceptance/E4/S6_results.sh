#!/usr/bin/env bash
# E4-S6 acceptance: the committed results of the full E4 run on the 12 benchmarks,
# docs/ucfs-integration/e4-results/ (docs/ai/tickets/E4-S6.md).
#  1. the files runs.tsv, values.tsv, examples.tsv, meta.tsv (written by scripts/ucfs/e4-bench.sh),
#     bench.log (its standard output) and probe_jdk.txt (standard output of acceptance/E4/probe_jdk.sh)
#     exist;
#  2. meta.tsv: the run was one invocation of e4-bench.sh on the 12 benchmarks of E4.md D3 with the
#     default runs, TIMEOUT 900 and XMX 16g, on a clean tree (tree-clean yes) at a commit git-head that
#     this repository has, and the code that makes the numbers is the code of HEAD:
#     git diff git-head HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src scripts/ucfs/e4-bench.sh
#     gradle.properties is empty (on main the epic verifier also checks that git-head is an ancestor);
#  3. runs.tsv: the 12 benchmarks x insens, ucfs-ANALYSIS, ucfs-CALL_GRAPH, cov-D3, cov-JDK; status ok
#     (exit 0), timeout (exit 124) or error; insens and cov-D3 ok everywhere; ucfs-ANALYSIS ok on >= 2
#     benchmarks whose D3 coverage (tables.py T5: app methods cov-D3 / cov-JDK) is >= 50 %;
#     bench.log has the line "e4-bench: <bench> <run>" of every run and the summary line;
#  4. values.tsv and examples.tsv hold rows only of runs in runs.tsv; for every finished ucfs run:
#     cmp/SPARK/<metric> = <metric> of insens, the three call-graph metrics equal in the views, all
#     #UCFS-cmp- counters are there and UCFS-cmp-last-step-pairs = UCFS-cmp-spark-pairs (the last
#     reference step reproduces Spark at benchmark scale, E4.md lead decision M2); cov-D3 has the insens
#     values of reachable methods, call edges, may-fail casts and average points-to; at most 3 examples
#     per run and class;
#  5. probe_jdk.txt: the PROBE lines of probe_jdk.sh (bench, the four seam counts, finished/exit/wall/RSS;
#     the import lines when it finished);
#  6. reproducibility: a run of e4-bench.sh on pmd and luindex at the current HEAD (the run of
#     S5_bench.sh in acceptance/E4/out/bench when its meta.tsv says git-head = HEAD and tree-clean yes,
#     else one made here) gives for those two benchmarks the committed value of every key that is not a
#     time (keys matching -ms, time, Time), the same set of keys and the same examples.tsv rows;
#  7. tracked files unchanged by the check.
# Usage: bash acceptance/E4/S6_results.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
RES=docs/ucfs-integration/e4-results
for f in runs.tsv values.tsv examples.tsv meta.tsv bench.log probe_jdk.txt; do
    [ -f "$RES/$f" ] && pass "$RES/$f exists" || fail "$RES/$f missing"
done
[ "$FAILS" -eq 0 ] || finish S6_results

head_at_run="$(awk -F'\t' '$1 == "git-head" {print $2}' "$RES/meta.tsv")"
if [ -n "$head_at_run" ] && git cat-file -e "$head_at_run^{commit}" 2>/dev/null; then
    pass "meta.tsv git-head $head_at_run is a commit of this repository"
    git diff --quiet "$head_at_run" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src scripts/ucfs/e4-bench.sh gradle.properties \
        && pass "the code of the full run is the code of HEAD (git diff git-head HEAD on the code paths is empty)" \
        || fail "code changed since the full run: $(git diff --stat "$head_at_run" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src scripts/ucfs/e4-bench.sh gradle.properties | tail -n 1)"
else
    fail "meta.tsv git-head '$head_at_run' is not a commit of this repository"
fi

python3 - "$RES" <<'PY' > "$LOGS/S6-check.txt" 2>&1
import os, re, sys
sys.path.insert(0, "acceptance/E4")
import tables
res = sys.argv[1]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
def tsv(p):
    return [l.rstrip("\n").split("\t") for l in open(p) if l.strip()]
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan", "checkstyle", "findbugs", "JPC"]
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH", "cov-D3", "cov-JDK"]
meta = {r[0]: (r[1] if len(r) > 1 else "") for r in tsv(os.path.join(res, "meta.tsv"))[1:]}
for k, v in {"tree-clean": "yes", "runs": " ".join(RUNS), "timeout": "900", "xmx": "16g"}.items():
    (ok if meta.get(k) == v else ko)("meta.tsv %s = %s (expected %s)" % (k, meta.get(k), v))
(ok if sorted(meta.get("benches", "").split()) == sorted(BENCHES) else ko)("meta.tsv benches: %s" % meta.get("benches"))
(ok if "bash scripts/ucfs/e4-bench.sh" in meta.get("command", "") and all(b in meta.get("command", "").split() for b in BENCHES)
 else ko)("meta.tsv command: %s" % meta.get("command"))
runs = {(r[0], r[1]): r for r in tsv(os.path.join(res, "runs.tsv"))[1:]}
(ok if sorted(runs) == sorted((b, r) for b in BENCHES for r in RUNS) else ko)("runs.tsv: %d rows for 12 benchmarks x 5 runs" % len(runs))
for k, r in sorted(runs.items()):
    st, ex = r[2], r[3]
    good = (st == "ok" and ex == "0") or (st == "timeout" and ex == "124") or (st == "error" and ex not in ("0", "124"))
    try:
        good = good and float(r[4]) > 0 and int(r[5]) > 0
    except ValueError:
        good = False
    if not good:
        ko("runs.tsv row %s" % r)
    if k[1] in ("insens", "cov-D3") and st != "ok":
        ko("%s/%s status %s (Spark without JDK bodies must finish)" % (k[0], k[1], st))
rv, vals = tables.load(res)
cov = {b: tables.coverage(rv, vals, b) for b in BENCHES}
good = [b for b in BENCHES if (cov[b] or 0) >= tables.COVERED_PCT and runs.get((b, "ucfs-ANALYSIS"), [""] * 3)[2] == "ok"]
(ok if len(good) >= 2 else ko)("ucfs-ANALYSIS ok on %d benchmarks with D3 coverage >= %.0f %%: %s (coverage: %s)"
                               % (len(good), tables.COVERED_PCT, good, {b: (None if c is None else round(c, 1)) for b, c in cov.items()}))
log = open(os.path.join(res, "bench.log"), errors="replace").read()
miss = [(b, r) for b in BENCHES for r in RUNS if ("e4-bench: %s %s\n" % (b, r)) not in log]
(ok if not miss else ko)("bench.log: a line per run%s" % ("" if not miss else ", missing %s" % miss[:5]))
(ok if re.search(r"^e4-bench: 60 runs, \d+ values, \d+ examples in ", log, re.M) else ko)("bench.log summary line")
V = {}
for r in tsv(os.path.join(res, "values.tsv"))[1:]:
    if (r[0], r[1]) not in runs:
        ko("values.tsv row of a run not in runs.tsv: %s" % r[:3])
        break
    V[(r[0], r[1], r[2])] = r[3]
COUNTERS = ["spark-pairs", "ucfs-pairs", "typed-pairs", "SAME", "R3", "R4b", "R1", "R2", "R5", "UNEXPLAINED", "MISSING",
            "new-edges", "seed-this-edges", "seed-exception-edges", "seed-finalizer-edges", "same-without-this-seeds",
            "same-without-seeds", "last-step-pairs", "dispatch-cg-edges", "dispatch-new-edges-UCFS"]
METRICS = ["Reachable Method (CI)", "Call Edge(CI)", "May Fail Cast (Total)", "Virtual Call Site(Polymorphic)",
           "globalAlias_incstst", "Avg Points-to Target without Native Var(CI)"]
nfin = 0
for b in BENCHES:
    for m in ["Reachable Method (CI)", "Call Edge(CI)", "May Fail Cast (Total)", "Avg Points-to Target without Native Var(CI)"]:
        if V.get((b, "cov-D3", m)) != V.get((b, "insens", m)) or V.get((b, "insens", m)) is None:
            ko("%s cov-D3 %s %s, insens %s" % (b, m, V.get((b, "cov-D3", m)), V.get((b, "insens", m))))
    for r in ["ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]:
        if runs.get((b, r), [""] * 3)[2] != "ok":
            continue
        nfin += 1
        for m in METRICS:
            if V.get((b, r, "cmp/SPARK/" + m)) != V.get((b, "insens", m)):
                ko("%s/%s cmp/SPARK/%s %s, insens %s" % (b, r, m, V.get((b, r, "cmp/SPARK/" + m)), V.get((b, "insens", m))))
        for m in METRICS[:2] + METRICS[3:4]:
            xs = {V.get((b, r, "cmp/%s/%s" % (v, m))) for v in ["SPARK", "UCFS", "UCFS_TYPED"]}
            if len(xs) != 1 or None in xs:
                ko("%s/%s %s differs between views: %s" % (b, r, m, xs))
        lack = [k for k in COUNTERS if not (V.get((b, r, "UCFS-cmp-" + k)) or "").isdigit()]
        if lack:
            ko("%s/%s lacks the counters %s" % (b, r, lack))
        elif V[(b, r, "UCFS-cmp-last-step-pairs")] != V[(b, r, "UCFS-cmp-spark-pairs")]:
            ko("%s/%s last-step-pairs %s != spark-pairs %s" % (b, r, V[(b, r, "UCFS-cmp-last-step-pairs")], V[(b, r, "UCFS-cmp-spark-pairs")]))
ok("%d finished ucfs runs checked (metrics, call-graph lines, counters, last step = Spark)" % nfin)
ex = tsv(os.path.join(res, "examples.tsv"))
from collections import Counter
per = Counter((r[0], r[1], r[2]) for r in ex[1:])
badex = [k for k, n in per.items() if n > 3 or runs.get(k[:2], [""] * 3)[2] != "ok" or not k[1].startswith("ucfs-")]
(ok if ex[0] == ["bench", "run", "class", "var", "object"] and not badex else ko)("examples.tsv: %d rows%s" % (len(ex) - 1, "" if not badex else ", bad %s" % badex[:3]))
probe = open(os.path.join(res, "probe_jdk.txt"), errors="replace").read()
p1 = re.search(r"^PROBE bench=(\S+) timeout_s=(\d+) xmx=(\S+)", probe, re.M)
seam = re.findall(r"^PROBE seam: #UCFS-seam-(NEW|ASSIGN|LOAD|STORE): (\d+)$", probe, re.M)
fin = re.search(r"^PROBE finished=(yes|no) exit=(\d+) wall_s=(\d+) max_rss_mb=(\d+)$", probe, re.M)
(ok if p1 and sorted(k for k, _ in seam) == ["ASSIGN", "LOAD", "NEW", "STORE"] and fin else ko)(
    "probe_jdk.txt: PROBE bench, four seam counts, finished line (%s)" % (fin.group(0) if fin else None))
if fin and fin.group(1) == "yes":
    (ok if re.search(r"^PROBE result: #UCFS-import-pairs: \d+$", probe, re.M) else ko)("probe_jdk.txt: import lines of the finished probe")
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
rc=$?
grep -v '^PASS' "$LOGS/S6-check.txt" | sed 's/^/  /'
[ $rc -eq 0 ] && pass "e4-results: meta, runs, values, examples, bench.log, probe ($(grep -c '^PASS' "$LOGS/S6-check.txt") checks)" \
    || fail "e4-results (see $LOGS/S6-check.txt)"

# 6. reproducibility on pmd and luindex at HEAD
REPRO="$OUT/bench"
reuse=no
if [ -f "$REPRO/meta.tsv" ] && [ -f "$REPRO/runs.tsv" ] \
        && [ "$(awk -F'\t' '$1 == "git-head" {print $2}' "$REPRO/meta.tsv")" = "$(git rev-parse HEAD)" ] \
        && [ "$(awk -F'\t' '$1 == "tree-clean" {print $2}' "$REPRO/meta.tsv")" = yes ] \
        && [ "$(cut -f1 "$REPRO/runs.tsv" | sort -u | tr '\n' ' ')" = "bench luindex pmd " ]; then
    reuse=yes
else
    FRESH="$OUT/qilin-fat.jar"
    fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S6_results; }
    REPRO="$OUT/bench-s6"
    safe_reset_dir "$REPRO"
    QILIN_JAR="$FRESH" TIMEOUT=600 XMX=8g bash scripts/ucfs/e4-bench.sh "$REPRO" pmd luindex > "$LOGS/S6-bench.txt" 2>&1 \
        || fail "e4-bench.sh pmd luindex (see $LOGS/S6-bench.txt)"
fi
echo "  reproducibility run: $REPRO (reused the run of S5_bench.sh at HEAD: $reuse)"
python3 - "$RES" "$REPRO" <<'PY'
import os, re, sys
res, rep = sys.argv[1:3]
TIME = re.compile(r"-ms$|time|Time")
def vals(d):
    out = {}
    for l in open(os.path.join(d, "values.tsv")):
        f = l.rstrip("\n").split("\t")
        if len(f) == 4 and f[0] in ("pmd", "luindex") and not TIME.search(f[2]):
            out[(f[0], f[1], f[2])] = f[3]
    return out
def ex(d):
    return sorted(l for l in open(os.path.join(d, "examples.tsv")) if l.split("\t")[0] in ("pmd", "luindex"))
a, b = vals(res), vals(rep)
bad = 0
if set(a) != set(b):
    print("FAIL: keys differ: committed only %s, fresh only %s" % (sorted(set(a) - set(b))[:5], sorted(set(b) - set(a))[:5])); bad += 1
diff = [(k, a[k], b[k]) for k in sorted(set(a) & set(b)) if a[k] != b[k]]
for d in diff[:5]:
    print("FAIL: %s committed %s, fresh %s" % d)
bad += len(diff)
if ex(res) != ex(rep):
    print("FAIL: examples.tsv rows of pmd/luindex differ"); bad += 1
print(("PASS: committed values of pmd and luindex reproduced (%d keys, examples equal)" % len(a)) if not bad else "RESULT-PY: FAIL")
sys.exit(1 if bad else 0)
PY
rc=$?
[ $rc -eq 0 ] && pass "committed results reproduced on pmd and luindex" || fail "results not reproduced"
tree_clean
finish S6_results
