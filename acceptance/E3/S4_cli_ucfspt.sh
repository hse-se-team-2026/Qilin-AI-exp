#!/usr/bin/env bash
# E3-S4 acceptance: the CLI option -ucfspt runs UCFS points-to after the analysis of driver.Main
# and dumps the graph and the answer to <outdir>/ucfs (sootOutput/ucfs by default):
#   graph.dot     UCFS DOT format (start -> N lines = the allocation vertices, quoted labels)
#   vertices.tsv  id <TAB> PTAUtils.getNodeLabel(node) <TAB> node, one line per vertex id
#   fields.tsv    index <TAB> field, one line per field index
#   pts.tsv       var-label <TAB> object-label, one line per pair (CI nodes, labels as Qilin's -pts)
# and prints exactly 5 lines "#UCFS-pt-(vertices|edges|fields|pairs|time-ms): <n>".
# Oracles (none of them the implementation):
#   * Qilin's own dump of the Spark result in the same run (-pts, sootOutput/pts.txt): for every
#     variable in it, Spark's objects are a subset of the UCFS objects (UCFS lacks only filters);
#   * hand facts of docs/example/example01/src/Main.java (comments C1, A1, O1, O2);
#   * acceptance/E3/DotCheck.java: graph.dot read back by UCFS's own DotParser and solved by
#     Gll directly gives exactly pts.tsv; the counts printed equal the dumped files;
#   * without -ucfspt nothing is printed or written and the statistics are those of the run with it.
# Programs: example01 and three qilin.microben programs (fields, arrays with type filtering, calls).
#
# Usage: bash acceptance/E3/S4_cli_ucfspt.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

FRESH="$OUT/qilin-fat.jar"
build_fatjar "$FRESH" clean fatJar -x test
rc=$?
echo "gradle clean fatJar -x test exit code: $rc (log: $LOGS/fatjar.log)"
if [ $rc -ne 0 ] || [ ! -f "$FRESH" ]; then
    fail "clean fatJar -x test (exit $rc)"
    finish S4_cli_ucfspt
fi

# run_app <name> <apppath> <mainclass> <qilin args...> -> $OUT/run-<name>/{out.txt,metrics.txt,rc}
run_app() {
    local name="$1" app="$2" main="$3" dir rc
    shift 3
    dir="$OUT/run-$name"
    safe_reset_dir "$dir"
    (cd "$dir" && timeout 300 "$JAVA" -Xmx2g -jar "$FRESH" -apppath "$app" -mainclass "$main" \
        -jre="$JRE_DIR" "$@" > out.txt 2>&1)
    rc=$?
    echo "$rc" > "$dir/rc"
    grep '^#' "$dir/out.txt" > "$dir/metrics.txt"
    return $rc
}

