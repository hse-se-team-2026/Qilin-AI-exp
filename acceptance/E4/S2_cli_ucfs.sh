#!/usr/bin/env bash
# E4-S2 acceptance: the CLI analysis -pta=ucfs (qilin.pta.tools.UcfsPTA) with -ucfsbinding, its six
# "#UCFS-import-" lines, -pts on the imported answer and -ucfspt dumping the graph and answer of the
# run itself (docs/ai/tickets/E4-S2.md). For every program, a -pta=ucfs run U and a -pta=insens run I
# with the same other arguments (separate JVMs; only numbers that do not depend on node numbering are
# compared across them, E4.md D7/RS7):
#  a. both exit 0; U prints each of the six #UCFS-import-(binding|pairs|typed-pairs|root-pairs|
#     spark-ms|ucfs-ms) lines once (binding = the -ucfsbinding value), I prints none of them;
#  b. call graph: the lines #Reachable Method (CI), #Call Edge(CI), #Virtual Call Site(Polymorphic)
#     of U equal those of I (the call graph is Spark's by construction); #May Fail Cast (Total) of
#     U >= that of I (the UCFS answer holds Spark's);
#  c. U loads qilin.pta.tools.UcfsPTA and org.ucfs.parser.Gll (JVM class-load log); I loads neither
#     qilin.ucfs.UcfsPointsTo nor Gll (UcfsPTA itself may be loaded by the verifier of driver code);
#  d. oracle: acceptance/E4/AndersenCheck.java (independent Andersen fixpoint of graph.dot) = pts.tsv
#     of U's -ucfspt dump; the dump is the run's own graph: #UCFS-pt-pairs = #UCFS-import-pairs +
#     #UCFS-import-root-pairs, the ROOT pairs of pts.tsv = #UCFS-import-root-pairs (>= 1);
#  e. Qilin's -pts dump of U (sootOutput/pts.txt) = pts.tsv without ROOT on every variable of pts.txt;
#  f. binding: in the CALL_GRAPH dump no "new" edge goes from a non-ROOT object into a this vertex and
#     some "assign" edge does; the ANALYSIS dump of the same program has such "new" edges;
#  g. -ucfsbinding without -pta=ucfs and -ucfsbinding=FOO exit non-zero.
# Programs: example01; qilin.microben assign.Receiver2This (JunitTests options) in both bindings;
# DaCapo-2006 pmd (both bindings) and luindex, with JDK bodies excluded (E4.md D3).
# Usage: bash acceptance/E4/S2_cli_ucfs.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S2_cli_ucfs; }

