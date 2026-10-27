#!/usr/bin/env bash
# E6-S6a acceptance: the probe script scripts/cflidr/e6-probe.sh (docs/ai/tickets/E6-S6a.md; E6.md D10, decision
# of the lead 3-6 after critic-E6 and Codex). Heavy (xalan with -Xmx16g): runs under the machine lock
# (heavy_lock of lib.sh) unless HEAVY_LOCK_HELD=1.
#  1. the script exists (bash -n); `DRY_RUN=1 bash scripts/cflidr/e6-probe.sh x` prints the matrix MATRIX of
#     E6.md D10 (bench:mode:grammar:timeout_s, in this order); with run arguments it prints them with their
#     timeouts (TIMEOUT for a spec without one);
#  2. lock: the script mentions flock and HEAVY_LOCK_HELD; with HEAVY_LOCK=<a lock this check holds> and
#     HEAVY_LOCK_HELD unset it waits (killed by `timeout 20`: exit 124, no output directory); with
#     HEAVY_LOCK_HELD=1 (as below) it runs at once;
#  3. a run of the fat jar of HEAD, EXTRA_OPTS=-pts, on xalan:ERASED:parity xalan:BALANCED:parity: both ok;
#     meta.tsv has the keys of the contract (git-head = HEAD, tree-clean yes, pins, timeout-s, xmx 16g,
#     stack default, extra-opts -pts, heavy-lock, java-version, cpu-model, mem-total-mb, load1-start,
#     load1-end, mem-available-mb-start, command); runs.tsv, values.tsv and evidence.tsv are byte-equal to
#     the ones acceptance/E6/e6raw.py derives from the files packed in raw.tar.xz (sha256 of out.txt and
#     cmd.txt in evidence.tsv = the packed files); every #CFLIDR- line of out.txt is in values.tsv;
#  4. the answer on xalan, by oracles independent of the export: acceptance/E6/IdrDyckCheck.java on the
#     ERASED dump = pts-under.tsv and pts-over.tsv; Spark (-pts, sootOutput/pts.txt of the same run, the
#     application variables Qilin dumps) within the ERASED over-approximation (vertices.tsv labels): missing
#     = 0 (critic MAJOR-2); the BALANCED over-approximation within the ERASED one (pts-over.tsv);
#  5. classification and failure report: xalan:CS:parity:5 -> timeout, timeout_s 5, exit 124/137;
#     STACK=64k on xalan:BALANCED:parity -> sof, exit not 0/124/137, wall < 300 s, error_line
#     "#CFLIDR-error: java.lang.StackOverflowError at <phase>", min(20, depth) frame lines in out.txt;
#     XMX=2g on xalan:CS:parity -> oom, exit not 0/124/137, wall < 600 s, error_line "#CFLIDR-error:
#     java.lang.OutOfMemoryError at <phase>" and last_phase = the phase before <phase> (export input under
#     over ondemand: the time of every finished phase is printed when it ends, critic MAJOR-5);
#  6. the tracked files are unchanged.
# Usage: bash acceptance/E6/S6a_probe_script.sh          (exit 0 = PASS; ~10 min)
source "$(dirname "$0")/lib.sh"
# a missing script fails at once, without waiting for the lock
[ -f "$ROOT/scripts/cflidr/e6-probe.sh" ] || { fail "no scripts/cflidr/e6-probe.sh"; finish S6a_probe_script; }
heavy_lock "$@"
need_submodules
need_ucfs
need_cflidr
P="$ROOT/scripts/cflidr/e6-probe.sh"
MATRIX="xalan:ERASED:parity:600 xalan:BALANCED:parity:600 xalan:BALANCED:se:600 xalan:CS:parity:3600 pmd:ERASED:parity:600 pmd:BALANCED:parity:600 pmd:CS:parity:600 luindex:BALANCED:parity:600 antlr:BALANCED:parity:600"

