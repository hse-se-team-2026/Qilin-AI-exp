#!/usr/bin/env bash
# E4-S5 acceptance: the benchmark runner scripts/ucfs/e4-bench.sh (docs/ai/tickets/E4-S5.md).
#  1. QILIN_JAR=<fresh fat jar> TIMEOUT=600 XMX=8g bash scripts/ucfs/e4-bench.sh acceptance/E4/out/bench pmd luindex
#     exits 0 and writes runs.tsv, values.tsv, examples.tsv;
#  2. runs.tsv: header "bench run status exit wall_s max_rss_mb" (TAB), one row per benchmark and run
#     insens, ucfs-ANALYSIS, ucfs-CALL_GRAPH, all status ok, exit 0, wall_s and max_rss_mb positive;
#     every cmd.txt has -jre=<artifact/benchmarks/JREs/jre1.6.0_45>, -pae -pe -clinit=ONFLY -lcs -mh,
#     -exclude=<the JDK list of E4.md D3>, -ucfsseam, and the -pta / -ucfsbinding / -ucfscompare /
#     -ucfspt options of the run;
#  3. values.tsv: header "bench run key value"; exactly one row per line "#<key>: <value>" of each
#     out.txt and per cell of each ucfs-compare/metrics.tsv (key cmp/<VIEW>/<metric without # and :>);
#     cmp/SPARK/<metric> of each ucfs run = <metric> of the insens run of the same benchmark
#     (another JVM: metric values do not depend on node numbering);
#  4. oracle per ucfs run: the independent Andersen fixpoint of its graph.dot = its pts.tsv;
#     UCFS-cmp-MISSING = 0 and UCFS-cmp-UNEXPLAINED = 0;
#  5. examples.tsv: header "bench run class var object"; per ucfs run and class != SAME with n distinct pairs,
#     exactly min(3, n) rows; each row is a pair of pairs.tsv with that class, var and object written
#     as the vertices.tsv node strings without the leading "<NodeKind> <number> " and with every Java
#     identity hash "@<hex>" (e.g. MergedNewExpr@1c24639e) written "@*", and the rows of a (run, class)
#     are the lexicographically smallest such distinct (var, object);
#  6. a run over its time limit: TIMEOUT=3 BINDINGS=ANALYSIS ... xalan -> rows status timeout, exit 124.
# Usage: bash acceptance/E4/S5_bench.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S5_bench; }

BD="$OUT/bench"
safe_reset_dir "$BD"
start=$(date +%s)
QILIN_JAR="$FRESH" TIMEOUT=600 XMX=8g bash scripts/ucfs/e4-bench.sh "$BD" pmd luindex > "$LOGS/S5-bench.txt" 2>&1
rc=$?
echo "  e4-bench.sh pmd luindex: exit $rc, $(( $(date +%s) - start )) s"
[ $rc -eq 0 ] && pass "e4-bench.sh exit 0" || fail "e4-bench.sh exit $rc (see $LOGS/S5-bench.txt)"

TD="$OUT/bench-timeout"
safe_reset_dir "$TD"
QILIN_JAR="$FRESH" TIMEOUT=3 BINDINGS=ANALYSIS bash scripts/ucfs/e4-bench.sh "$TD" xalan > "$LOGS/S5-timeout.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e4-bench.sh with TIMEOUT=3 exit 0" || fail "e4-bench.sh TIMEOUT=3 exit $rc"

python3 - "$BD" "$TD" "$ROOT" "$JDK_EXCLUDE" > "$LOGS/S5-check.txt" 2>&1 <<'PY'
import os, re, sys
bd, td, root, jdk = sys.argv[1:5]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
def tsv(p):
    return [l.rstrip("\n").split("\t") for l in open(p) if l.strip()]
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]
BENCHES = ["luindex", "pmd"]
runs = tsv(os.path.join(bd, "runs.tsv"))
if runs[0] == ["bench", "run", "status", "exit", "wall_s", "max_rss_mb"]:
    ok("runs.tsv header")
else:
    ko("runs.tsv header %s" % runs[0])
got = {(r[0], r[1]): r for r in runs[1:]}
if sorted(got) == sorted((b, r) for b in BENCHES for r in RUNS) and len(got) == len(runs) - 1:
    ok("runs.tsv: one row per benchmark and run")
else:
    ko("runs.tsv rows %s" % sorted(got))
for k, r in sorted(got.items()):
    try:
        good = r[2] == "ok" and r[3] == "0" and float(r[4]) > 0 and int(r[5]) > 0
    except ValueError:
        good = False
    (ok if good else ko)("run %s/%s: %s" % (k[0], k[1], r[2:]))
for b in BENCHES:
    for r in RUNS:
        cmd = open(os.path.join(bd, b, r, "cmd.txt")).read()
        need = ["-jre=" + os.path.join(root, "artifact/benchmarks/JREs/jre1.6.0_45"), "-pae", "-pe", "-clinit=ONFLY",
                "-lcs", "-mh", "-ucfsseam"]
        need += ["-pta=insens"] if r == "insens" else ["-pta=ucfs", "-ucfsbinding=" + r[5:], "-ucfscompare", "-ucfspt"]
        toks = cmd.replace("\\", "").split()
        missing = [n for n in need if n not in toks]
        if not any(t.startswith("-exclude=") and t[len("-exclude="):].replace("\\", "") == jdk for t in cmd.split()) \
                and ("-exclude=" + jdk) not in cmd.replace("\\", ""):
            missing.append("-exclude=<JDK list>")
        (ok if not missing else ko)("cmd.txt %s/%s %s" % (b, r, "has the options" if not missing else "lacks %s" % missing))
