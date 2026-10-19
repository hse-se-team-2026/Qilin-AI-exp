#!/usr/bin/env bash
# E4-S4 acceptance: one step of dispatch over the UCFS answer, UcfsCompare.dispatch and its output
# in -ucfscompare (dispatch.tsv and the #UCFS-cmp-dispatch- lines; docs/ai/tickets/E4-S4.md).
#  1. `gradle clean build` green; qilin.test.ucfs.E4DispatchTest PASSED: on the 43 small programs,
#     both bindings and all views, the new edges and the counts = a reference computed by the test
#     with Qilin's dispatch; in the view SPARK the dispatch reproduces Spark's call graph at the
#     recorded sites; no regression: qilin.pta >= 113 tests, <= 11 skipped, 0 failed;
#  2. hand program acceptance/E4/prog/e4prog/DispatchProg.java (compiled here, javac --release 8),
#     facts from its source: with -ucfsbinding=CALL_GRAPH dispatch.tsv has exactly one row for each of
#     the views UCFS and UCFS_TYPED, caller <e4prog.DispatchProg$A: void foo()>, target
#     <e4prog.DispatchProg$B: void bar()>, and none for SPARK; pairs.tsv has the pair (this of A.foo,
#     the B object of main) with class R3; with ANALYSIS no row and no R3 pair; special invoke, both
#     bindings: pairs.tsv has (parameter `other` of A.viaOther, the C object) in UCFS and not in Spark,
#     and no view has a dispatch.tsv row to <e4prog.DispatchProg$A: void priv()> (C cannot be stored
#     in A: the canStoreType check of CallGraphBuilder.dispatch for special invokes);
#  3. layout on DaCapo-2006 JPC (CALL_GRAPH, JDK bodies excluded) and the hand program: the lines
#     #UCFS-cmp-dispatch-cg-edges, #UCFS-cmp-dispatch-edges-<VIEW>, #UCFS-cmp-dispatch-new-edges-<VIEW>
#     (VIEW = UCFS, UCFS_TYPED, SPARK) once each; dispatch.tsv rows "VIEW<TAB>caller<TAB>site<TAB>target",
#     their number per view = new-edges-<VIEW>; new-edges-SPARK = 0, edges-SPARK = cg-edges; the
#     UCFS_TYPED rows are UCFS rows.
# Usage: bash acceptance/E4/S4_dispatch.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
expect_cases qilin.pta qilin.test.ucfs.E4DispatchTest dispatchAgainstSparkCallGraph
junit_stdout "$(xml_dir_of qilin.pta)" qilin.test.ucfs.E4DispatchTest "E4DispatchTest total" | sed 's/^/  /'
check_totals 113 14

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S4_dispatch; }
PROG="$OUT/prog-classes"
safe_reset_dir "$PROG"
"$JAVA_HOME/bin/javac" --release 8 -d "$PROG" acceptance/E4/prog/e4prog/DispatchProg.java \
    && pass "hand program compiled" || fail "javac DispatchProg"

check_dispatch() { # <U dir> <binding> <hand: yes|no>
    python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
u, binding, hand = sys.argv[1:4]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
VIEWS = ["UCFS", "UCFS_TYPED", "SPARK"]
pr = {}
for l in open(os.path.join(u, "out.txt"), errors="replace"):
    m = re.match(r"^(#UCFS-cmp-dispatch-[^:]+):\s*(\d+)\s*$", l)
    if m:
        pr.setdefault(m.group(1), []).append(int(m.group(2)))
keys = ["#UCFS-cmp-dispatch-cg-edges"] + ["#UCFS-cmp-dispatch-edges-" + v for v in VIEWS] \
    + ["#UCFS-cmp-dispatch-new-edges-" + v for v in VIEWS]
val = {}
for k in keys:
    if len(pr.get(k, [])) == 1:
        val[k] = pr[k][0]
    else:
        ko("%s printed %s" % (k, pr.get(k)))
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(u, "sootOutput", "ucfs-compare", "dispatch.tsv")) if l.strip()]
byview = {v: [] for v in VIEWS}
for r in rows:
    if len(r) != 4 or r[0] not in VIEWS or not r[1].startswith("<") or not r[3].startswith("<"):
        ko("bad dispatch.tsv row %s" % r)
    else:
        byview[r[0]].append(tuple(r[1:]))
if len(val) == len(keys):
    for v in VIEWS:
        if len(byview[v]) == val["#UCFS-cmp-dispatch-new-edges-" + v] and len(set(byview[v])) == len(byview[v]):
            ok("dispatch.tsv rows of %s = new-edges-%s = %d" % (v, v, len(byview[v])))
        else:
            ko("dispatch.tsv rows of %s %d, new-edges-%s %s" % (v, len(byview[v]), v, val["#UCFS-cmp-dispatch-new-edges-" + v]))
    if val["#UCFS-cmp-dispatch-new-edges-SPARK"] == 0 and val["#UCFS-cmp-dispatch-edges-SPARK"] == val["#UCFS-cmp-dispatch-cg-edges"] > 0:
        ok("view SPARK reproduces Spark's call graph at the recorded sites (%d edges)" % val["#UCFS-cmp-dispatch-cg-edges"])
    else:
        ko("view SPARK: new %d, edges %d, cg-edges %d" % (val["#UCFS-cmp-dispatch-new-edges-SPARK"],
            val["#UCFS-cmp-dispatch-edges-SPARK"], val["#UCFS-cmp-dispatch-cg-edges"]))
