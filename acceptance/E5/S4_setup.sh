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
#     bash scripts/ucfs/e5-full.sh <P>/full (JAVA_HOME = <jdk21>, QILIN_JAR = <jar>) exits 0; its own stdout
#     (not the logs of the parts) is "e5-full: <part> started" / "e5-full: <part> finished exit 0" for bench
#     minheap probe-cg probe-jdk in this order and the last line "e5-full: done in <P>/full"; full.tsv lists the
#     four parts in this order with exit 0; bench/ has 6 ok rows (rep 0, 1 x 3 runs, order of e5lib.run_order)
#     whose answer = E4 and whose cmd.txt = e5lib.expected_cmd(<jdk21>/bin/java, <jar>, 16g, ..., clone);
#     minheap/minheap.tsv has 3 rows with status ok (confirmed); probe-cg has 1 ok row (xalan ucfs-CALL_GRAPH)
#     with timeout 120, xmx 4g and compressed-oops true in its meta; probe-jdk has the rows insens (ok) and
#     ucfs-ANALYSIS (ok, timeout or oom: with JDK bodies UCFS may not finish in the smoke limits, planner: oom
#     at 4g after 136 s) and jdk-bodies yes; host.txt has the sections "== lscpu", "== head -n 3
#     /proc/meminfo", "== uname -a", "== cat /etc/os-release", "== nproc", "== systemd-detect-virt" and, last,
#     "== kernel-oom" (written after the parts: OOM-killer lines of dmesg or journalctl -k, "none" or
#     "unavailable"); <part>/raw.tar.xz of each part holds exactly the files of e5lib.RUN_FILES of the run
#     directories of that part (paths <part>/..., no sootOutput) and is complete when the part's row of
#     full.tsv is written; all run directories of the four parts ran one after the other in the order of the
#     parts and each inside its part's started..finished of full.tsv; the clone stays clean;
#  7. e5-full.sh into a directory that is not empty (the smoke output again; E5_PARTS=bench E5_REPS=1 E5_BENCHES=xalan
#     under timeout 600, so that a driver that does not refuse runs only a minute) -> exit 2, nothing written;
#  8. tracked files of this repository unchanged.
# The calls of the scripts are bounded (setup and smoke 3 h each - generous: on this shared machine under load 35 the
# smoke alone took over 30 min -, second call 600 s), so that a defective driver
# cannot start the full measurement with its -Xmx52g probes on this machine.
# Usage: bash acceptance/E5/S4_setup.sh   (exit 0 = PASS; about 20 min with network: clone of the benchmarks
#        submodule, UCFS build, Gradle dependencies into the isolated Gradle home; run it detached, E5.md)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"
JDK21_SHA=ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
JDK11_SHA=5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d
HEAD_SHA="$(git rev-parse HEAD)"
CACHE="$HOME/.gradle/jdks"
[ -d "$CACHE" ] || CACHE=""

P="$OUT/setup"
safe_reset_dir "$P"
start=$(date +%s)
E5_NO_APT=1 E5_JDK_CACHE="$CACHE" E5_REPO_URL="$ROOT" timeout -k 30 10800 bash scripts/ucfs/e5-vm-setup.sh "$P" "$HEAD_SHA" \
    > "$LOGS/S4-setup.txt" 2>&1
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
    # bounded: a driver that ignored the E5_* limits would otherwise run the full measurement (-Xmx52g probes) here
    (cd "$Q" && JAVA_HOME="$J21" QILIN_JAR="$JAR" E5_REPS=1 E5_BENCHES=xalan E5_MINHEAP_BENCHES=xalan \
        E5_PROBE_CG_BENCHES=xalan E5_PROBE_JDK_BENCHES=xalan E5_PROBE_TIMEOUT=120 E5_PROBE_XMX=4g \
        timeout -k 30 10800 bash scripts/ucfs/e5-full.sh "$P/full") > "$LOGS/S4-full.txt" 2>&1
    rc=$?
    [ $rc -eq 0 ] && pass "e5-full.sh smoke exit 0" || fail "e5-full.sh smoke exit $rc (see $LOGS/S4-full.txt)"
    before="$(cd "$P/full" && find . -type f -printf '%p %s %T@\n' | LC_ALL=C sort | sha256sum)"
    # only the bench part with one benchmark and a time limit: a driver that does not refuse must not start the
    # default minimum-heap searches and the -Xmx52g probes on this machine
    (cd "$Q" && JAVA_HOME="$J21" QILIN_JAR="$JAR" E5_PARTS=bench E5_REPS=1 E5_BENCHES=xalan \
        timeout -k 10 600 bash scripts/ucfs/e5-full.sh "$P/full") > "$LOGS/S4-full-again.txt" 2>&1
    rc=$?
    after="$(cd "$P/full" && find . -type f -printf '%p %s %T@\n' | LC_ALL=C sort | sha256sum)"
    [ $rc -eq 2 ] && [ "$before" = "$after" ] && pass "e5-full.sh into a non-empty directory: exit 2, nothing written" \
        || fail "e5-full.sh into a non-empty directory: exit $rc, files changed: $([ "$before" = "$after" ] && echo no || echo yes)"
