#!/usr/bin/env bash
# E4-S5 acceptance: the benchmark runner scripts/ucfs/e4-bench.sh (docs/ai/tickets/E4-S5.md).
#  1. QILIN_JAR=<fresh fat jar> TIMEOUT=600 XMX=8g bash scripts/ucfs/e4-bench.sh acceptance/E4/out/bench pmd luindex
#     exits 0 and writes runs.tsv, values.tsv, examples.tsv, meta.tsv;
#  2. runs.tsv: header "bench run status exit wall_s max_rss_mb" (TAB), one row per benchmark and run
#     insens, ucfs-ANALYSIS, ucfs-CALL_GRAPH, cov-D3, cov-JDK, all status ok, exit 0, wall_s and
#     max_rss_mb positive; every cmd.txt has -jre=<artifact/benchmarks/JREs/jre1.6.0_45>,
#     -pae -pe -clinit=ONFLY -lcs -mh, -ucfsseam, -exclude=<the JDK list of E4.md D3> except cov-JDK (none),
#     and the options of the run (-pta=insens; -pta=ucfs -ucfsbinding=<B> -ucfscompare -ucfspt;
#     -pta=insens -stats);
#  3. values.tsv: header "bench run key value"; exactly one row per line "#<key>: <value>" of each
#     out.txt and per cell of each ucfs-compare/metrics.tsv (key cmp/<VIEW>/<metric without # and :>);
#     cmp/SPARK/<metric> of each ucfs run = <metric> of the insens run of the same benchmark; cov-D3
#     (Qilin's PTAEvaluator) has the insens values of reachable methods, call edges, may-fail casts and
#     average points-to; both cov runs have "Reachable App Method (CI)", and cov-JDK reaches more methods;
#  4. meta.tsv: header "key value"; command, git-head (= HEAD), tree-clean (= yes), jar, jar-sha256
#     (= sha256 of the jar run), benches ("pmd luindex"), runs, timeout (600), xmx (8g), started, finished;
#  5. options checked independently of cmd.txt (E4.md, lead decision M3): reference runs whose arguments
#     acceptance/E4/lib.sh builds (dacapo_args, RUNPY_OPTS, JDK_EXCLUDE; run_cli) give the same value for
#     every key of out.txt that is not a time (keys matching -ms, time, Time), and the same set of keys:
#     insens and ucfs-ANALYSIS of pmd and luindex, ucfs-CALL_GRAPH of pmd, cov-JDK of luindex;
#  6. oracles per ucfs run: the independent Andersen fixpoint of graph.dot = pts.tsv (AndersenCheck.java);
#     the seed counters = SeedCheck.java; UCFS-cmp-last-step-pairs = the CI pairs of the -ptsall dump of
#     the reference insens run (another JVM); UCFS-cmp-MISSING = 0 and UCFS-cmp-UNEXPLAINED = 0;
#  7. examples.tsv: header "bench run class var object"; per ucfs run and class != SAME with n distinct
#     pairs, exactly min(3, n) rows; each row is a pair of pairs.tsv with that class, var and object written
#     as the vertices.tsv node strings without the leading "<NodeKind> <number> " and with every Java
#     identity hash "@<hex>" (e.g. MergedNewExpr@1c24639e) written "@*", and the rows of a (run, class)
#     are the lexicographically smallest such distinct (var, object);
#  8. a run over its time limit: TIMEOUT=3 RUNS="insens ucfs-ANALYSIS" ... chart -> rows status timeout,
#     exit 124; an unknown run name or benchmark -> exit 2;
#  9. tracked files unchanged by the check.
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
QILIN_JAR="$FRESH" TIMEOUT=3 RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e4-bench.sh "$TD" chart > "$LOGS/S5-timeout.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e4-bench.sh with TIMEOUT=3 exit 0" || fail "e4-bench.sh TIMEOUT=3 exit $rc"
QILIN_JAR="$FRESH" RUNS="insens foo" bash scripts/ucfs/e4-bench.sh "$OUT/bench-bad" xalan > /dev/null 2>&1
rc=$?
[ $rc -eq 2 ] && pass "unknown run name: exit 2" || fail "unknown run name: exit $rc"
QILIN_JAR="$FRESH" bash scripts/ucfs/e4-bench.sh "$OUT/bench-bad" nosuchbench > /dev/null 2>&1
rc=$?
[ $rc -eq 2 ] && pass "unknown benchmark: exit 2" || fail "unknown benchmark: exit $rc"

