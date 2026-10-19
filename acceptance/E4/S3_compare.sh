#!/usr/bin/env bash
# E4-S3 acceptance: same-run comparison of Spark and UCFS, -pta=ucfs -ucfscompare
# (qilin.pta.ucfs.UcfsCompare; docs/ai/tickets/E4-S3.md).
#  1. `gradle clean build` green; qilin.test.ucfs.E4UcfsCompareTest PASSED (2 cases): on the 43 small
#     programs and both bindings, every row of UcfsCompare.pairs = the row computed by the test from
#     the E3 references (flags and class, E3.md D16 + R3), and UcfsCompare.metrics = Qilin's
#     SimplifiedEvaluator per view; no regression: qilin.pta >= 111 tests, <= 11 skipped, 0 failed;
#  2. CLI, for each program a run U = -pta=ucfs -ucfsbinding=<B> -ucfscompare -ucfspt and a run
#     I = -pta=insens -ptsall with the same other arguments:
#     a. <outdir>/ucfs-compare/metrics.tsv: header "metric<TAB>SPARK<TAB>UCFS<TAB>UCFS_TYPED" and the
#        six metric lines of UcfsCompare.METRICS in order; column SPARK = the lines printed by I,
#        column UCFS = the lines printed by U; the three call-graph lines equal in all columns;
#     b. pairs.tsv: "var<TAB>object<TAB>S<TAB>U<TAB>T<TAB>class", labels of vertices.tsv, flags 0/1,
#        class in SAME R3 R4b R1 R2 R5 UNEXPLAINED MISSING, no pair twice; SAME <=> S=U=1, MISSING
#        <=> S=1,U=0; T=1 => U=1; the pairs with U=1 = pts.tsv = the independent Andersen fixpoint
#        of graph.dot (acceptance/E4/AndersenCheck.java); the number of pairs with S=1 = the number
#        of CI pairs in I's -ptsall dump (another JVM: a count, not labels); class R4b <=> the object
#        is ROOT; R3 only with CALL_GRAPH;
#     c. the lines #UCFS-cmp-binding, -spark-pairs, -ucfs-pairs, -typed-pairs and #UCFS-cmp-<class>
#        for the 8 classes, each once, equal to the counts of pairs.tsv and to the #UCFS-import- lines;
#     d. MISSING = 0 and UNEXPLAINED = 0 (Spark subset of UCFS; every extra pair is removed by one of
#        the solver's filters, E3.md D16) on these programs;
#  3. -ucfscompare with -pta=insens exits non-zero.
# Programs: qilin.microben array.ArrayElemTypeFiltering (ANALYSIS), assign.Receiver2This (CALL_GRAPH),
# DaCapo-2006 pmd and luindex (ANALYSIS) with JDK bodies excluded.
# Usage: bash acceptance/E4/S3_compare.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
expect_cases qilin.pta qilin.test.ucfs.E4UcfsCompareTest pairsAndClassesAgainstReferences metricsPerViewAsQilinPrintsThem
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E4UcfsCompareTest "E4UcfsCompareTest total" | sed 's/^/  /'
check_totals 111 14

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S3_compare; }

check_compare() { # <U dir> <I dir> <binding>
    python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
u, i, binding = sys.argv[1:4]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
METRICS = ["#Reachable Method (CI):", "#Call Edge(CI):", "#May Fail Cast (Total):",
           "#Virtual Call Site(Polymorphic):", "#globalAlias_incstst:",
           "#Avg Points-to Target without Native Var(CI):"]
CLASSES = ["SAME", "R3", "R4b", "R1", "R2", "R5", "UNEXPLAINED", "MISSING"]
def printed(d):
    ls = [l.rstrip("\n") for l in open(os.path.join(d, "out.txt"), errors="replace")]
    out = {}
    for l in ls:
        m = re.match(r"^(#[^:]+:)\s*(\S+)\s*$", l)
        if m:
            out.setdefault(m.group(1), []).append(m.group(2))
    return out
pu, pi = printed(u), printed(i)
cmpdir = os.path.join(u, "sootOutput", "ucfs-compare")
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(cmpdir, "metrics.tsv")) if l.strip()]
if rows and rows[0] == ["metric", "SPARK", "UCFS", "UCFS_TYPED"] and [r[0] for r in rows[1:]] == METRICS \
        and all(len(r) == 4 for r in rows):
    ok("metrics.tsv: header and the six metric lines in order")