else
    fail "no jdk21/jar/clone from setup.tsv"
fi
J11="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("jdk11",""))' "$P/setup.tsv" 2>/dev/null)"
V21="$("$J21/bin/java" -version 2>&1 | sed -n 2p)"
V11="$("$J11/bin/java" -version 2>&1 | sed -n 2p)"

py - "$P" "$HEAD_SHA" "$JDK21_SHA" "$JDK11_SHA" "$V21" "$V11" "$FRESH" "$E4_RESULTS" "$LOGS/S4-setup.txt" "$LOGS/S4-leftover.txt" \
    "$LOGS/S4-full.txt" > "$LOGS/S4-check.txt" 2>&1 <<'PY'
import hashlib, os, re, subprocess, sys, tarfile, zipfile
import e5lib
P, head, s21, s11, v21, v11, fresh, e4dir, stdout, leftover, fullout = sys.argv[1:12]
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
PARTS = ["bench", "minheap", "probe-cg", "probe-jdk"]
def tsv(*p):
    try:
        return e5lib.read_tsv(os.path.join(F, *p))
    except OSError:
        return []
def meta(p):
    f = os.path.join(F, p, "meta.tsv")
    return e5lib.read_meta(f) if os.path.isfile(f) else {}
fl = [l.rstrip("\n") for l in open(fullout, errors="replace") if l.strip()]
want = [x for p in PARTS for x in ("e5-full: %s started" % p, "e5-full: %s finished exit 0" % p)] + \
       ["e5-full: done in " + os.path.realpath(F)]
(ok if [l for l in fl if l.startswith("e5-full: ")] == want and fl[-1:] == want[-1:] else ko)(
    "stdout of e5-full.sh: %s" % [l for l in fl if l.startswith("e5-full: ")][:9])
ft = tsv("full.tsv")
(ok if [(r["part"], r["exit"]) for r in ft] == [(x, "0") for x in PARTS] else ko)("full.tsv %s" % ft)
J = os.path.join(m.get("jdk21", ""), "bin", "java")
bmap = e5lib.bench_map(q)
br, bv = tsv("bench", "runs.tsv"), tsv("bench", "values.tsv")
order = e5lib.run_order(["xalan"], e5lib.RUNS, 1, True, set())
(ok if sorted((int(r["rep"]), r["bench"], r["run"]) for r in br) == sorted(order) and all(r["status"] == "ok" for r in br)
 else ko)("bench: %d rows %s" % (len(br), sorted({r["status"] for r in br})))
V = {}
for r in bv:
    if not e5lib.is_measure(r["key"]):
        V.setdefault((r["bench"], r["run"], r["rep"]), {})[r["key"]] = r["value"]
(ok if all(V.get((r["bench"], r["run"], r["rep"])) == e5lib.e4_answer(e4, r["bench"], r["run"]) for r in br) and br else ko)("bench answers = E4")
cmdbad = [k for k, b, r in order if e5lib.cmd_problem(e5lib.cmd_tokens(os.path.join(F, "bench", b, r, "rep%d" % k)),
          e5lib.expected_cmd(J, jar, "16g", r, b, q, bmap))]