# --- 1. script, matrix ------------------------------------------------------------------------------
[ -f "$P" ] && bash -n "$P" && pass "scripts/cflidr/e6-probe.sh exists" || { fail "no scripts/cflidr/e6-probe.sh"; finish S6a_probe_script; }
[ "$(DRY_RUN=1 bash "$P" "$OUT/dry" | tr '\n' ' ' | sed 's/ $//')" = "$MATRIX" ] && pass "default matrix = E6.md D10" \
    || fail "default matrix: $(DRY_RUN=1 bash "$P" "$OUT/dry" | tr '\n' ' ')"
[ "$(DRY_RUN=1 TIMEOUT=7 bash "$P" "$OUT/dry" a:B:c a:B:d:9 | tr '\n' ' ')" = "a:B:c:7 a:B:d:9 " ] && pass "run specs with and without a timeout" \
    || fail "DRY_RUN with specs: $(DRY_RUN=1 TIMEOUT=7 bash "$P" "$OUT/dry" a:B:c a:B:d:9 | tr '\n' ' ')"

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S6a_probe_script; }

# --- 2. lock ---------------------------------------------------------------------------------------
grep -q 'flock' "$P" && grep -q 'HEAVY_LOCK_HELD' "$P" && pass "the script takes the machine lock (flock, HEAVY_LOCK_HELD)" \
    || fail "no flock / HEAVY_LOCK_HELD in the script"
TL="$OUT/test.lock"
rm -rf "$OUT/locked"
flock "$TL" sleep 30 &
holder=$!
sleep 1
timeout 20 env -u HEAVY_LOCK_HELD HEAVY_LOCK="$TL" JAR="$FRESH" bash "$P" "$OUT/locked" xalan:ERASED:parity > "$LOGS/locked.log" 2>&1
rc=$?
kill "$holder" 2> /dev/null; wait "$holder" 2> /dev/null
[ $rc -eq 124 ] && [ ! -e "$OUT/locked/runs.tsv" ] && pass "without HEAVY_LOCK_HELD the script waits for a held lock" \
    || fail "held lock: exit $rc, $( [ -e "$OUT/locked/runs.tsv" ] && echo 'ran anyway' || echo 'no run')"

# --- 3, 4. a run on xalan ----------------------------------------------------------------------------
T="$OUT/probe"
rm -rf "$T"
EXTRA_OPTS=-pts JAR="$FRESH" bash "$P" "$T" xalan:ERASED:parity xalan:BALANCED:parity > "$LOGS/probe.log" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e6-probe.sh xalan ERASED, BALANCED: exit 0" || fail "e6-probe.sh exit $rc (log: $LOGS/probe.log)"
RAW="$OUT/probe-raw"
rm -rf "$RAW" "$OUT/probe-derived"
mkdir -p "$RAW" && tar -xJf "$T/raw.tar.xz" -C "$RAW" 2> "$LOGS/raw.log" && pass "raw.tar.xz unpacks" || fail "raw.tar.xz (log: $LOGS/raw.log)"
python3 acceptance/E6/e6raw.py "$RAW" "$OUT/probe-derived" xalan:ERASED:parity xalan:BALANCED:parity
for f in runs.tsv values.tsv evidence.tsv; do
    cmp -s "$T/$f" "$OUT/probe-derived/$f" && pass "$f = derived from raw.tar.xz" || fail "$f differs from the one derived from raw.tar.xz"
done
python3 - "$T" "$RAW" "$(git rev-parse HEAD)" "$(cflidr_prop cflidrCommit)" "$(sed -n 's/^ucfsCommit=//p' gradle.properties | tr -d '\r')" <<'PY'
import hashlib, os, re, sys
t, raw, head, cc, uc = sys.argv[1:6]
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + msg)
    ok &= bool(c)
meta = dict(l.split("\t", 1) for l in open(os.path.join(t, "meta.tsv")).read().strip().split("\n")[1:])
for k in ["command", "git-head", "tree-clean", "jar-sha256", "cflidr-commit", "ucfs-commit", "java-version", "timeout-s",
          "xmx", "stack", "extra-opts", "heavy-lock", "cpu-model", "mem-total-mb", "load1-start", "mem-available-mb-start",
          "load1-end"]:
    check(meta.get(k, "") != "", "meta.tsv has %s" % k)
