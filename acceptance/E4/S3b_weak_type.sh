#!/usr/bin/env bash
# E4-S3b acceptance: the reference fixpoint of -ucfscompare (qilin.pta.ucfs.ReferenceFixpoint) tests
# a cast with the same type object as Qilin's solver (docs/ai/tickets/E4-S3b.md). Hand program
# acceptance/E4/prog/e4prog/WeakCastProg.java (javac --release 8), with the options of the benchmark
# runs (lib.sh RUNPY_OPTS, JDK bodies excluded), both bindings. Oracles, none of them the code under test:
#  1. facts of Soot's typing (acceptance/E4/WeakTypeProbe.java, -pta=insens; reads Soot and the PAG,
#     not qilin.pta.ucfs): every cast node of twoArrays has a type named java.lang.Object that is a
#     soot.jimple.toolkits.typing.fast.WeakObjectType and not Scene.getObjectType() (at least one such
#     node); the control nodes - the return of oneArray and the field canonical - have Scene's Object;
#  2. facts of Spark, run I = -pta=insens -ptsall (another JVM): each array made in twoArrays is in
#     the set of some variable, the cast nodes of twoArrays are empty, no array of twoArrays is in
#     weak; the array made in oneArray is in canonical;
#  3. run U = -pta=ucfs -ucfsbinding=<B> -ucfscompare -ucfspt: the lines #UCFS-cmp-<class> (8 classes),
#     -spark-pairs, -ucfs-pairs, each once, = the counts of pairs.tsv; pairs with U=1 = pts.tsv = the
#     independent Andersen fixpoint of graph.dot (AndersenCheck.java); pairs with S=1 = the CI pairs
#     of I's dump (a count); UNEXPLAINED = 0 and MISSING = 0; #UCFS-cmp-last-step-pairs = the CI
#     pairs of I's dump (the reference with all filters gives Spark's answer, E4.md D5 (b));
#  4. classes from the facts above: every pair (v, o) with U=1, S=0 and o an array of twoArrays is
#     R2 (no declared type removes it, the cast does), there is one on every cast node of twoArrays and
#     one on weak; the pair (canonical, the array of oneArray) is SAME.
# Usage: bash acceptance/E4/S3b_weak_type.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S3b_weak_type; }
PROG="$OUT/prog-weak-classes"
safe_reset_dir "$PROG"
"$JAVA_HOME/bin/javac" --release 8 -d "$PROG" acceptance/E4/prog/e4prog/WeakCastProg.java \
    && pass "hand program WeakCastProg compiled" || fail "javac WeakCastProg"
ARGS="-apppath $PROG -mainclass e4prog.WeakCastProg $RUNPY_OPTS -exclude=$JDK_EXCLUDE"

# 1. Soot's types of the program's variables
dir="$OUT/run-weak-probe"
safe_reset_dir "$dir"
# shellcheck disable=SC2086
(cd "$dir" && timeout 900 "$JAVA" -Xmx8g -cp "$FRESH" "$ROOT/acceptance/E4/WeakTypeProbe.java" e4prog.WeakCastProg \
    -pta=insens -jre="$JRE_DIR" $ARGS > out.txt 2>&1)
rc=$?
grep '^WEAKTYPE' "$dir/out.txt" > "$LOGS/S3b-weaktype.txt"
python3 - "$LOGS/S3b-weaktype.txt" > "$LOGS/S3b-probe.txt" 2>&1 <<'PY'
import re, sys
TWO = r"<e4prog\.WeakCastProg: java\.lang\.Object twoArrays\(java\.lang\.Object,int\)>"
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
bad = []
casts = [r for r in rows if r[0] == "WEAKTYPE cast" and re.search(TWO + r"$", r[1])]
if casts and all(r[2] == "soot.jimple.toolkits.typing.fast.WeakObjectType" and r[3] == "other" for r in casts):
    print("PASS: %d cast node(s) of twoArrays, each with a WeakObjectType that is not Scene's Object" % len(casts))
else:
    bad.append(1); print("FAIL: cast nodes of twoArrays: %s" % casts)
ctl = {"return of oneArray": r"^LocalVarNode \d+ Parm RETURN to <e4prog\.WeakCastProg: java\.lang\.Object oneArray\(int\)> ",
       "field canonical": r"^GlobalVarNode \d+ <e4prog\.WeakCastProg: java\.lang\.Object canonical>$"}
for name, pat in ctl.items():
    rs = [r for r in rows if r[0] == "WEAKTYPE var" and re.search(pat, r[1])]
    if rs and all(r[3] == "scene" for r in rs):
        print("PASS: %s has Scene's Object" % name)
    else:
        bad.append(1); print("FAIL: %s: %s" % (name, rs))