(ok if not cmdbad else ko)("bench cmd.txt = expected_cmd with <jdk21>/bin/java, the jar of the setup, the clone %s" % cmdbad)
mh = tsv("minheap", "minheap.tsv")
(ok if len(mh) == 3 and all(r["status"] == "ok" for r in mh) else ko)("minheap: %s" % [(r["run"], r["status"], r["minheap_mb"]) for r in mh])
pc, mc = tsv("probe-cg", "runs.tsv"), meta("probe-cg")
(ok if [(r["bench"], r["run"], r["status"]) for r in pc] == [("xalan", "ucfs-CALL_GRAPH", "ok")] and mc.get("timeout") == "120"
 and mc.get("xmx") == "4g" and mc.get("compressed-oops") == "true" else ko)(
    "probe-cg %s %s" % ([(r["bench"], r["run"], r["status"]) for r in pc], (mc.get("timeout"), mc.get("xmx"), mc.get("compressed-oops"))))
pj, mj = tsv("probe-jdk", "runs.tsv"), meta("probe-jdk")
(ok if sorted((r["run"], r["status"] if r["run"] == "insens" else r["status"] in ("ok", "timeout", "oom")) for r in pj)
 == [("insens", "ok"), ("ucfs-ANALYSIS", True)] and mj.get("jdk-bodies") == "yes" and mj.get("timeout") == "120"
 else ko)("probe-jdk %s" % [(r["run"], r["status"]) for r in pj])
host = e5lib.read(os.path.join(F, "host.txt"), "")
secs = re.findall(r"^== (.+)$", host, re.M)
need = ["lscpu", "head -n 3 /proc/meminfo", "uname -a", "cat /etc/os-release", "nproc", "systemd-detect-virt"]
(ok if all(x in secs for x in need) and secs[-1:] == ["kernel-oom"] else ko)("host.txt sections %s" % secs)
# raw archives of the parts and the order of all runs
items = []
for p, row in zip(PARTS, ft):
    want, dirs = set(), []
    base = os.path.join(F, p)
    for root_, dn, fn in os.walk(base):
        if "exit" in fn:
            dirs.append(root_)
            want |= {os.path.relpath(os.path.join(root_, x), F) for x in fn if x in e5lib.RUN_FILES}
            if "sootOutput" in dn:
                ko("sootOutput left in %s" % root_)
    try:
        with tarfile.open(os.path.join(base, "raw.tar.xz")) as t:
            got = {os.path.normpath(n) for n in t.getnames() if t.getmember(n).isfile()}
        (ok if got == want and want and os.path.getmtime(os.path.join(base, "raw.tar.xz")) <= e5lib.iso_epoch(row["finished"]) + 1
         else ko)("%s/raw.tar.xz: %d files, run directories of the part have %d" % (p, len(got), len(want)))
    except Exception as e:
        ko("%s/raw.tar.xz: %r" % (p, e))
    part_items = []
    for d in dirs:
        f = e5lib.read_run(d)
        if f is None:
            ko("%s: files missing %s" % (d, e5lib.run_files_missing(d))); continue
        part_items.append((os.path.relpath(d, F), f["start"], f["end"], f["wall"]))
    part_items.sort(key=lambda x: x[1] or 0)
    a, z = e5lib.iso_epoch(row["started"]) - 1, e5lib.iso_epoch(row["finished"]) + 1
    out_of = [x[0] for x in part_items if x[1] is None or x[1] / 1e9 < a or x[2] / 1e9 > z]
    (ok if not out_of else ko)("%s: %d runs inside started..finished of full.tsv %s" % (p, len(part_items), out_of[:3]))
    items += part_items
ip = e5lib.interval_problems(items)
(ok if not ip else ko)("all %d runs of the four parts one after the other, parts in order %s" % (len(items), ip[:3]))
(ok if git("status", "--porcelain", "--untracked-files=no") == "" else ko)("clone clean after the smoke")
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S4-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S4
finish S4_setup