check(meta.get("git-head") == head and meta.get("tree-clean") == "yes", "meta: git-head = HEAD, tree-clean yes")
check(meta.get("cflidr-commit") == cc and meta.get("ucfs-commit") == uc, "meta: cflidr-commit, ucfs-commit = the pins")
check(meta.get("xmx") == "16g" and meta.get("stack") == "default" and meta.get("extra-opts") == "-pts", "meta: xmx 16g, stack default, extra-opts -pts")
runs = [l.split("\t") for l in open(os.path.join(t, "runs.tsv")).read().strip().split("\n")]
check(runs[0] == ["bench", "mode", "grammar", "timeout_s", "status", "exit", "wall_s", "max_rss_mb", "last_phase"], "runs.tsv header")
st = {(r[0], r[1], r[2]): r for r in runs[1:]}
for k in [("xalan", "ERASED", "parity"), ("xalan", "BALANCED", "parity")]:
    check(st.get(k, [""] * 9)[4] == "ok" and st.get(k, [""] * 9)[3] == "600", "%s ok, timeout_s 600" % ":".join(k))
vals = set(tuple(l.split("\t")) for l in open(os.path.join(t, "values.tsv")).read().strip().split("\n")[1:])
for b, m, g in st:
    d = os.path.join(raw, b, "%s-%s" % (m, g))
    lines = [l for l in open(os.path.join(d, "out.txt"), errors="replace").read().split("\n") if l.startswith("#CFLIDR-") and not l.startswith("#CFLIDR-error")]
    kv = [re.match(r"^#([^:]+): *(.*)$", l) for l in lines]
    miss = [l for l, x in zip(lines, kv) if not x or (b, m, g, x.group(1), x.group(2).split("\t")[0]) not in vals]
    check(lines and not miss, "%s:%s:%s: every #CFLIDR- line of out.txt in values.tsv (%d)" % (b, m, g, len(lines)))
ev = [l.split("\t") for l in open(os.path.join(t, "evidence.tsv")).read().strip().split("\n")[1:]]
for e in ev:
    d = os.path.join(raw, e[0], "%s-%s" % (e[1], e[2]))
    check(e[7] == hashlib.sha256(open(os.path.join(d, "out.txt"), "rb").read()).hexdigest()
          and e[8] == hashlib.sha256(open(os.path.join(d, "cmd.txt"), "rb").read()).hexdigest(), "%s:%s: sha256 of out.txt, cmd.txt" % (e[0], e[1]))
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))
DUMP="$T/xalan/ERASED-parity/sootOutput/cflidr"
if [ -d "$DUMP" ]; then
    "$JAVA" -Xmx1g acceptance/E6/IdrDyckCheck.java "$DUMP" > "$LOGS/dyck.log" 2>&1
    rc=$?
    sed 's/^/  /' "$LOGS/dyck.log"
    [ $rc -eq 0 ] && pass "IdrDyckCheck: the ERASED answer of xalan = independent Dyck reachability" || fail "IdrDyckCheck exit $rc"
else
    fail "no ERASED dump $DUMP"
fi
python3 - "$T/xalan/ERASED-parity/sootOutput" "$T/xalan/BALANCED-parity/sootOutput" <<'PY'
import os, re, sys
er, ba = sys.argv[1:3]
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + msg)
    ok &= bool(c)
# Spark: sootOutput/pts.txt of -pts ("<var label> -> { <obj label> ... }", then "[label]node" lines)
text = open(os.path.join(er, "pts.txt"), errors="replace").read().split("\n")
names = {}
for l in text:
    m = re.match(r"^\[([LGO]\d+)\](.*)$", l)
    if m:
        names[m.group(1)] = m.group(2)
def base_obj(lbl):  # a ContextAllocNode label -> the label of its AllocNode
    m = re.match(r"^ContextAllocNode \d+\(\w+ (\d+)[ ,)]", names.get(lbl, ""))
    return "O" + m.group(1) if m else lbl
spark = set()
for l in text:
    m = re.match(r"^([LG]\d+) -> \{(.*)\}$", l)
    if m and m.group(2).strip() != "empty":
        for o in m.group(2).split():
            spark.add((m.group(1), base_obj(o)))
