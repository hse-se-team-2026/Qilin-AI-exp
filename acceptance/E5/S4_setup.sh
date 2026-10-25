#!/usr/bin/env bash
# E5-S4 acceptance: host setup scripts/ucfs/e5-vm-setup.sh and the full-run driver scripts/ucfs/e5-full.sh
# (docs/ai/tickets/E5-S4.md), checked on this machine without a VM.
#  1. E5_NO_APT=1 E5_JDK_CACHE=<dir> E5_REPO_URL=<this repository> bash scripts/ucfs/e5-vm-setup.sh <P> <HEAD>
#     exits 0 (P = acceptance/E5/out/setup; E5_JDK_CACHE = ~/.gradle/jdks when it exists, else downloads);
#     the last two lines of stdout are "e5-vm-setup: ready in <P>" and "e5-vm-setup: next: ..." with the
#     e5-full.sh command;
#  2. <P>/setup.tsv: header "key value", keys repo-url commit git-head tree-clean jdk21 jdk21-sha256 jdk11
#     jdk11-sha256 java-version jar jar-sha256 started finished; commit = git-head = HEAD, tree-clean yes; the
#     JDK tarballs are the pinned Temurin 21.0.12.1+1 and 11.0.32.1+1 (sha256 below = the .sha256.txt files of
#     the Adoptium GitHub releases, checked by the planner), <jdk21>/bin/java and <jdk11>/bin/java report these
#     versions; jar-sha256 = sha256 of <jar>; <P>/Qilin-AI-exp is a clean checkout of HEAD;
#  3. Gradle of the setup is isolated and leaves no process behind: <P>/gradle-home/gradle.properties lists both
#     JDK directories in org.gradle.java.installations.paths, turns auto-download and the Gradle daemon off and
#     runs the Kotlin compiler in-process; after the setup no process has <P>/gradle-home on its command line
#     (on the VM, other-java of meta.tsv must be 0, E5-S5);
#  4. the jar is the code of HEAD: every .class entry of <jar> has the content of the same entry of a fat jar
#     built here from HEAD (zip entry sha256; E9 #39: the fat jar is not byte-reproducible);
#  5. E5_OFFLINE=1 with a cache that holds only fake tarballs under the real file names (valid tar.gz files
#     whose bin/java is a script) -> exit 3 and no clone (a tarball is taken by its sha256, not its name);
#     a commit that is not 40 hex digits -> exit 2;
#  6. smoke of the driver in the clone: E5_REPS=1 E5_BENCHES=xalan E5_MINHEAP_BENCHES=xalan
#     E5_PROBE_CG_BENCHES=xalan E5_PROBE_JDK_BENCHES=xalan E5_PROBE_TIMEOUT=120 E5_PROBE_XMX=4g
#     bash scripts/ucfs/e5-full.sh <P>/full (JAVA_HOME = <jdk21>, QILIN_JAR = <jar>) exits 0; full.tsv lists
#     bench minheap probe-cg probe-jdk with exit 0; bench/ has 6 ok rows (rep 0, 1 x 3 runs) whose answer = E4;
#     minheap/minheap.tsv has 3 rows with status ok; probe-cg has 1 ok row (xalan ucfs-CALL_GRAPH) with
#     timeout 120 and xmx 4g in its meta; probe-jdk has the rows insens (ok) and ucfs-ANALYSIS (ok, timeout or
#     oom: with JDK bodies UCFS may not finish in the smoke limits, planner: oom at 4g after 136 s) and
#     jdk-bodies yes; host.txt has the sections
#     "== lscpu", "== nproc", "== uname -a"; raw.tar.xz holds exactly the cmd.txt, out.txt, time.txt, exit, load1
#     files of all run directories (no sootOutput); the clone stays clean;
#  7. tracked files of this repository unchanged.
# Usage: bash acceptance/E5/S4_setup.sh   (exit 0 = PASS; about 15 min with network: clone of the benchmarks
#        submodule, UCFS build, Gradle dependencies into the isolated Gradle home; run it detached, E5.md)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"
JDK21_SHA=ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
JDK11_SHA=5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d
HEAD_SHA="$(git rev-parse HEAD)"
CACHE="$HOME/.gradle/jdks"
[ -d "$CACHE" ] || CACHE=""