# compare <run dir> <hand-facts: example01|none> -> python check of the dump against Qilin's pts.txt
compare() {
    python3 - "$1" "$2" <<'PY'
import os, re, sys
d, facts = sys.argv[1], sys.argv[2]
u = os.path.join(d, "sootOutput", "ucfs")
bad = []
def ok(msg): print("PASS: " + msg)
def ko(msg): print("FAIL: " + msg); bad.append(msg)
metrics = {}
for line in open(os.path.join(d, "metrics.txt")):
    m = re.match(r"^#UCFS-pt-([a-z-]+):\s+(\d+)\s*$", line)
    if m:
        metrics[m.group(1)] = int(m.group(2))
keys = ["vertices", "edges", "fields", "pairs", "time-ms"]
if sorted(metrics) == sorted(keys) and sum(1 for l in open(os.path.join(d, "metrics.txt")) if l.startswith("#UCFS-pt-")) == 5:
    ok("exactly the 5 lines #UCFS-pt-{%s}" % ",".join(keys))
else:
    ko("expected the 5 lines #UCFS-pt-{%s}, got %s" % (",".join(keys), metrics))
for f in ["graph.dot", "vertices.tsv", "fields.tsv", "pts.tsv"]:
    if not os.path.isfile(os.path.join(u, f)):
        ko("missing " + f); print("RESULT-PY: FAIL"); sys.exit(1)
vert = {}
for line in open(os.path.join(u, "vertices.tsv")):
    i, label, node = line.rstrip("\n").split("\t", 2)
    vert[label] = node
nfields = sum(1 for _ in open(os.path.join(u, "fields.tsv")))
pairs = [l.rstrip("\n").split("\t") for l in open(os.path.join(u, "pts.tsv")) if l.strip()]
nedges = sum(1 for l in open(os.path.join(u, "graph.dot")) if re.match(r"^\s*\d+\s*->\s*\d+\s*\[label", l))
for k, v in [("vertices", len(vert)), ("fields", nfields), ("pairs", len(pairs)), ("edges", nedges)]:
    if metrics.get(k) == v:
        ok("#UCFS-pt-%s = %d = size of the dump" % (k, v))
    else:
        ko("#UCFS-pt-%s = %s, dump has %d" % (k, metrics.get(k), v))
if len(pairs) == 0:
    ko("UCFS found no pairs")
ucfs = {}
for v, o in pairs:
    if not re.match(r"^[LG]\d+$", v) or not re.match(r"^O\d+$", o) or v not in vert or o not in vert:
        ko("bad pair line %s %s" % (v, o))
    ucfs.setdefault(v, set()).add(o)
# Qilin's own -pts dump (Spark result of the same run): var labels are CI; objects are context
# nodes "[O<n>]ContextAllocNode n(AllocNode <m> ...)": map them to the CI object O<m>
spark, base = {}, {}
qp = os.path.join(d, "sootOutput", "pts.txt")
for line in open(qp):
    m = re.match(r"^\[(O\d+)\]ContextAllocNode \d+\(AllocNode (\d+) ", line)
    if m:
        base[m.group(1)] = "O" + m.group(2)
for line in open(qp):
    m = re.match(r"^([LG]\d+) -> \{(.*)\}\s*$", line)
    if m and m.group(2).strip() != "empty":
        spark[m.group(1)] = set(m.group(2).split())
missing = extra = nvars = 0
for v, objs in spark.items():
    nvars += 1
    ci = {base.get(o, "?" + o) for o in objs}
    lost = ci - ucfs.get(v, set())
    missing += len(lost)
    extra += len(ucfs.get(v, set()) - ci)
    if lost:
        ko("Spark objects of %s not found by UCFS: %s" % (v, sorted(lost)))
if nvars == 0:
    ko("no Spark points-to sets in %s" % qp)
else:
    ok("Spark (Qilin -pts) subset of UCFS on all %d variables of pts.txt (extra UCFS pairs there: %d)" % (nvars, extra))
if facts == "example01":
    # docs/example/example01/src/Main.java: c1 = new C() (C1); a1 = c1.wcreate2(), a2 = c2.wcreate2()
    # (c2 = c1 is a copy that Soot removes, so c2 is no variable)
    # both return the A of B.create (A1); o1, o2 = new Object() (O1, O2); a1.f = o1; a2.f = o2;
    # v1 = a1.f; v2 = a2.f (insens: a1, a2 hold the same A1, so v1, v2 get O1 and O2)
    def var(name):
        r = [l for l, n in vert.items() if re.match(r"^LocalVarNode \d+ %s <Main: void main\(java.lang.String\[\]\)>$" % name, n)]
        return r[0] if len(r) == 1 else None
    def objs_of(name):
        v = var(name)
        return None if v is None else sorted(vert[o].split(" ", 2)[2] for o in ucfs.get(v, set()))
    expect = {
        "c1": ["new C in method <Main: void main(java.lang.String[])>"],
        "a1": ["new A in method <B: A create()>"],
        "a2": ["new A in method <B: A create()>"],
        "o1": ["new java.lang.Object in method <Main: void main(java.lang.String[])>"],
        "v1": ["new java.lang.Object in method <Main: void main(java.lang.String[])>"] * 2,
        "v2": ["new java.lang.Object in method <Main: void main(java.lang.String[])>"] * 2,
    }
    for name, exp in expect.items():
        got = objs_of(name)
        if got == exp:
            ok("example01 %s -> %s" % (name, exp))
        else:
            ko("example01 %s: expected %s, UCFS gives %s" % (name, exp, got))
    o1, o2 = set(ucfs.get(var("o1"), set())), set(ucfs.get(var("o2"), set()))
    if len(o1) == 1 and len(o2) == 1 and o1 != o2 and ucfs.get(var("v1")) == o1 | o2 == ucfs.get(var("v2")):
        ok("example01 v1 and v2 point to exactly the objects of o1 and o2 (field f of the shared A1)")
    else:
        ko("example01: v1/v2 do not hold exactly o1's and o2's objects")
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
}

