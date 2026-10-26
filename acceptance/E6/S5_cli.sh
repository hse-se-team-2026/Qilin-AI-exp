#!/usr/bin/env bash
# E6-S5 acceptance: the CLI option -cflidr=<grammar> (with -cflidrmode=ERASED|BALANCED|CS, default CS)
# runs cfl-idr-with-gll in process after the analysis on the IDR export of its PAG, prints the
# #CFLIDR- lines and dumps <outdir>/cflidr (docs/ai/tickets/E6-S5.md; plan E6.md D9).
#  1. `gradle clean build` green, no regression (qilin.pta >= MIN_PTA tests, <= 11 skipped, 0 failed);
#     fat jar;
#  2. without the option: no #CFLIDR- line, no <outdir>/cflidr, no class of org.cfl_idr_with_gll or
#     qilin.ucfs.idr loaded (-Xlog:class+load); with it: org.cfl_idr_with_gll.ApproximationKt and
#     org.ucfs.parser.Gll loaded; a wrong grammar (-cflidr=bogus) and -cflidrmode without -cflidr end
#     with a non-zero exit code;
#  3. each of the lines #CFLIDR-mode, -grammar, -vertices, -edges, -fields, -sites, -under-pairs,
#     -over-pairs, -pt-under, -pt-over once (with parityD/on-demand also -ondemand-pairs, -pt-ondemand);
#     dump: graph.dot, vertices.tsv (id, layer, label, node; ids 0..n-1), under.tsv, over.tsv
#     (vertex id pairs), pts-under.tsv, pts-over.tsv (variable, object as node strings); line counts =
#     the printed numbers; pts-over.tsv = the pairs of over.tsv from an object source vertex (OBJ for
#     ERASED/BALANCED, START for CS) to a variable answer vertex (F for ERASED/BALANCED, END or F_IN for
#     CS), mapped through vertices.tsv by this script;
#  4. upstream cross-check: cfl-idr-with-gll's own CLI (the root build of the pinned commit in
#     .cflidr/src, Kotlin 1.9.20, libs/solver-new.jar = UCFS PR #50, unchanged) on graph.dot prints
#     "Under approximation paths: <#CFLIDR-under-pairs>" and the over-approximation pairs = over.tsv,
#     for the hand program in the three modes and with parityD, and three qilin.microben programs (CS;
#     field.InstanceLoad with se, natives.PrivilegedActions2, context.cfa.CFA2k). Not example01: it runs the
#     JDK with bodies, and cfl-idr's all-pairs run on that graph did not finish in 300 s (planner);
#  5. facts of acceptance/E6/prog/e6prog/CsFacts.java (javac -g --release 8; run with the JunitTests
#     options -singleentry -pae -pe -mh -lcs): in CS, F1 x -> A and not B, y -> B and not A; F2 f -> C;
#     F3 r -> D; F4 e1 -> E and not F, e2 -> F and not E; F5 m -> K; in ERASED x -> A and B, e1 -> E
#     and F (context-insensitive); in BALANCED (cfl-idr's fully balanced semantics) f has no C and r no D
#     (what partial balance and the erasure add).
# Usage: bash acceptance/E6/S5_cli.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
need_cflidr
MIN_PTA=118
MB="qilin.microben.core"

clean_build
rc=$?
echo "gradle clean build exit code: $rc (log: $LOGS/build.log)"
[ $rc -eq 0 ] && pass "clean build" || fail "clean build exit $rc"
check_totals "$MIN_PTA" 20
FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S5_cli; }

PROG="$OUT/prog-classes"
safe_reset_dir "$PROG"
"$JAVA_HOME/bin/javac" -g --release 8 -d "$PROG" acceptance/E6/prog/e6prog/CsFacts.java \
    && pass "hand program compiled" || fail "javac CsFacts"