# reference runs, arguments built here (lib.sh), not by e4-bench.sh
DX="-exclude=$JDK_EXCLUDE"
for b in pmd luindex; do
    # shellcheck disable=SC2046,SC2086
    run_cli "$FRESH" "ref-$b-insens" -pta=insens -ptsall -ucfsseam $(dacapo_args $b) $RUNPY_OPTS $DX \
        || fail "reference run $b insens exit $?"
    # shellcheck disable=SC2046,SC2086
    run_cli "$FRESH" "ref-$b-ucfs-ANALYSIS" -pta=ucfs -ucfsbinding=ANALYSIS -ucfscompare -ucfspt -ucfsseam \
        $(dacapo_args $b) $RUNPY_OPTS $DX || fail "reference run $b ucfs-ANALYSIS exit $?"
done
# shellcheck disable=SC2046,SC2086
run_cli "$FRESH" "ref-pmd-ucfs-CALL_GRAPH" -pta=ucfs -ucfsbinding=CALL_GRAPH -ucfscompare -ucfspt -ucfsseam \
    $(dacapo_args pmd) $RUNPY_OPTS $DX || fail "reference run pmd ucfs-CALL_GRAPH exit $?"
# shellcheck disable=SC2046,SC2086
run_cli "$FRESH" "ref-luindex-cov-JDK" -pta=insens -stats -ucfsseam $(dacapo_args luindex) $RUNPY_OPTS \
    || fail "reference run luindex cov-JDK exit $?"

for b in pmd luindex; do
    for r in ucfs-ANALYSIS ucfs-CALL_GRAPH; do
        andersen_check "$BD/$b/$r/sootOutput/ucfs" > "$LOGS/S5-andersen-$b-$r.txt" 2>&1 \
            && pass "$b/$r: independent Andersen fixpoint of graph.dot = pts.tsv" || fail "$b/$r: AndersenCheck"
        "$JAVA" -Xmx8g acceptance/E4/SeedCheck.java "$BD/$b/$r" > "$LOGS/S5-seeds-$b-$r.txt" 2>&1 \
            || fail "$b/$r: SeedCheck.java (see $LOGS/S5-seeds-$b-$r.txt)"
    done
done