sys.exit(1 if bad else 0)
PY
prc=$?
sed 's/^/  [probe] /' "$LOGS/S3b-probe.txt"
[ $rc -eq 0 ] && [ $prc -eq 0 ] && pass "Soot's types: WeakObjectType casts in twoArrays, Scene's Object in the control" \
    || fail "WeakTypeProbe (exit $rc, see $dir/out.txt and $LOGS/S3b-probe.txt)"

check_weak() { # <U dir> <I dir> <binding>
    python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
u, i, binding = sys.argv[1:4]
bad = []
def ok(m): print("PASS: " + m)
def ko(m): print("FAIL: " + m); bad.append(m)
CLASSES = ["SAME", "R3", "R4b", "R1", "R2", "R5", "UNEXPLAINED", "MISSING"]
M = r"<e4prog\.WeakCastProg: "
TWO = M + r"java\.lang\.Object twoArrays\(java\.lang\.Object,int\)>"
ONE = M + r"java\.lang\.Object oneArray\(int\)>"
CAST = r"^LocalVarNode \d+ \(java\.lang\.Object\) \$\S+ " + TWO + r"$"
WEAK = r"^GlobalVarNode \d+ " + M + r"java\.lang\.Object weak>$"
CANON = r"^GlobalVarNode \d+ " + M + r"java\.lang\.Object canonical>$"
ARR_TWO = r"^AllocNode \d+ newarray \((char|java\.lang\.Object)\)\[\S+\] in method " + TWO + r"$"
ARR_ONE = r"^AllocNode \d+ newarray \(char\)\[\S+\] in method " + ONE + r"$"
# --- 2. Spark (run I, -ptsall): labels by node, CI objects
qp = os.path.join(i, "sootOutput", "pts.txt")
name, base, pts = {}, {}, {}
nspark = 0  # counted as acceptance/E4/S3_compare.sh counts the CI pairs of a -ptsall dump
for l in open(qp):
    m = re.match(r"^\[(\w+)\](.*)$", l.rstrip("\n"))
    if m:
        name[m.group(1)] = m.group(2)
        mo = re.match(r"^ContextAllocNode \d+\((AllocNode \d+ .*), \[.*\]\)$", m.group(2))
        if mo:
            base[m.group(1)] = mo.group(1)
for l in open(qp):
    m = re.match(r"^([LG]\d+) -> \{(.*)\}\s*$", l.rstrip("\n"))
    if m:
        objs = m.group(2).split()
        pts[m.group(1)] = set() if objs == ["empty"] else {base.get(o, o) for o in objs}
        nspark += len(pts[m.group(1)])
def spark_nodes(pat):
    return [n for n in pts if re.search(pat, name.get(n, ""))]
casts = spark_nodes(CAST)
arrs = {o for s in pts.values() for o in s if re.search(ARR_TWO, o)}
if len(arrs) == 2:
    ok("Spark: both arrays of twoArrays are in some variable's set")
else:
    ko("Spark: arrays of twoArrays in the sets: %s" % sorted(arrs))
if casts and all(not pts[n] for n in casts):
    ok("Spark: the %d cast node(s) of twoArrays are empty" % len(casts))
else:
    ko("Spark: cast nodes of twoArrays %s" % [(name[n], sorted(pts[n])) for n in casts])
w, c = spark_nodes(WEAK), spark_nodes(CANON)
if len(w) == 1 and not any(re.search(ARR_TWO, o) for o in pts[w[0]]):
    ok("Spark: no array of twoArrays in weak")
else:
    ko("Spark: weak %s" % [sorted(pts[n]) for n in w])
if len(c) == 1 and any(re.search(ARR_ONE, o) for o in pts[c[0]]):
    ok("Spark: the array of oneArray is in canonical")
else:
    ko("Spark: canonical %s" % [sorted(pts[n]) for n in c])
# --- 3. run U
def printed(d):
    out = {}
    for l in open(os.path.join(d, "out.txt"), errors="replace"):
        m = re.match(r"^(#[^:]+:)\s*(\S+)\s*$", l.rstrip("\n"))
        if m:
            out.setdefault(m.group(1), []).append(m.group(2))
    return out
pu = printed(u)
def one(k):
    v = pu.get(k, [])
    return v[0] if len(v) == 1 else None
dump = os.path.join(u, "sootOutput", "ucfs")
node = {}
for l in open(os.path.join(dump, "vertices.tsv")):
    vid, label, sname = l.rstrip("\n").split("\t", 2)
    node[label] = sname
upts = set(tuple(l.rstrip("\n").split("\t")) for l in open(os.path.join(dump, "pts.tsv")) if l.strip())
cnt = {k: 0 for k in CLASSES}
rows, uset = [], set()
s1 = 0
for l in open(os.path.join(u, "sootOutput", "ucfs-compare", "pairs.tsv")):
    f = l.rstrip("\n").split("\t")
    if len(f) != 6 or f[5] not in CLASSES or f[0] not in node or f[1] not in node:
        ko("bad pairs.tsv line: %r" % l); continue
    rows.append(f)
    cnt[f[5]] += 1
    s1 += f[2] == "1"
    if f[3] == "1":
        uset.add((f[0], f[1]))
for k, v in [("#UCFS-cmp-%s:" % x, str(cnt[x])) for x in CLASSES] + \
        [("#UCFS-cmp-spark-pairs:", str(s1)), ("#UCFS-cmp-ucfs-pairs:", str(len(uset))), ("#UCFS-cmp-binding:", binding)]:
    (ok if one(k) == v else ko)("%s printed %s, pairs.tsv %s" % (k, pu.get(k), v))
(ok if uset == upts else ko)("pairs with U=1 (%d) = pts.tsv (%d)" % (len(uset), len(upts)))
(ok if s1 == nspark and nspark > 0 else ko)("pairs with S=1 %d = CI pairs of -pta=insens -ptsall %d" % (s1, nspark))
for k in ["UNEXPLAINED", "MISSING"]:
    (ok if cnt[k] == 0 else ko)("%s = %d" % (k, cnt[k]))
last = one("#UCFS-cmp-last-step-pairs:")
(ok if last == str(nspark) else ko)("#UCFS-cmp-last-step-pairs %s = CI pairs of -pta=insens -ptsall %d" % (last, nspark))
# --- 4. classes of the program's pairs
extra = [f for f in rows if f[3] == "1" and f[2] == "0" and re.search(ARR_TWO, node[f[1]])]
if extra and all(f[5] == "R2" for f in extra):
    ok("%d pair(s) of UCFS, not Spark, with an array of twoArrays: all R2" % len(extra))
else:
    ko("pairs with an array of twoArrays, U=1 S=0: %s" % [(node[f[0]], node[f[1]], f[5]) for f in extra][:6])
ucasts = [lab for lab, s in node.items() if re.search(CAST, s)]
if ucasts and all(any(f[0] == lab for f in extra) for lab in ucasts):
    ok("each of the %d cast node(s) of twoArrays has such a pair" % len(ucasts))
else:
    ko("cast nodes of twoArrays %s without an R2 pair" % [node[lab] for lab in ucasts])
(ok if any(re.search(WEAK, node[f[0]]) for f in extra) else ko)("weak has such a pair")
ctl = [f for f in rows if re.search(CANON, node[f[0]]) and re.search(ARR_ONE, node[f[1]])]
(ok if len(ctl) == 1 and ctl[0][2:] == ["1", "1", "1", "SAME"] else ko)("control (canonical, array of oneArray): %s" % [f[2:] for f in ctl])
print("WEAK %s %s last-step-pairs=%s spark-ptsall=%d" % (binding, " ".join("%s=%d" % (k, cnt[k]) for k in CLASSES), last, nspark))
print("RESULT-PY: " + ("FAIL" if bad else "PASS"))
sys.exit(1 if bad else 0)
PY
}