# run_app <name> <apppath> <mainclass> <qilin args...> -> $OUT/run-<name>/{out.txt,rc,classload.txt}
run_app() {
    local name="$1" app="$2" main="$3" dir rc
    shift 3
    dir="$OUT/run-$name"
    safe_reset_dir "$dir"
    (cd "$dir" && timeout 600 "$JAVA" -Xmx8g -Xlog:class+load=info:file=classload.txt -jar "$FRESH" -pta=insens \
        -apppath "$app" -mainclass "$main" -jre="$JRE_DIR" "$@" > out.txt 2>&1)
    rc=$?
    echo "$rc" > "$dir/rc"
    return $rc
}
JOPTS=(-singleentry -pae -pe -mh -lcs)

# --- 2. option off / on, bad values ----------------------------------------------------------------
run_app off "$PROG" e6prog.CsFacts "${JOPTS[@]}"
rc=$?
D="$OUT/run-off"
[ $rc -eq 0 ] && pass "run without -cflidr" || fail "run without -cflidr exit $rc"
grep -q '^#CFLIDR-' "$D/out.txt" && fail "#CFLIDR- lines without the option" || pass "no #CFLIDR- line without the option"
[ -e "$D/sootOutput/cflidr" ] && fail "cflidr dump without the option" || pass "no cflidr dump without the option"
if grep -qE '\] (org\.cfl_idr_with_gll\.|qilin\.ucfs\.idr\.)' "$D/classload.txt"; then
    fail "cfl-idr or qilin.ucfs.idr classes loaded without the option"
else
    pass "no class of org.cfl_idr_with_gll / qilin.ucfs.idr loaded without the option"
fi
run_app bogus "$PROG" e6prog.CsFacts "${JOPTS[@]}" -cflidr=bogus
[ $? -ne 0 ] && pass "-cflidr=bogus fails" || fail "-cflidr=bogus exits 0"
run_app modeonly "$PROG" e6prog.CsFacts "${JOPTS[@]}" -cflidrmode=CS
[ $? -ne 0 ] && pass "-cflidrmode without -cflidr fails" || fail "-cflidrmode without -cflidr exits 0"

# --- upstream cfl-idr CLI (root build of the pinned commit, solver-new.jar) -------------------------
UP="$ROOT/.cflidr/src/build/libs/cfl-idr-with-gll-all.jar"
(cd "$ROOT/.cflidr/src" && git diff --quiet HEAD -- src libs build.gradle.kts settings.gradle.kts \
    && bash ./gradlew --console=plain -q shadowJar -x test) > "$LOGS/upstream-jar.log" 2>&1
[ -f "$UP" ] && pass "upstream cfl-idr CLI jar built from .cflidr/src @ $(git -C .cflidr/src rev-parse --short HEAD)" \
    || fail "upstream cfl-idr jar (log: $LOGS/upstream-jar.log)"

# check_run <name> <grammar> <mode>: sections 3 and 4 for one run
check_run() {
    local name="$1" grammar="$2" mode="$3" d="$OUT/run-$1"
    [ "$(cat "$d/rc")" = 0 ] && pass "$name: exit 0" || { fail "$name: exit $(cat "$d/rc")"; return; }
    class_loaded "$d/classload.txt" org.cfl_idr_with_gll.ApproximationKt && class_loaded "$d/classload.txt" org.ucfs.parser.Gll \
        && pass "$name: cfl-idr and UCFS GLL loaded" || fail "$name: ApproximationKt or Gll not loaded"
    python3 - "$d" "$grammar" "$mode" <<'PY'
import os, sys
d, grammar, mode = sys.argv[1:4]
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + os.path.basename(d) + ": " + msg)
    ok &= bool(c)
lines = [l.rstrip("\n") for l in open(os.path.join(d, "out.txt"), errors="replace") if l.startswith("#CFLIDR-")]
kv = {}
for l in lines:
    k, _, v = l.partition(":")
    kv.setdefault(k[1:], []).append(v.strip())