MB="qilin.microben.core"
for spec in "example01|$EXAMPLE_JAR|Main|example01" \
            "fieldsens1|$MICROBEN_CLASSES|$MB.field.FieldSensitivity1|none" \
            "arrfilter|$MICROBEN_CLASSES|$MB.array.ArrayElemTypeFiltering|none" \
            "receiver|$MICROBEN_CLASSES|$MB.assign.Receiver2This|none"; do
    IFS='|' read -r name app main facts <<< "$spec"
    run_app "pt-$name" "$app" "$main" -pta=insens -se -stats -pts -ucfspt; rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name: '-pta=insens -se -stats -pts -ucfspt' exit $rc (see $OUT/run-pt-$name/out.txt)"
        continue
    fi
    pass "$name: -pta=insens -se -stats -pts -ucfspt exit 0"
    compare "$OUT/run-pt-$name" "$facts" > "$LOGS/S4-compare-$name.txt" 2>&1; rc=$?
    sed "s/^/  [$name] /" "$LOGS/S4-compare-$name.txt"
    [ $rc -eq 0 ] && pass "$name: dump consistent, Spark subset of UCFS${facts:+, facts: $facts}" || fail "$name: dump/oracle check (see $LOGS/S4-compare-$name.txt)"
    "$JAVA" -cp "$FRESH" acceptance/E3/DotCheck.java "$OUT/run-pt-$name/sootOutput/ucfs" > "$LOGS/S4-dotcheck-$name.txt" 2>&1; rc=$?
    sed "s/^/  [$name] /" "$LOGS/S4-dotcheck-$name.txt"
    [ $rc -eq 0 ] && pass "$name: graph.dot read by UCFS DotParser + Gll gives exactly pts.tsv" \
        || fail "$name: DotCheck failed (see $LOGS/S4-dotcheck-$name.txt)"
done

# without the option: no lines, no files, the same statistics
run_app "nopt" "$EXAMPLE_JAR" Main -pta=insens -se -stats -pts; rc=$?
grep -q '^#UCFS-pt-' "$OUT/run-nopt/metrics.txt" && fail "#UCFS-pt- lines printed without -ucfspt" \
    || pass "no #UCFS-pt- lines without -ucfspt"
[ -e "$OUT/run-nopt/sootOutput/ucfs" ] && fail "sootOutput/ucfs written without -ucfspt" || pass "nothing written to sootOutput/ucfs without -ucfspt"
stable() { grep -v '^#UCFS-pt-' "$1"; }
if [ $rc -eq 0 ] && [ -n "$(stable "$OUT/run-nopt/metrics.txt")" ] \
    && [ "$(stable "$OUT/run-nopt/metrics.txt")" = "$(stable "$OUT/run-pt-example01/metrics.txt")" ]; then
    pass "statistics without -ucfspt = with it ($(stable "$OUT/run-nopt/metrics.txt" | wc -l) lines)"
else
    fail "statistics differ with and without -ucfspt (exit $rc)"
fi

# both options together: the E2 seam lines are still exactly 4
run_app "both" "$EXAMPLE_JAR" Main -pta=insens -se -ucfsseam -ucfspt; rc=$?
nseam=$(grep -cE '^#UCFS-seam-(NEW|ASSIGN|LOAD|STORE):[[:space:]]+[0-9]+[[:space:]]*$' "$OUT/run-both/metrics.txt")
npt=$(grep -cE '^#UCFS-pt-[a-z-]+:[[:space:]]+[0-9]+[[:space:]]*$' "$OUT/run-both/metrics.txt")
[ $rc -eq 0 ] && [ "$nseam" -eq 4 ] && [ "$npt" -eq 5 ] && pass "-ucfsseam -ucfspt: 4 seam lines and 5 pt lines" \
    || fail "-ucfsseam -ucfspt: exit $rc, $nseam seam lines, $npt pt lines"

# the UCFS points-to entry point of the CLI is Java code of qilin.pta calling the Kotlin module
callers=$(grep -rlE 'qilin\.ucfs\.UcfsPointsTo|import qilin\.ucfs\.\*;' qilin.pta/src --include='*.java' 2>/dev/null)
[ -n "$callers" ] && pass "production Java code calls qilin.ucfs.UcfsPointsTo: $(echo $callers)" \
    || fail "no Java file under qilin.pta/src uses qilin.ucfs.UcfsPointsTo"

tree_clean
finish S4_cli_ucfspt