check_pair() { # <U dir> <I dir> <binding>
    python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
u, i, binding = sys.argv[1:4]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
def lines(d):
    return [l.rstrip("\n") for l in open(os.path.join(d, "out.txt"), errors="replace")]
def metric(ls, name):
    v = [l[len(name):].strip() for l in ls if l.startswith(name)]
    return v
lu, li = lines(u), lines(i)
keys = ["binding", "pairs", "typed-pairs", "root-pairs", "spark-ms", "ucfs-ms"]
imp = {}
for k in keys:
    v = metric(lu, "#UCFS-import-%s:" % k)
    if len(v) == 1:
        imp[k] = v[0]
    else:
        ko("U: line #UCFS-import-%s: printed %d times" % (k, len(v)))
if len(imp) == 6:
    ok("U prints the six #UCFS-import- lines once each")
if imp.get("binding") == binding:
    ok("#UCFS-import-binding: " + binding)
else:
    ko("#UCFS-import-binding: %s, expected %s" % (imp.get("binding"), binding))
if any(l.startswith("#UCFS-import-") for l in li):
    ko("I (-pta=insens) prints #UCFS-import- lines")
else:
    ok("I (-pta=insens) prints no #UCFS-import- line")
for name in ["#Reachable Method (CI):", "#Call Edge(CI):", "#Virtual Call Site(Polymorphic):"]:
    a, b = metric(lu, name), metric(li, name)
    if len(a) == 1 and a == b:
        ok("%s %s in U and I" % (name, a[0]))
    else:
        ko("%s U=%s I=%s" % (name, a, b))
a, b = metric(lu, "#May Fail Cast (Total):"), metric(li, "#May Fail Cast (Total):")
if len(a) == 1 and len(b) == 1 and int(a[0]) >= int(b[0]):
    ok("#May Fail Cast (Total): U=%s >= I=%s" % (a[0], b[0]))
else:
    ko("#May Fail Cast (Total): U=%s I=%s" % (a, b))
dump = os.path.join(u, "sootOutput", "ucfs")
vert, node = {}, {}
for l in open(os.path.join(dump, "vertices.tsv")):
    vid, label, s = l.rstrip("\n").split("\t", 2)
    vert[int(vid)] = label
    node[label] = s
roots = {lab for lab, s in node.items() if re.match(r"^AllocNode \d+ ROOT ", s)}
pts = {}
for l in open(os.path.join(dump, "pts.tsv")):
    if l.strip():
        v, o = l.rstrip("\n").split("\t")
        pts.setdefault(v, set()).add(o)
npairs = sum(len(s) for s in pts.values())
nroot = sum(1 for s in pts.values() for o in s if o in roots)
ptline = metric(lu, "#UCFS-pt-pairs:")
try:
    ip, ir, it = int(imp["pairs"]), int(imp["root-pairs"]), int(imp["typed-pairs"])
except (KeyError, ValueError):
    ip = ir = it = -1
if ptline == [str(npairs)] and npairs == ip + ir:
    ok("#UCFS-pt-pairs = %d = |pts.tsv| = import-pairs + root-pairs" % npairs)
else:
    ko("#UCFS-pt-pairs %s, |pts.tsv| %d, import-pairs %d + root-pairs %d" % (ptline, npairs, ip, ir))
if nroot == ir and nroot >= 1:
    ok("ROOT pairs of pts.tsv = #UCFS-import-root-pairs = %d" % nroot)
else:
    ko("ROOT pairs of pts.tsv %d, #UCFS-import-root-pairs %d" % (nroot, ir))
if 0 <= it <= ip:
    ok("typed-pairs %d <= pairs %d" % (it, ip))
else:
    ko("typed-pairs %d, pairs %d" % (it, ip))
# Qilin's -pts dump of the run (view UCFS): objects may be printed as context nodes -> CI
qp = os.path.join(u, "sootOutput", "pts.txt")
base = {}
for l in open(qp):
    m = re.match(r"^\[(O\d+)\]ContextAllocNode \d+\(AllocNode (\d+) ", l)
    if m:
        base[m.group(1)] = "O" + m.group(2)
nv = diff = 0
for l in open(qp):
    m = re.match(r"^([LG]\d+) -> \{(.*)\}\s*$", l)
    if not m:
        continue
    nv += 1
    got = set() if m.group(2).strip() == "empty" else {base.get(o, o) for o in m.group(2).split()}
    exp = pts.get(m.group(1), set()) - roots
    if got != exp:
        diff += 1
        if diff <= 3:
            ko("-pts %s = %s, pts.tsv without ROOT = %s" % (m.group(1), sorted(got)[:5], sorted(exp)[:5]))
if nv > 0 and diff == 0:
    ok("-pts (pts.txt) = pts.tsv without ROOT on all %d variables of pts.txt" % nv)
elif nv == 0:
    ko("no variable in pts.txt")
# binding: new edges into this vertices
this = {vid for vid, lab in vert.items() if "Parm THIS_NODE" in node[lab]}
newThis = assignThis = 0
for l in open(os.path.join(dump, "graph.dot")):
    m = re.match(r'^\s*(\d+)\s*->\s*(\d+)\s*\[label\s*=\s*"([^"]*)"\]', l)
    if m and int(m.group(2)) in this:
        if m.group(3) == "new" and vert[int(m.group(1))] not in roots:
            newThis += 1
        elif m.group(3) == "assign":
            assignThis += 1
print("BINDING %s newIntoThis=%d assignIntoThis=%d" % (binding, newThis, assignThis))
if binding == "CALL_GRAPH":
    if newThis == 0 and assignThis > 0:
        ok("CALL_GRAPH dump: no new edge from a non-ROOT object into this, %d assign edges into this" % assignThis)
    else:
        ko("CALL_GRAPH dump: %d new edges into this, %d assign edges into this" % (newThis, assignThis))
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
}

newIntoThis() { python3 - "$1" <<'PY'
import os, re, sys
d = os.path.join(sys.argv[1], "sootOutput", "ucfs")
vert, roots, this = {}, set(), set()
for l in open(os.path.join(d, "vertices.tsv")):
    vid, label, s = l.rstrip("\n").split("\t", 2)
    if re.match(r"^AllocNode \d+ ROOT ", s): roots.add(int(vid))
    if "Parm THIS_NODE" in s: this.add(int(vid))
n = 0
for l in open(os.path.join(d, "graph.dot")):
    m = re.match(r'^\s*(\d+)\s*->\s*(\d+)\s*\[label\s*=\s*"new"\]', l)
    if m and int(m.group(2)) in this and int(m.group(1)) not in roots: n += 1
print(n)
PY
}