keys = ["CFLIDR-mode", "CFLIDR-grammar", "CFLIDR-vertices", "CFLIDR-edges", "CFLIDR-fields", "CFLIDR-sites",
        "CFLIDR-under-pairs", "CFLIDR-over-pairs", "CFLIDR-pt-under", "CFLIDR-pt-over"]
od = grammar in ("parityD", "on-demand")
if od:
    keys += ["CFLIDR-ondemand-pairs", "CFLIDR-pt-ondemand"]
check(all(len(kv.get(k, [])) == 1 for k in keys), "each of %d #CFLIDR- lines once" % len(keys))
if not ok:
    sys.exit(1)
v = {k: kv[k][0] for k in keys}
check(v["CFLIDR-mode"] == mode and v["CFLIDR-grammar"] == grammar, "mode %s grammar %s" % (mode, grammar))
dump = os.path.join(d, "sootOutput", "cflidr")
need = ["graph.dot", "vertices.tsv", "under.tsv", "over.tsv", "pts-under.tsv", "pts-over.tsv"] + (["ondemand.tsv"] if od else [])
check(all(os.path.isfile(os.path.join(dump, f)) for f in need), "dump files " + " ".join(need))
if not ok:
    sys.exit(1)
read = lambda f: [l.rstrip("\n") for l in open(os.path.join(dump, f))]
verts = [l.split("\t") for l in read("vertices.tsv")]
check([int(x[0]) for x in verts] == list(range(len(verts))) and len(verts) == int(v["CFLIDR-vertices"]),
      "vertices.tsv ids 0..%d" % (len(verts) - 1))
edges = [l for l in read("graph.dot") if "->" in l]
check(len(edges) == int(v["CFLIDR-edges"]), "graph.dot has #CFLIDR-edges edges")
under = {tuple(map(int, l.split("\t"))) for l in read("under.tsv")}
over = {tuple(map(int, l.split("\t"))) for l in read("over.tsv")}
check(len(under) == int(v["CFLIDR-under-pairs"]) and len(over) == int(v["CFLIDR-over-pairs"]), "under.tsv/over.tsv sizes")
src_layers = {"START"} if mode == "CS" else {"OBJ"}
dst_layers = {"END", "F_IN"} if mode == "CS" else {"F"}
nodes = {int(x[0]): (x[1], x[3]) for x in verts}
def pts(pairs):
    return {nodes[b][1] + "\t" + nodes[a][1] for a, b in pairs
            if nodes[a][0] in src_layers and nodes[b][0] in dst_layers}
check(pts(over) == set(read("pts-over.tsv")), "pts-over.tsv = over.tsv from %s to %s" % (src_layers, dst_layers))
check(pts(under) == set(read("pts-under.tsv")), "pts-under.tsv = under.tsv mapped")
check(len(read("pts-over.tsv")) == int(v["CFLIDR-pt-over"]), "#CFLIDR-pt-over = lines of pts-over.tsv")
check(under <= over, "under.tsv within over.tsv")
open(os.path.join(d, "kv.tsv"), "w").write("".join("%s\t%s\n" % (k, v[k]) for k in keys))
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || FAILS=$((FAILS + 1))
    if [ -f "$UP" ] && [ -f "$d/sootOutput/cflidr/graph.dot" ]; then
        local u="$d/upstream"
        safe_reset_dir "$u"
        timeout 600 "$JAVA" -Xmx8g -jar "$UP" -o "$u" "$d/sootOutput/cflidr/graph.dot" "$grammar" > "$u/stdout.txt" 2>&1
        python3 - "$d" "$u/graph.out" "$grammar" <<'PY'
import os, sys, re
d, out, grammar = sys.argv[1:4]
name = os.path.basename(d)
if not os.path.isfile(out):
    print("FAIL: %s: upstream cfl-idr wrote no %s" % (name, out)); sys.exit(1)