P="$OUT/setup"
safe_reset_dir "$P"
start=$(date +%s)
E5_NO_APT=1 E5_JDK_CACHE="$CACHE" E5_REPO_URL="$ROOT" bash scripts/ucfs/e5-vm-setup.sh "$P" "$HEAD_SHA" > "$LOGS/S4-setup.txt" 2>&1
rc=$?
sleep 2
pgrep -af -- "$P/gradle-home" > "$LOGS/S4-leftover.txt" 2>/dev/null
echo "  e5-vm-setup.sh: exit $rc, $(( $(date +%s) - start )) s"
[ $rc -eq 0 ] && pass "e5-vm-setup.sh exit 0" || fail "e5-vm-setup.sh exit $rc (see $LOGS/S4-setup.txt)"

P2="$OUT/setup-offline"
safe_reset_dir "$P2"
mkdir -p "$P2/fake-cache"
for v in "jdk-21.0.12.1+1:OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz" "jdk-11.0.32.1+1:OpenJDK11U-jdk_x64_linux_hotspot_11.0.32.1_1.tar.gz"; do
    mkdir -p "$P2/fake/${v%%:*}/bin"
    printf '#!/bin/sh\necho fake\n' > "$P2/fake/${v%%:*}/bin/java"
    chmod +x "$P2/fake/${v%%:*}/bin/java"
    tar -czf "$P2/fake-cache/${v#*:}" -C "$P2/fake" "${v%%:*}"
done
E5_NO_APT=1 E5_OFFLINE=1 E5_JDK_CACHE="$P2/fake-cache" E5_REPO_URL="$ROOT" bash scripts/ucfs/e5-vm-setup.sh "$P2/p" "$HEAD_SHA" \
    > "$LOGS/S4-offline.txt" 2>&1
rc=$?
[ $rc -eq 3 ] && [ ! -d "$P2/p/Qilin-AI-exp" ] && pass "offline with fake tarballs only: exit 3, no clone" || fail "offline with fake tarballs: exit $rc"
E5_NO_APT=1 bash scripts/ucfs/e5-vm-setup.sh "$P2/q" "HEAD" > "$LOGS/S4-badcommit.txt" 2>&1
rc=$?
[ $rc -eq 2 ] && pass "commit HEAD (not 40 hex): exit 2" || fail "bad commit: exit $rc"

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || fail "fat jar build"

J21="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("jdk21",""))' "$P/setup.tsv" 2>/dev/null)"
JAR="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("jar",""))' "$P/setup.tsv" 2>/dev/null)"
Q="$P/Qilin-AI-exp"
if [ -x "$J21/bin/java" ] && [ -f "$JAR" ] && [ -d "$Q" ]; then
    (cd "$Q" && JAVA_HOME="$J21" QILIN_JAR="$JAR" E5_REPS=1 E5_BENCHES=xalan E5_MINHEAP_BENCHES=xalan \
        E5_PROBE_CG_BENCHES=xalan E5_PROBE_JDK_BENCHES=xalan E5_PROBE_TIMEOUT=120 E5_PROBE_XMX=4g \
        bash scripts/ucfs/e5-full.sh "$P/full") > "$LOGS/S4-full.txt" 2>&1
    rc=$?
    [ $rc -eq 0 ] && pass "e5-full.sh smoke exit 0" || fail "e5-full.sh smoke exit $rc (see $LOGS/S4-full.txt)"
else
    fail "no jdk21/jar/clone from setup.tsv"