python3 - "$BD" "$TD" "$ROOT" "$JDK_EXCLUDE" "$OUT" "$LOGS" "$FRESH" "$(git rev-parse HEAD)" > "$LOGS/S5-check.txt" 2>&1 <<'PY'
import hashlib, os, re, sys
from collections import Counter
bd, td, root, jdk, out, logs, jar, head = sys.argv[1:9]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
def tsv(p):
    return [l.rstrip("\n").split("\t") for l in open(p) if l.strip()]
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH", "cov-D3", "cov-JDK"]
UCFS = ["ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]
BENCHES = ["luindex", "pmd"]
TIME = re.compile(r"-ms$|time|Time")
LINE = re.compile(r"^#([^:]+):\s*(\S+)\s*$")
def printed(d):
    v = {}
    for l in open(os.path.join(d, "out.txt"), errors="replace"):
        m = LINE.match(l)
        if m:
            v.setdefault(m.group(1).strip(), []).append(m.group(2))
    return v
# 2. runs.tsv and cmd.txt
runs = tsv(os.path.join(bd, "runs.tsv"))
(ok if runs[0] == ["bench", "run", "status", "exit", "wall_s", "max_rss_mb"] else ko)("runs.tsv header %s" % runs[0])
got = {(r[0], r[1]): r for r in runs[1:]}
if sorted(got) == sorted((b, r) for b in BENCHES for r in RUNS) and len(got) == len(runs) - 1:
    ok("runs.tsv: one row per benchmark and run (%d)" % len(got))
else:
    ko("runs.tsv rows %s" % sorted(got))
for k, r in sorted(got.items()):
    try:
        good = r[2] == "ok" and r[3] == "0" and float(r[4]) > 0 and int(r[5]) > 0
    except ValueError:
        good = False
    (ok if good else ko)("run %s/%s: %s" % (k[0], k[1], r[2:]))
OPTS = {"insens": ["-pta=insens"], "ucfs-ANALYSIS": ["-pta=ucfs", "-ucfsbinding=ANALYSIS", "-ucfscompare", "-ucfspt"],
        "ucfs-CALL_GRAPH": ["-pta=ucfs", "-ucfsbinding=CALL_GRAPH", "-ucfscompare", "-ucfspt"],
        "cov-D3": ["-pta=insens", "-stats"], "cov-JDK": ["-pta=insens", "-stats"]}
for b in BENCHES:
    for r in RUNS:
        cmd = open(os.path.join(bd, b, r, "cmd.txt")).read().replace("\\", "")
        toks = cmd.split()
        need = ["-jre=" + os.path.join(root, "artifact/benchmarks/JREs/jre1.6.0_45"), "-pae", "-pe", "-clinit=ONFLY",
                "-lcs", "-mh", "-ucfsseam"] + OPTS[r]
        missing = [n for n in need if n not in toks]
        excl = [t for t in toks if t.startswith("-exclude")]
        if r == "cov-JDK":
            if excl:
                missing.append("no -exclude (has %s)" % excl)
        elif excl != ["-exclude=" + jdk]:
            missing.append("-exclude=<JDK list> (has %s)" % excl)
        (ok if not missing else ko)("cmd.txt %s/%s %s" % (b, r, "has the options" if not missing else "lacks %s" % missing))
# 3. values.tsv
vals = tsv(os.path.join(bd, "values.tsv"))
(ok if vals[0] == ["bench", "run", "key", "value"] else ko)("values.tsv header %s" % vals[0])
V, cnt, exp = {}, Counter(), Counter()
for r in vals[1:]:
    V[(r[0], r[1], r[2])] = r[3]
    cnt[(r[0], r[1], r[2])] += 1
P = {}
for b in BENCHES:
    for r in RUNS:
        d = os.path.join(bd, b, r)
        P[(b, r)] = printed(d)
        for k, vs in P[(b, r)].items():
            exp[(b, r, k)] += len(vs)
            if V.get((b, r, k)) != vs[-1] and V.get((b, r, k)) not in vs:
                ko("values.tsv %s/%s %s != out.txt %s" % (b, r, k, vs))
        if r in UCFS:
            rows = tsv(os.path.join(d, "sootOutput", "ucfs-compare", "metrics.tsv"))
            for row in rows[1:]:
                name = row[0].lstrip("#").rstrip(":").strip()
                for view, x in zip(rows[0][1:], row[1:]):
                    exp[(b, r, "cmp/%s/%s" % (view, name))] += 1
                    if V.get((b, r, "cmp/%s/%s" % (view, name))) != x:
                        ko("values.tsv %s/%s cmp/%s/%s != metrics.tsv %s" % (b, r, view, name, x))
                (ok if V.get((b, r, "cmp/SPARK/" + name)) == V.get((b, "insens", name)) is not None else ko)(
                    "%s/%s cmp/SPARK/%s %s = insens %s" % (b, r, name, V.get((b, r, "cmp/SPARK/" + name)), V.get((b, "insens", name))))
            for c in ["MISSING", "UNEXPLAINED"]:
                (ok if V.get((b, r, "UCFS-cmp-" + c)) == "0" else ko)("%s/%s UCFS-cmp-%s = %s" % (b, r, c, V.get((b, r, "UCFS-cmp-" + c))))
    for m in ["Reachable Method (CI)", "Call Edge(CI)", "May Fail Cast (Total)", "Avg Points-to Target without Native Var(CI)"]:
        (ok if V.get((b, "cov-D3", m)) == V.get((b, "insens", m)) is not None else ko)(
            "%s cov-D3 %s %s = insens %s" % (b, m, V.get((b, "cov-D3", m)), V.get((b, "insens", m))))
    try:
        a3, aj = int(V[(b, "cov-D3", "Reachable App Method (CI)")]), int(V[(b, "cov-JDK", "Reachable App Method (CI)")])
        r3, rj = int(V[(b, "cov-D3", "Reachable Method (CI)")]), int(V[(b, "cov-JDK", "Reachable Method (CI)")])
        (ok if a3 > 0 and aj > 0 and rj > r3 else ko)("%s coverage: app methods %d (D3) / %d (JDK), reachable %d / %d" % (b, a3, aj, r3, rj))
    except (KeyError, ValueError) as e:
        ko("%s coverage keys missing: %s" % (b, e))
(ok if cnt == exp else ko)("values.tsv: one row per printed line and per metrics.tsv cell (%d rows; extra %s missing %s)"
                           % (sum(cnt.values()), list((cnt - exp).items())[:3], list((exp - cnt).items())[:3]))
# 4. meta.tsv
meta = tsv(os.path.join(bd, "meta.tsv"))
M = {r[0]: (r[1] if len(r) > 1 else "") for r in meta[1:]}
KEYS = ["command", "git-head", "tree-clean", "jar", "jar-sha256", "benches", "runs", "timeout", "xmx", "started", "finished"]
(ok if meta[0] == ["key", "value"] and [r[0] for r in meta[1:]] == KEYS else ko)("meta.tsv keys %s" % [r[0] for r in meta[1:]])
want = {"git-head": head, "tree-clean": "yes", "jar-sha256": hashlib.sha256(open(jar, "rb").read()).hexdigest(),
        "benches": "pmd luindex", "runs": " ".join(RUNS), "timeout": "600", "xmx": "8g"}
for k, v in want.items():
    (ok if M.get(k) == v else ko)("meta.tsv %s = %s (expected %s)" % (k, M.get(k), v))
(ok if "bash scripts/ucfs/e4-bench.sh" in M.get("command", "") and "pmd luindex" in M.get("command", "") else ko)(
    "meta.tsv command: %s" % M.get("command"))
# 5. reference runs built by lib.sh
pairs = [("pmd", "insens"), ("luindex", "insens"), ("pmd", "ucfs-ANALYSIS"), ("luindex", "ucfs-ANALYSIS"),
         ("pmd", "ucfs-CALL_GRAPH"), ("luindex", "cov-JDK")]
for b, r in pairs:
    ref = printed(os.path.join(out, "run-ref-%s-%s" % (b, r)))
    a = {k: v for k, v in P[(b, r)].items() if not TIME.search(k)}
    z = {k: v for k, v in ref.items() if not TIME.search(k)}
    diff = sorted(k for k in set(a) | set(z) if a.get(k) != z.get(k))
    (ok if not diff and a else ko)("%s/%s: %d non-time keys = reference run of lib.sh arguments%s"
                                   % (b, r, len(a), "" if not diff else ", differ: %s" % [(k, a.get(k), z.get(k)) for k in diff[:4]]))
# 6. last-step pairs and seeds
def ptsall_pairs(d):
    qp = os.path.join(d, "sootOutput", "pts.txt")
    base, n = {}, 0
    for l in open(qp):
        m = re.match(r"^\[(O\d+)\]ContextAllocNode \d+\(AllocNode (\d+) ", l)
        if m: base[m.group(1)] = "O" + m.group(2)
    for l in open(qp):
        m = re.match(r"^([LG]\d+) -> \{(.*)\}\s*$", l)
        if m and m.group(2).strip() != "empty":
            n += len({base.get(o, o) for o in m.group(2).split()})
    return n
COUNTERS = ["new-edges", "seed-this-edges", "seed-exception-edges", "seed-finalizer-edges",
            "same-without-this-seeds", "same-without-seeds"]
for b in BENCHES:
    nspark = ptsall_pairs(os.path.join(out, "run-ref-%s-insens" % b))
    for r in UCFS:
        (ok if V.get((b, r, "UCFS-cmp-last-step-pairs")) == str(nspark) and nspark > 0 else ko)(
            "%s/%s UCFS-cmp-last-step-pairs %s = CI pairs of the reference -ptsall %d" % (b, r, V.get((b, r, "UCFS-cmp-last-step-pairs")), nspark))
        s = open(os.path.join(logs, "S5-seeds-%s-%s.txt" % (b, r))).read()
        m = re.search(r"^SEEDS new (\d+) this (\d+) exception (\d+) finalizer (\d+) same \d+ same-without-this-seeds (\d+) "
                      r"same-without-seeds (\d+)$", s, re.M)
        if not m:
            ko("%s/%s: no SEEDS line" % (b, r)); continue
        exp6 = dict(zip(COUNTERS, m.groups()))
        diff = [(k, V.get((b, r, "UCFS-cmp-" + k)), exp6[k]) for k in COUNTERS if V.get((b, r, "UCFS-cmp-" + k)) != exp6[k]]
        (ok if not diff else ko)("%s/%s seed counters = SeedCheck%s" % (b, r, "" if not diff else ": %s" % diff))
# 7. examples.tsv
ex = tsv(os.path.join(bd, "examples.tsv"))
(ok if ex[0] == ["bench", "run", "class", "var", "object"] else ko)("examples.tsv header %s" % ex[0])
E = {}
for r in ex[1:]:
    E.setdefault((r[0], r[1], r[2]), []).append((r[3], r[4]))
for b in BENCHES:
    for r in UCFS:
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
            (ok if E.get((b, r, c), []) == want else ko)("examples %s/%s %s: %d rows" % (b, r, c, len(want)))
# 8. timeout
t = tsv(os.path.join(td, "runs.tsv"))
rows = {(r[0], r[1]): r for r in t[1:]}
if sorted(rows) == [("chart", "insens"), ("chart", "ucfs-ANALYSIS")] and all(r[2] == "timeout" and r[3] == "124" for r in rows.values()):
    ok("TIMEOUT=3: both chart runs status timeout, exit 124")
else:
    ko("TIMEOUT=3 rows %s" % t[1:])
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
rc=$?
grep -v '^PASS' "$LOGS/S5-check.txt" | sed 's/^/  /'
[ $rc -eq 0 ] && pass "runs.tsv, values.tsv, examples.tsv, meta.tsv, cmd.txt, reference runs ($(grep -c '^PASS' "$LOGS/S5-check.txt") checks)" \
    || fail "result files (see $LOGS/S5-check.txt)"

tree_clean
finish S5_bench