vals = tsv(os.path.join(bd, "values.tsv"))
if vals[0] == ["bench", "run", "key", "value"]:
    ok("values.tsv header")
else:
    ko("values.tsv header %s" % vals[0])
V = {}
from collections import Counter
cnt = Counter()
for r in vals[1:]:
    V[(r[0], r[1], r[2])] = r[3]
    cnt[(r[0], r[1], r[2])] += 1
exp = Counter()
for b in BENCHES:
    for r in RUNS:
        d = os.path.join(bd, b, r)
        for l in open(os.path.join(d, "out.txt"), errors="replace"):
            m = re.match(r"^#([^:]+):\s*(\S+)\s*$", l)
            if m:
                exp[(b, r, m.group(1).strip())] += 1
                if V.get((b, r, m.group(1).strip())) != m.group(2):
                    ko("values.tsv %s/%s %s != out.txt %s" % (b, r, m.group(1), m.group(2)))
        mt = os.path.join(d, "sootOutput", "ucfs-compare", "metrics.tsv")
        if r != "insens":
            rows = tsv(mt)
            for row in rows[1:]:
                name = row[0].lstrip("#").rstrip(":").strip()
                for view, x in zip(rows[0][1:], row[1:]):
                    exp[(b, r, "cmp/%s/%s" % (view, name))] += 1
                    if V.get((b, r, "cmp/%s/%s" % (view, name))) != x:
                        ko("values.tsv %s/%s cmp/%s/%s != metrics.tsv %s" % (b, r, view, name, x))
                if V.get((b, r, "cmp/SPARK/" + name)) == V.get((b, "insens", name)) is not None:
                    ok("%s/%s cmp/SPARK/%s = insens %s" % (b, r, name, V.get((b, "insens", name))))
                else:
                    ko("%s/%s cmp/SPARK/%s %s, insens %s" % (b, r, name, V.get((b, r, "cmp/SPARK/" + name)), V.get((b, "insens", name))))
            for c in ["MISSING", "UNEXPLAINED"]:
                (ok if V.get((b, r, "UCFS-cmp-" + c)) == "0" else ko)("%s/%s UCFS-cmp-%s = %s" % (b, r, c, V.get((b, r, "UCFS-cmp-" + c))))
if cnt == exp:
    ok("values.tsv: exactly one row per printed line and per metrics.tsv cell (%d rows)" % sum(cnt.values()))
else:
    ko("values.tsv rows differ from out.txt/metrics.tsv: extra %s missing %s" % (list((cnt - exp).items())[:3], list((exp - cnt).items())[:3]))
ex = tsv(os.path.join(bd, "examples.tsv"))
if ex[0] == ["bench", "run", "class", "var", "object"]:
    ok("examples.tsv header")
else:
    ko("examples.tsv header %s" % ex[0])
E = {}
for r in ex[1:]:
    E.setdefault((r[0], r[1], r[2]), []).append((r[3], r[4]))
for b in BENCHES:
    for r in RUNS[1:]:
        d = os.path.join(bd, b, r, "sootOutput")
        node = {}
        for l in open(os.path.join(d, "ucfs", "vertices.tsv")):
            vid, label, s = l.rstrip("\n").split("\t", 2)
            node[label] = re.sub(r"@[0-9a-f]+\b", "@*", re.sub(r"^\w+ \d+ ", "", s))
        by = {}
        for l in open(os.path.join(d, "ucfs-compare", "pairs.tsv")):
            f = l.rstrip("\n").split("\t")
            if len(f) == 6 and f[5] != "SAME":
                by.setdefault(f[5], set()).add((node[f[0]], node[f[1]]))
        for c in sorted(set(by) | {k[2] for k in E if k[:2] == (b, r)}):
            want = sorted(by.get(c, set()))[:3]
            if E.get((b, r, c), []) == want:
                ok("examples %s/%s %s: %d rows" % (b, r, c, len(want)))
            else:
                ko("examples %s/%s %s: %s, expected %s" % (b, r, c, E.get((b, r, c)), want))
t = tsv(os.path.join(td, "runs.tsv"))
rows = {(r[0], r[1]): r for r in t[1:]}
if sorted(rows) == [("xalan", "insens"), ("xalan", "ucfs-ANALYSIS")] and all(r[2] == "timeout" and r[3] == "124" for r in rows.values()):
    ok("TIMEOUT=3: both xalan runs status timeout, exit 124")
else:
    ko("TIMEOUT=3 rows %s" % t[1:])
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
rc=$?
grep -v '^PASS' "$LOGS/S5-check.txt" | sed 's/^/  /'
[ $rc -eq 0 ] && pass "runs.tsv, values.tsv, examples.tsv and cmd.txt ($(grep -c '^PASS' "$LOGS/S5-check.txt") checks)" \
    || fail "result files (see $LOGS/S5-check.txt)"

for b in pmd luindex; do
    for r in ucfs-ANALYSIS ucfs-CALL_GRAPH; do
        andersen_check "$BD/$b/$r/sootOutput/ucfs" > "$LOGS/S5-andersen-$b-$r.txt" 2>&1 \
            && pass "$b/$r: independent Andersen fixpoint of graph.dot = pts.tsv" || fail "$b/$r: AndersenCheck"
    done
done

tree_clean
finish S5_bench