t = open(out).read()
kv = dict(l.split("\t") for l in open(os.path.join(d, "kv.tsv")).read().splitlines())
m = re.search(r"Under approximation paths: (\d+)", t)
ok = m and int(m.group(1)) == int(kv["CFLIDR-under-pairs"])
print(("PASS: " if ok else "FAIL: ") + "%s: upstream under count %s = #CFLIDR-under-pairs %s" % (name, m and m.group(1), kv["CFLIDR-under-pairs"]))
sec = t.split("On-Demand paths:")[0] if grammar not in ("parityD", "on-demand") else t.split("On-Demand paths:")[0]
pairs = {tuple(map(int, l.split())) for l in sec.splitlines() if l.startswith("\t")}
over = {tuple(map(int, l.split("\t"))) for l in open(os.path.join(d, "sootOutput", "cflidr", "over.tsv")).read().splitlines()}
if grammar in ("parityD", "on-demand"):
    m2 = re.search(r"Over approximation paths \([^)]*\): (\d+)", t)
    ok2 = m2 and int(m2.group(1)) == len(over)
    print(("PASS: " if ok2 else "FAIL: ") + "%s: upstream over count = over.tsv" % name)
else:
    ok2 = pairs == over
    print(("PASS: " if ok2 else "FAIL: ") + "%s: upstream over pairs = over.tsv (%d, %d)" % (name, len(pairs), len(over)))
sys.exit(0 if ok and ok2 else 1)
PY
        [ $? -eq 0 ] || FAILS=$((FAILS + 1))
    fi
}

# --- 3, 4. runs -----------------------------------------------------------------------------------
for mode in CS ERASED BALANCED; do
    run_app "facts-$mode" "$PROG" e6prog.CsFacts "${JOPTS[@]}" -cflidr=parity "-cflidrmode=$mode"
    check_run "facts-$mode" parity "$mode"
done
run_app facts-CS-parityD "$PROG" e6prog.CsFacts "${JOPTS[@]}" -cflidr=parityD
check_run facts-CS-parityD parityD CS
run_app cfa2k "$MICROBEN_CLASSES" qilin.microben.context.cfa.CFA2k "${JOPTS[@]}" -cflidr=parity
check_run cfa2k parity CS
run_app instload "$MICROBEN_CLASSES" "$MB.field.InstanceLoad" "${JOPTS[@]}" -cflidr=se
check_run instload se CS
run_app priv2 "$MICROBEN_CLASSES" "$MB.natives.PrivilegedActions2" "${JOPTS[@]}" -cflidr=parity
check_run priv2 parity CS

# --- 5. facts of the hand program -----------------------------------------------------------------
python3 - "$OUT" <<'PY'
import os, sys, re
out = sys.argv[1]
ok = True
def pts(mode):
    m = {}
    f = os.path.join(out, "run-facts-" + mode, "sootOutput", "cflidr", "pts-over.tsv")
    for l in open(f).read().splitlines():
        var, obj = l.split("\t")
        mv = re.search(r" (\w+) <e6prog\.CsFacts: void main\(java\.lang\.String\[\]\)>$", var)
        mo = re.search(r"new e6prog\.CsFacts\$(\w+) in method", obj)
        if mv and mo:
            m.setdefault(mv.group(1), set()).add(mo.group(1))
    return m
def fact(mode, var, has=(), hasnot=()):
    global ok
    s = pts(mode).get(var, set())
    c = all(h in s for h in has) and not any(h in s for h in hasnot)
    print(("PASS: " if c else "FAIL: ") + "%s: pts(%s) = %s has %s, not %s" % (mode, var, sorted(s), list(has), list(hasnot)))
    ok &= c
fact("CS", "x", ["A"], ["B"]); fact("CS", "y", ["B"], ["A"])
fact("CS", "f", ["C"]); fact("CS", "r", ["D"])
fact("CS", "e1", ["E"], ["F"]); fact("CS", "e2", ["F"], ["E"])
fact("CS", "m", ["K"])
fact("ERASED", "x", ["A", "B"]); fact("ERASED", "e1", ["E", "F"])
fact("BALANCED", "f", [], ["C"]); fact("BALANCED", "r", [], ["D"])
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))
tree_clean
finish S5_cli