if set(byview["UCFS_TYPED"]) <= set(byview["UCFS"]):
    ok("UCFS_TYPED rows are UCFS rows")
else:
    ko("a UCFS_TYPED row is not a UCFS row")
if hand == "yes":
    A, B = "<e4prog.DispatchProg$A: void foo()>", "<e4prog.DispatchProg$B: void bar()>"
    exp = 1 if binding == "CALL_GRAPH" else 0
    for v in VIEWS:
        want = exp if v != "SPARK" else 0
        got = byview[v]
        if len(got) == want and all(c == A and t == B for c, s, t in got):
            ok("hand program %s %s: %d new edge(s) %s" % (binding, v, want, "A.foo -> B.bar" if want else ""))
        else:
            ko("hand program %s %s: expected %d edge A.foo -> B.bar, got %s" % (binding, v, want, got))
    node = {}
    for l in open(os.path.join(u, "sootOutput", "ucfs", "vertices.tsv")):
        vid, label, s = l.rstrip("\n").split("\t", 2)
        node[label] = s
    r3 = [f for f in (l.rstrip("\n").split("\t") for l in open(os.path.join(u, "sootOutput", "ucfs-compare", "pairs.tsv")))
          if len(f) == 6 and f[5] == "R3"]
    hit = [f for f in r3 if re.match(r"^LocalVarNode \d+ Parm THIS_NODE to <e4prog\.DispatchProg\$A: void foo\(\)>", node.get(f[0], ""))
           and re.match(r"^AllocNode \d+ new e4prog\.DispatchProg\$B in method <e4prog\.DispatchProg: void main\(java\.lang\.String\[\]\)>", node.get(f[1], ""))]
    if (binding == "CALL_GRAPH" and len(hit) == 1) or (binding == "ANALYSIS" and not r3):
        ok("hand program %s: R3 pair (this of A.foo, B of main) %s" % (binding, "present" if hit else "absent, no R3 pair"))
    else:
        ko("hand program %s: R3 rows %d, (this of A.foo, B) rows %d" % (binding, len(r3), len(hit)))
    other = [f for f in (l.rstrip("\n").split("\t") for l in open(os.path.join(u, "sootOutput", "ucfs-compare", "pairs.tsv")))
             if len(f) == 6 and f[2] == "0" and f[3] == "1"
             and re.match(r"^LocalVarNode \d+ Parm 0 to <e4prog\.DispatchProg\$A: void viaOther\(e4prog\.DispatchProg\$A\)>", node.get(f[0], ""))
             and re.match(r"^AllocNode \d+ new e4prog\.DispatchProg\$C in method ", node.get(f[1], ""))]
    (ok if len(other) == 1 else ko)("hand program %s: (other of A.viaOther, C) in UCFS, not in Spark: %d row(s)" % (binding, len(other)))
    priv = [(v, r) for v in VIEWS for r in byview[v] if r[2] == "<e4prog.DispatchProg$A: void priv()>"]
    (ok if not priv else ko)("hand program %s: special invoke other.priv() over C gives no edge (%s)" % (binding, priv))
print("DISPATCH %s %s" % (binding, " ".join("%s=%s" % (k.replace("#UCFS-cmp-dispatch-", ""), v) for k, v in val.items())))
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
}

for spec in "hand-CG|CALL_GRAPH|yes|-apppath $PROG -mainclass e4prog.DispatchProg -se" \
            "hand-AN|ANALYSIS|yes|-apppath $PROG -mainclass e4prog.DispatchProg -se" \
            "JPC-CG|CALL_GRAPH|no|-apppath $BENCH/applications/JPC/JPCApplication.jar -libpath $BENCH/applications/JPC/ -mainclass org.jpc.j2se.JPCApplication -reflectionlog $BENCH/applications/JPC/JPC-refl.log $RUNPY_OPTS -exclude=$JDK_EXCLUDE"; do
    IFS='|' read -r name binding hand args <<< "$spec"
    # shellcheck disable=SC2086
    run_cli "$FRESH" "d-$name" -pta=ucfs -ucfsbinding=$binding -ucfscompare -ucfspt $args; rc=$?
    if [ $rc -ne 0 ]; then
        fail "$name: -pta=ucfs -ucfscompare exit $rc (see $OUT/run-d-$name/out.txt)"
        continue
    fi
    check_dispatch "$OUT/run-d-$name" "$binding" "$hand" > "$LOGS/S4-$name.txt" 2>&1; rc=$?
    grep -v '^PASS' "$LOGS/S4-$name.txt" | sed "s/^/  [$name] /"
    [ $rc -eq 0 ] && pass "$name ($binding): dispatch lines and dispatch.tsv" || fail "$name: see $LOGS/S4-$name.txt"
done

tree_clean
finish S4_dispatch