else:
    ko("metrics.tsv layout: %s" % [r[:1] for r in rows])
    print("RESULT-PY: FAIL"); sys.exit(1)
for r in rows[1:]:
    name, s, uu, t = r
    if pi.get(name) == [s]:
        ok("SPARK %s %s = -pta=insens" % (name, s))
    else:
        ko("SPARK %s %s, -pta=insens printed %s" % (name, s, pi.get(name)))
    if pu.get(name) == [uu]:
        ok("UCFS %s %s = printed by the -pta=ucfs run" % (name, uu))
    else:
        ko("UCFS %s %s, -pta=ucfs printed %s" % (name, uu, pu.get(name)))
    if name in METRICS[:2] + METRICS[3:4] and not (s == uu == t):
        ko("call-graph line %s differs between views: %s" % (name, r[1:]))
dump = os.path.join(u, "sootOutput", "ucfs")
node = {}
for l in open(os.path.join(dump, "vertices.tsv")):
    vid, label, sname = l.rstrip("\n").split("\t", 2)
    node[label] = sname
roots = {lab for lab, sname in node.items() if re.match(r"^AllocNode \d+ ROOT ", sname)}
pts = set(tuple(l.rstrip("\n").split("\t")) for l in open(os.path.join(dump, "pts.tsv")) if l.strip())
cnt = {c: 0 for c in CLASSES}
seen, uset = set(), set()
s1 = t1 = 0
nbad = 0
for l in open(os.path.join(cmpdir, "pairs.tsv")):
    f = l.rstrip("\n").split("\t")
    if len(f) != 6 or f[2] not in "01" or f[3] not in "01" or f[4] not in "01" or f[5] not in CLASSES \
            or f[0] not in node or f[1] not in node:
        nbad += 1
        if nbad <= 3: ko("bad pairs.tsv line: %r" % l)
        continue
    v, o, S, U, T, c = f[0], f[1], f[2] == "1", f[3] == "1", f[4] == "1", f[5]
    if (v, o) in seen:
        nbad += 1; ko("pair twice: %s %s" % (v, o))
    seen.add((v, o))
    cnt[c] += 1
    s1 += S; t1 += T
    if U: uset.add((v, o))
    rule = ((c == "SAME") == (S and U)) and ((c == "MISSING") == (S and not U)) and (not T or U) \
        and (c != "R4b" or o in roots) and (not (o in roots and U and not S) or c == "R4b") \
        and (c != "R3" or binding == "CALL_GRAPH") and (S or U)
    if not rule:
        nbad += 1
        if nbad <= 5: ko("pairs.tsv row breaks the rules: %s" % f)
if nbad == 0:
    ok("pairs.tsv: %d rows, layout and flag/class rules hold" % len(seen))
if uset == pts:
    ok("pairs with U=1 = pts.tsv (%d)" % len(pts))
else:
    ko("pairs with U=1 (%d) != pts.tsv (%d)" % (len(uset), len(pts)))
# Spark pairs of I's -ptsall dump (CI), counted
qp = os.path.join(i, "sootOutput", "pts.txt")
base = {}
for l in open(qp):
    m = re.match(r"^\[(O\d+)\]ContextAllocNode \d+\(AllocNode (\d+) ", l)
    if m: base[m.group(1)] = "O" + m.group(2)
nspark = 0
for l in open(qp):
    m = re.match(r"^([LG]\d+) -> \{(.*)\}\s*$", l)
    if m and m.group(2).strip() != "empty":
        nspark += len({base.get(o, o) for o in m.group(2).split()})