for binding in ANALYSIS CALL_GRAPH; do
    name="weak-$binding"
    # shellcheck disable=SC2086
    run_cli "$FRESH" "c-$name" -pta=ucfs -ucfsbinding=$binding -ucfscompare -ucfspt $ARGS; rcu=$?
    # shellcheck disable=SC2086
    run_cli "$FRESH" "ci-$name" -pta=insens -ptsall $ARGS; rci=$?
    if [ $rcu -ne 0 ] || [ $rci -ne 0 ]; then
        fail "$name: exit -pta=ucfs -ucfscompare $rcu, -pta=insens $rci (see $OUT/run-c-$name/out.txt)"
        continue
    fi
    check_weak "$OUT/run-c-$name" "$OUT/run-ci-$name" "$binding" > "$LOGS/S3b-$name.txt" 2>&1; rc=$?
    grep -v '^PASS' "$LOGS/S3b-$name.txt" | sed "s/^/  [$name] /"
    [ $rc -eq 0 ] && pass "$name: Spark facts, pairs.tsv, last-step-pairs = -ptsall, R2 at the WeakObjectType casts" \
        || fail "$name: see $LOGS/S3b-$name.txt"
    andersen_check "$OUT/run-c-$name/sootOutput/ucfs" > "$LOGS/S3b-andersen-$name.txt" 2>&1 \
        && pass "$name: independent Andersen fixpoint of graph.dot = pts.tsv" || fail "$name: AndersenCheck"
done

tree_clean
finish S3b_weak_type