MB="qilin.microben.core"
DX="-exclude=$JDK_EXCLUDE"
declare -A INSENS_DONE
for spec in "example01|ANALYSIS|-apppath $EXAMPLE_JAR -mainclass Main -se" \
            "r2t|ANALYSIS|-apppath $MICROBEN_CLASSES -mainclass $MB.assign.Receiver2This $JUNIT_OPTS" \
            "r2t|CALL_GRAPH|-apppath $MICROBEN_CLASSES -mainclass $MB.assign.Receiver2This $JUNIT_OPTS" \
            "pmd|ANALYSIS|$(dacapo_args pmd) $RUNPY_OPTS $DX" \
            "pmd|CALL_GRAPH|$(dacapo_args pmd) $RUNPY_OPTS $DX" \
            "luindex|ANALYSIS|$(dacapo_args luindex) $RUNPY_OPTS $DX"; do
    IFS='|' read -r name binding args <<< "$spec"
    tag="$name-$binding"
    # shellcheck disable=SC2086
    run_cli "$FRESH" "u-$tag" -pta=ucfs -ucfsbinding=$binding -pts -ucfspt $args; rcu=$?
    if [ -z "${INSENS_DONE[$name]:-}" ]; then
        # shellcheck disable=SC2086
        run_cli "$FRESH" "i-$name" -pta=insens $args
        INSENS_DONE[$name]=1
    fi
    rci=$(cat "$OUT/run-i-$name/rc")
    if [ $rcu -ne 0 ] || [ "$rci" -ne 0 ]; then
        fail "$tag: exit -pta=ucfs $rcu, -pta=insens $rci (see $OUT/run-u-$tag/out.txt)"
        continue
    fi
    pass "$tag: -pta=ucfs and -pta=insens exit 0"
    check_pair "$OUT/run-u-$tag" "$OUT/run-i-$name" "$binding" > "$LOGS/S2-$tag.txt" 2>&1; rc=$?
    sed "s/^/  [$tag] /" "$LOGS/S2-$tag.txt"
    [ $rc -eq 0 ] && pass "$tag: lines, call graph, dumps and binding" || fail "$tag: see $LOGS/S2-$tag.txt"
    andersen_check "$OUT/run-u-$tag/sootOutput/ucfs" > "$LOGS/S2-andersen-$tag.txt" 2>&1; rc=$?
    sed "s/^/  [$tag] /" "$LOGS/S2-andersen-$tag.txt"
    [ $rc -eq 0 ] && pass "$tag: independent Andersen fixpoint of graph.dot = pts.tsv" || fail "$tag: AndersenCheck"
    miss=""
    for c in qilin.pta.tools.UcfsPTA org.ucfs.parser.Gll; do
        class_loaded "$OUT/run-u-$tag/classload.txt" "$c" || miss="$miss $c"
    done
    [ -z "$miss" ] && pass "$tag: -pta=ucfs loaded UcfsPTA and Gll" || fail "$tag: -pta=ucfs did not load:$miss"
    loaded=""
    for c in qilin.ucfs.UcfsPointsTo org.ucfs.parser.Gll; do
        class_loaded "$OUT/run-i-$name/classload.txt" "$c" && loaded="$loaded $c"
    done
    [ -s "$OUT/run-i-$name/classload.txt" ] && [ -z "$loaded" ] && pass "$name: -pta=insens loads neither UcfsPointsTo nor Gll" \
        || fail "$name: -pta=insens class-load log empty or loaded:$loaded"
done
for name in r2t pmd; do
    n="$(newIntoThis "$OUT/run-u-$name-ANALYSIS")"
    [ "${n:-0}" -gt 0 ] && pass "$name ANALYSIS dump: $n new edges from objects into this" \
        || fail "$name ANALYSIS dump: no new edge into this"
done

run_cli "$FRESH" "err1" -pta=insens -ucfsbinding=ANALYSIS -apppath "$EXAMPLE_JAR" -mainclass Main -se; rc=$?
[ $rc -ne 0 ] && pass "-ucfsbinding with -pta=insens: exit $rc" || fail "-ucfsbinding with -pta=insens: exit 0"
run_cli "$FRESH" "err2" -pta=ucfs -ucfsbinding=FOO -apppath "$EXAMPLE_JAR" -mainclass Main -se; rc=$?
[ $rc -ne 0 ] && pass "-ucfsbinding=FOO: exit $rc" || fail "-ucfsbinding=FOO: exit 0"

tree_clean
finish S2_cli_ucfs