if s1 == nspark and nspark > 0:
    ok("pairs with S=1 = %d = CI pairs of -pta=insens -ptsall" % s1)
else:
    ko("pairs with S=1 %d, CI pairs of -ptsall %d" % (s1, nspark))
def one(k):
    v = pu.get(k, [])
    return v[0] if len(v) == 1 else None
exp = {"#UCFS-cmp-binding:": binding, "#UCFS-cmp-spark-pairs:": str(s1), "#UCFS-cmp-ucfs-pairs:": str(len(uset)),
       "#UCFS-cmp-typed-pairs:": str(t1)}
for c in CLASSES:
    exp["#UCFS-cmp-%s:" % c] = str(cnt[c])
for k, v in exp.items():
    if one(k) == v:
        ok("%s %s" % (k, v))
    else:
        ko("%s printed %s, expected %s" % (k, pu.get(k), v))
try:
    if len(uset) == int(one("#UCFS-import-pairs:")) + int(one("#UCFS-import-root-pairs:")) \
            and t1 == int(one("#UCFS-import-typed-pairs:")):
        ok("ucfs-pairs = import-pairs + root-pairs, typed-pairs = import-typed-pairs")
    else:
        ko("compare counts disagree with the #UCFS-import- lines")
except (TypeError, ValueError):
    ko("#UCFS-import- lines missing")
for c in ["MISSING", "UNEXPLAINED"]:
    if cnt[c] == 0:
        ok("%s = 0" % c)
    else:
        ko("%s = %d" % (c, cnt[c]))
print("COMPARE %s %s" % (binding, " ".join("%s=%d" % (c, cnt[c]) for c in CLASSES)))
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
}

MB="qilin.microben.core"
DX="-exclude=$JDK_EXCLUDE"
for spec in "afilt|ANALYSIS|-apppath $MICROBEN_CLASSES -mainclass $MB.array.ArrayElemTypeFiltering $JUNIT_OPTS" \
            "r2t|CALL_GRAPH|-apppath $MICROBEN_CLASSES -mainclass $MB.assign.Receiver2This $JUNIT_OPTS" \
            "pmd|ANALYSIS|$(dacapo_args pmd) $RUNPY_OPTS $DX" \
            "luindex|ANALYSIS|$(dacapo_args luindex) $RUNPY_OPTS $DX"; do
    IFS='|' read -r name binding args <<< "$spec"
    # shellcheck disable=SC2086
    run_cli "$FRESH" "c-$name" -pta=ucfs -ucfsbinding=$binding -ucfscompare -ucfspt $args; rcu=$?
    # shellcheck disable=SC2086
    run_cli "$FRESH" "ci-$name" -pta=insens -ptsall $args; rci=$?
    if [ $rcu -ne 0 ] || [ $rci -ne 0 ]; then
        fail "$name: exit -pta=ucfs -ucfscompare $rcu, -pta=insens $rci (see $OUT/run-c-$name/out.txt)"
        continue
    fi
    check_compare "$OUT/run-c-$name" "$OUT/run-ci-$name" "$binding" > "$LOGS/S3-$name.txt" 2>&1; rc=$?
    grep -v '^PASS' "$LOGS/S3-$name.txt" | sed "s/^/  [$name] /"
    [ $rc -eq 0 ] && pass "$name ($binding): metrics.tsv, pairs.tsv and #UCFS-cmp- lines" || fail "$name: see $LOGS/S3-$name.txt"
    andersen_check "$OUT/run-c-$name/sootOutput/ucfs" > "$LOGS/S3-andersen-$name.txt" 2>&1 \
        && pass "$name: independent Andersen fixpoint of graph.dot = pts.tsv" || fail "$name: AndersenCheck"
done

run_cli "$FRESH" "cerr" -pta=insens -ucfscompare -apppath "$EXAMPLE_JAR" -mainclass Main -se; rc=$?
[ $rc -ne 0 ] && pass "-ucfscompare with -pta=insens: exit $rc" || fail "-ucfscompare with -pta=insens: exit 0"

tree_clean
finish S3_compare