fi
J11="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("jdk11",""))' "$P/setup.tsv" 2>/dev/null)"
V21="$("$J21/bin/java" -version 2>&1 | sed -n 2p)"
V11="$("$J11/bin/java" -version 2>&1 | sed -n 2p)"

py - "$P" "$HEAD_SHA" "$JDK21_SHA" "$JDK11_SHA" "$V21" "$V11" "$FRESH" "$E4_RESULTS" "$LOGS/S4-setup.txt" "$LOGS/S4-leftover.txt" \
    > "$LOGS/S4-check.txt" 2>&1 <<'PY'
import hashlib, os, re, subprocess, sys, tarfile, zipfile
import e5lib
P, head, s21, s11, v21, v11, fresh, e4dir, stdout, leftover = sys.argv[1:11]
e4 = e5lib.e4_values(e4dir)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
lines = [l.rstrip("\n") for l in open(stdout, errors="replace") if l.strip()]
(ok if len(lines) >= 2 and lines[-2] == "e5-vm-setup: ready in " + os.path.realpath(P)
 and lines[-1].startswith("e5-vm-setup: next: ") and "scripts/ucfs/e5-full.sh" in lines[-1] else ko)("stdout last lines %s" % lines[-2:])
try:
    with open(os.path.join(P, "setup.tsv")) as f:
        hdr = f.readline().rstrip("\n")
    rows = e5lib.read_tsv(os.path.join(P, "setup.tsv"))
except OSError:
    hdr, rows = "", []
KEYS = "repo-url commit git-head tree-clean jdk21 jdk21-sha256 jdk11 jdk11-sha256 java-version jar jar-sha256 started finished".split()
(ok if hdr == "key\tvalue" and [r["key"] for r in rows] == KEYS else ko)("setup.tsv keys %s" % [r["key"] for r in rows])
m = {r["key"]: r["value"] for r in rows}
(ok if m.get("commit") == head == m.get("git-head") and m.get("tree-clean") == "yes" else ko)("commit = git-head = HEAD, clean")
(ok if m.get("jdk21-sha256") == s21 and m.get("jdk11-sha256") == s11 else ko)("pinned JDK sha256")
(ok if "Temurin-21.0.12.1+1" in v21 and m.get("java-version") == v21 and "Temurin-11.0.32.1+1" in v11 else ko)(
    "JDK versions: %r / %r" % (v21, v11))
jar = m.get("jar", "")
(ok if os.path.isfile(jar) and hashlib.sha256(open(jar, "rb").read()).hexdigest() == m.get("jar-sha256") else ko)("jar-sha256")
q = os.path.join(P, "Qilin-AI-exp")
def git(*a):
    return subprocess.run(["git", "-C", q] + list(a), capture_output=True, text=True).stdout.strip()
(ok if git("rev-parse", "HEAD") == head and git("status", "--porcelain", "--untracked-files=no") == "" else ko)("clone at HEAD, clean")
gp = os.path.join(P, "gradle-home", "gradle.properties")
txt = open(gp).read() if os.path.isfile(gp) else ""
mm = re.search(r"^org\.gradle\.java\.installations\.paths=(.*)$", txt, re.M)
paths = set(x.strip() for x in mm.group(1).split(",")) if mm else set()
(ok if {m.get("jdk21"), m.get("jdk11")} <= paths and re.search(r"^org\.gradle\.java\.installations\.auto-download=false$", txt, re.M)
 and re.search(r"^org\.gradle\.daemon=false$", txt, re.M) and re.search(r"^kotlin\.compiler\.execution\.strategy=in-process$", txt, re.M)
 else ko)("isolated Gradle home with both JDKs, no auto-download, no daemon, Kotlin in-process")
(ok if open(leftover).read().strip() == "" else ko)("no process left with the Gradle home of the setup: %r" % open(leftover).read()[:200])
def classes(p):
    with zipfile.ZipFile(p) as z:
        return {n: hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.endswith(".class")}