verts = {}
for l in open(os.path.join(er, "cflidr", "vertices.tsv")).read().strip().split("\n"):
    i, layer, label, node = l.split("\t")
    verts[int(i)] = (layer, label)
erased = set()
for l in open(os.path.join(er, "cflidr", "over.tsv")).read().strip().split("\n"):
    a, b = map(int, l.split("\t"))
    if verts[a][0] == "OBJ" and verts[b][0] == "F":
        erased.add((verts[b][1], verts[a][1]))
miss = sorted(spark - erased)
check(len(spark) > 0, "Spark -pts dump has %d (variable, object) pairs" % len(spark))
check(not miss, "Spark within the ERASED over-approximation on xalan: missing %d %s" % (len(miss), miss[:3]))
# node numbers and identity hashes (MergedNewExpr@...) differ between two JVM runs: compare without them
norm = lambda l: re.sub(r"@[0-9a-f]+\b", "@", re.sub(r"\b(\w*Node) \d+", r"\1", l))
pe, pb = [set(norm(l) for l in open(os.path.join(d, "cflidr", "pts-over.tsv")).read().strip().split("\n")) for d in (er, ba)]
check(pb <= pe, "BALANCED over within ERASED over on xalan, node numbers dropped (%d, %d; missing %s)" % (len(pb), len(pe), sorted(pb - pe)[:2]))
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))

# --- 5. classification and failure report -------------------------------------------------------------
rm -rf "$OUT/to" "$OUT/sof" "$OUT/oom"
JAR="$FRESH" bash "$P" "$OUT/to" xalan:CS:parity:5 > "$LOGS/to.log" 2>&1
STACK=64k JAR="$FRESH" bash "$P" "$OUT/sof" xalan:BALANCED:parity > "$LOGS/sof.log" 2>&1
XMX=2g JAR="$FRESH" bash "$P" "$OUT/oom" xalan:CS:parity > "$LOGS/oom.log" 2>&1
python3 - "$OUT" <<'PY'
import os, re, sys
out = sys.argv[1]
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + msg)
    ok &= bool(c)
def row(d):
    try:
        r = open(os.path.join(out, d, "runs.tsv")).read().strip().split("\n")[1].split("\t")
        e = open(os.path.join(out, d, "evidence.tsv")).read().strip().split("\n")[1].split("\t")
        return r, e
    except (OSError, IndexError):
        return [""] * 9, [""] * 9
r, e = row("to")
check(r[4] == "timeout" and r[3] == "5" and r[5] in ("124", "137"), "xalan:CS:parity:5 -> timeout, timeout_s 5, exit %s" % r[5])
PH = ["export", "input", "under", "over", "ondemand"]
for d, cls, st, limit in (("sof", "StackOverflowError", "sof", 300), ("oom", "OutOfMemoryError", "oom", 600)):
    r, e = row(d)
    m = re.match(r"^#CFLIDR-error: java\.lang\.%s at (\w+)$" % cls, e[5])
    wall = float(r[6] or 1e9)
    check(r[4] == st and r[5] not in ("", "0", "124", "137") and wall < limit and m,
          "%s run -> %s, exit %s, wall %s s < %d, error_line '%s'" % (d, st, r[5], r[6], limit, e[5]))
    if d == "oom" and m:
        ph = m.group(1)
        want = PH[PH.index(ph) - 1] if ph in PH[1:] else None
        check(want is not None and r[8] == want, "oom at %s: last_phase %s = the phase before it" % (ph, r[8]))
    if d == "sof":
        b = os.path.join(out, "sof", "xalan", "BALANCED-parity", "out.txt")
        lines = open(b, errors="replace").read().split("\n") if os.path.isfile(b) else []
        dep = [int(x.split(": ")[1]) for x in lines if x.startswith("#CFLIDR-error-depth: ")]
        n = min(20, dep[0]) if dep else -1
        i = lines.index(e[5]) if e[5] in lines else -1
        check(n > 0 and i >= 0 and all(x.startswith("\tat ") for x in lines[i + 3:i + 3 + n]) and len(lines[i + 3:i + 3 + n]) == n,
              "sof: depth line and %d frame lines in out.txt" % n)
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))
tree_clean
finish S6a_probe_script