try:
    a, b = classes(jar), classes(fresh)
    diff = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
    (ok if a and not diff else ko)("jar classes = fresh build of HEAD (%d entries, %d differ %s)" % (len(a), len(diff), diff[:3]))
except Exception as e:
    ko("jar compare: %r" % e)
F = os.path.join(P, "full")
def tsv(*p):
    try:
        return e5lib.read_tsv(os.path.join(F, *p))
    except OSError:
        return []
ft = tsv("full.tsv")
(ok if [(r["part"], r["exit"]) for r in ft] == [(x, "0") for x in ("bench", "minheap", "probe-cg", "probe-jdk")] else ko)("full.tsv %s" % ft)
br, bv = tsv("bench", "runs.tsv"), tsv("bench", "values.tsv")
(ok if len(br) == 6 and all(r["status"] == "ok" for r in br) else ko)("bench: %d rows %s" % (len(br), sorted({r["status"] for r in br})))
V = {}
for r in bv:
    if not e5lib.is_measure(r["key"]):
        V.setdefault((r["bench"], r["run"], r["rep"]), {})[r["key"]] = r["value"]
(ok if all(V.get((r["bench"], r["run"], r["rep"])) == e5lib.e4_answer(e4, r["bench"], r["run"]) for r in br) and br else ko)("bench answers = E4")
mh = tsv("minheap", "minheap.tsv")
(ok if len(mh) == 3 and all(r["status"] == "ok" for r in mh) else ko)("minheap: %s" % [(r["run"], r["status"], r["minheap_mb"]) for r in mh])
pc = tsv("probe-cg", "runs.tsv")
mc = e5lib.read_meta(os.path.join(F, "probe-cg", "meta.tsv")) if os.path.isfile(os.path.join(F, "probe-cg", "meta.tsv")) else {}
(ok if [(r["bench"], r["run"], r["status"]) for r in pc] == [("xalan", "ucfs-CALL_GRAPH", "ok")] and mc.get("timeout") == "120"
 and mc.get("xmx") == "4g" else ko)("probe-cg %s %s" % ([(r["bench"], r["run"], r["status"]) for r in pc], (mc.get("timeout"), mc.get("xmx"))))
pj = tsv("probe-jdk", "runs.tsv")
mj = e5lib.read_meta(os.path.join(F, "probe-jdk", "meta.tsv")) if os.path.isfile(os.path.join(F, "probe-jdk", "meta.tsv")) else {}
(ok if [(r["run"], r["status"] if r["run"] == "insens" else r["status"] in ("ok", "timeout", "oom")) for r in pj]
 == [("insens", "ok"), ("ucfs-ANALYSIS", True)] and mj.get("jdk-bodies") == "yes" and mj.get("timeout") == "120"
 else ko)("probe-jdk %s" % [(r["run"], r["status"]) for r in pj])
host = open(os.path.join(F, "host.txt"), errors="replace").read() if os.path.isfile(os.path.join(F, "host.txt")) else ""
(ok if all(("== %s\n" % s) in host for s in ("lscpu", "nproc", "uname -a")) else ko)("host.txt sections")
want = set()
for root, dirs, files in os.walk(F):
    if "exit" in files:
        rel = os.path.relpath(root, F)
        for f in ("cmd.txt", "out.txt", "time.txt", "exit", "load1"):
            if f in files:
                want.add(os.path.normpath(os.path.join(rel, f)))
        if "sootOutput" in dirs:
            ko("sootOutput left in %s" % rel)
try:
    with tarfile.open(os.path.join(F, "raw.tar.xz")) as t:
        got = {os.path.normpath(n) for n in t.getnames() if t.getmember(n).isfile()}
    (ok if got == want and want else ko)("raw.tar.xz: %d files, run directories have %d" % (len(got), len(want)))
except Exception as e:
    ko("raw.tar.xz: %r" % e)
(ok if git("status", "--porcelain", "--untracked-files=no") == "" else ko)("clone clean after the smoke")
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S4-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S4
finish S4_setup
