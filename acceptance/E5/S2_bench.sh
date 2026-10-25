#!/usr/bin/env bash
# E5-S2 acceptance: the repeated-measurement runner scripts/ucfs/e5-bench.sh (docs/ai/tickets/E5-S2.md).
#  1. QILIN_JAR=<fresh fat jar> REPS=2 WARMUP=1 TIMEOUT=600 XMX=8g bash scripts/ucfs/e5-bench.sh <dir> pmd luindex
#     exits 0; stdout has "e5-bench: <bench> <run> rep<k>" in the order of e5lib.run_order (rep 0, 1, 2; inside a
#     rep the benchmarks as given; inside a benchmark the runs insens ucfs-ANALYSIS ucfs-CALL_GRAPH rotated left
#     by k), and the last line "e5-bench: 18 runs, <n> values in <dir>";
#  2. run directories <dir>/<bench>/<run>/rep<k>/ with exactly the files of e5lib.RUN_FILES among the regular
#     files (cmd.txt out.txt time.txt exit load1 other-java start end stat-before stat-after) and no sootOutput/;
#     cmd.txt (a bash-quoted command line) is token for token e5lib.expected_cmd: <JAVA_HOME>/bin/java -Xmx8g
#     -XX:+ExitOnOutOfMemoryError -jar <jar> -pae -pe -clinit=ONFLY -lcs -mh <run options> <benchmark
#     arguments of artifact/util/benchmark.py> -ucfsseam -exclude=<JDK list of E4.md D3> - nothing else, so
#     the runs differ only in -pta/-ucfsbinding (no other JVM flag, no -ucfscompare/-ucfspt);
#  3. runs.tsv: header "bench run rep status exit wall_s user_s sys_s max_rss_mb load1 other_java procs_running
#     steal_pct start_ns end_ns"; one row per run directory (18), each = its files: status (e5lib.status_of),
#     exit, wall/user/sys (two decimals) and max RSS (MB, rounded down) of time.txt, load1, other-java,
#     procs_running of stat-before, steal_pct = 100 * steal ticks / all ticks between stat-before and
#     stat-after (two decimals), start, end;
#  4. values.tsv: header "bench run rep key value"; for each run exactly the pairs of e5lib.parse_out(out.txt);
#     the three qilin- keys once; times consistent (e5lib.time_problems: phase lines of E5-S1 for the ucfs
#     runs, the kernel and UCFS inside qilin-pta-s, qilin-pta-s <= qilin-main-pta-s <= wall_s); no out.txt
#     reports "Picked up ..." options of the environment;
#  5. the analysis is the E4 one (independent of cmd.txt, checked for every run even if cmd.txt is wrong): the
#     answer keys of every run and rep = the committed E4 values (docs/ucfs-integration/e4-results, without
#     the -ucfscompare/-ucfspt keys);
#  6. the runs are sequential and in order: [start, end] of the 18 runs follow run_order without overlap, the
#     wall time of each lies inside its [start, end], and all lie between meta started and finished (+- 1 s);
#  7. meta.tsv: header "key value" and the keys, in this order: command git-head tree-clean jar jar-sha256
#     benches runs reps warmup skip timeout xmx jvm-flags jdk-bodies java-tool-options java-options
#     jdk-java-options compressed-oops host-kind flavor cpu-model cpu-count mem-total-mb kernel os
#     java-version other-java load-start started finished, with git-head = HEAD, tree-clean yes, jar-sha256 of
#     the jar run, reps 2, warmup 1, the default skip, jdk-bodies no, the three java option keys empty,
#     compressed-oops = UseCompressedOops of `java -Xmx8g -XX:+PrintFlagsFinal -version`, host-kind local,
#     flavor "-", cpu-model = lscpu "Model name", cpu-count = nproc, mem-total-mb = MemTotal / 1024, kernel =
#     uname -r, os = PRETTY_NAME, java-version = second line of `java -version`, other-java a count;
#  8. SKIP="pmd:ucfs-CALL_GRAPH" RUNS="insens ucfs-CALL_GRAPH" REPS=1 WARMUP=0 ... pmd xalan: no pmd
#     ucfs-CALL_GRAPH directory or row, xalan has it, meta skip = "pmd:ucfs-CALL_GRAPH", order of run_order;
#  9. TIMEOUT=3 RUNS=insens REPS=1 WARMUP=0 ... chart -> status timeout, exit 124; XMX=48m RUNS=insens ... pmd
#     -> status oom, exit 3, wall < 60 s (the JVM exits on OutOfMemoryError instead of hanging); a run whose
#     JVM this check kills with SIGKILL (TIMEOUT=600, chart insens) -> status killed, exit 137 (not timeout);
# 10. JDK_BODIES=yes RUNS=insens REPS=1 WARMUP=0 ... pmd: cmd.txt = expected_cmd without -exclude, meta
#     jdk-bodies yes, and Reachable Method (CI), Call Edge(CI), May Fail Cast (Total) = those of the E4 cov-JDK
#     run of pmd;
# 11. exit 2 before any run: unknown run name, unknown benchmark, REPS=0, WARMUP=2, E5_HOST_KIND=cloud,
#     XMX=lots, JDK_BODIES=maybe, JAVA_TOOL_OPTIONS=-Xint, _JAVA_OPTIONS=-Xint, JDK_JAVA_OPTIONS=-Xint;
# 12. tracked files unchanged.
# Usage: bash acceptance/E5/S2_bench.sh          (exit 0 = PASS; about 7 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S2_bench; }

BD="$OUT/bench"
safe_reset_dir "$BD"
QILIN_JAR="$FRESH" REPS=2 WARMUP=1 TIMEOUT=600 XMX=8g bash scripts/ucfs/e5-bench.sh "$BD" pmd luindex \
    > "$LOGS/S2-bench.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh pmd luindex exit 0" || fail "e5-bench.sh exit $rc (see $LOGS/S2-bench.txt)"

SD="$OUT/bench-skip"
safe_reset_dir "$SD"
QILIN_JAR="$FRESH" SKIP="pmd:ucfs-CALL_GRAPH" RUNS="insens ucfs-CALL_GRAPH" REPS=1 WARMUP=0 XMX=8g \
    bash scripts/ucfs/e5-bench.sh "$SD" pmd xalan > "$LOGS/S2-skip.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh SKIP exit 0" || fail "e5-bench.sh SKIP exit $rc"

TD="$OUT/bench-timeout"
safe_reset_dir "$TD"
QILIN_JAR="$FRESH" TIMEOUT=3 RUNS=insens REPS=1 WARMUP=0 bash scripts/ucfs/e5-bench.sh "$TD" chart > "$LOGS/S2-timeout.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh TIMEOUT=3 exit 0" || fail "e5-bench.sh TIMEOUT=3 exit $rc"

MD="$OUT/bench-oom"
safe_reset_dir "$MD"
QILIN_JAR="$FRESH" XMX=48m RUNS=insens REPS=1 WARMUP=0 bash scripts/ucfs/e5-bench.sh "$MD" pmd > "$LOGS/S2-oom.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh XMX=48m exit 0" || fail "e5-bench.sh XMX=48m exit $rc"

# 9. a JVM killed from outside (as the OOM killer of the kernel would): SIGKILL to the java process of the run
# (only the process named java: GNU time and timeout carry the same command line)
KD="$OUT/bench-killed"
safe_reset_dir "$KD"
QILIN_JAR="$FRESH" TIMEOUT=600 RUNS=insens REPS=1 WARMUP=0 bash scripts/ucfs/e5-bench.sh "$KD" chart > "$LOGS/S2-killed.txt" 2>&1 &
kpid=$!
killed=no
for _ in $(seq 1 120); do
    sleep 0.5
    jp=""
    for p in $(pgrep -f -- "-jar $FRESH .*-mainclass [^ ]*chart"); do
        [ "$(ps -o comm= -p "$p" 2>/dev/null)" = java ] && jp="$p"
    done
    if [ -n "$jp" ]; then sleep 2; kill -9 "$jp" 2>/dev/null && killed=yes; break; fi
done
wait $kpid
rc=$?
[ $rc -eq 0 ] && [ $killed = yes ] && pass "e5-bench.sh with the JVM killed: exit 0" || fail "e5-bench.sh killed run: exit $rc, kill sent: $killed"

JD="$OUT/bench-jdk"
safe_reset_dir "$JD"
QILIN_JAR="$FRESH" JDK_BODIES=yes RUNS=insens REPS=1 WARMUP=0 XMX=8g bash scripts/ucfs/e5-bench.sh "$JD" pmd \
    > "$LOGS/S2-jdk.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-bench.sh JDK_BODIES=yes exit 0" || fail "e5-bench.sh JDK_BODIES=yes exit $rc"

bad() {
    local what="$1" rc
    shift
    env QILIN_JAR="$FRESH" "$@" > "$LOGS/S2-bad.txt" 2>&1
    rc=$?
    [ $rc -eq 2 ] && pass "$what: exit 2" || fail "$what: exit $rc"
}
BADD="$OUT/bench-bad"
safe_reset_dir "$BADD"
bad "unknown run" RUNS="insens foo" bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "unknown benchmark" bash scripts/ucfs/e5-bench.sh "$BADD" nosuchbench
bad "REPS=0" REPS=0 bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "WARMUP=2" WARMUP=2 bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "E5_HOST_KIND=cloud" E5_HOST_KIND=cloud bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "XMX=lots" XMX=lots bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "JDK_BODIES=maybe" JDK_BODIES=maybe bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "JAVA_TOOL_OPTIONS=-Xint" JAVA_TOOL_OPTIONS=-Xint bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "_JAVA_OPTIONS=-Xint" _JAVA_OPTIONS=-Xint bash scripts/ucfs/e5-bench.sh "$BADD" xalan
bad "JDK_JAVA_OPTIONS=-Xint" JDK_JAVA_OPTIONS=-Xint bash scripts/ucfs/e5-bench.sh "$BADD" xalan
[ -z "$(find "$BADD" -name exit 2>/dev/null)" ] && pass "bad arguments: no run started" || fail "bad arguments: a run was started"

EXPECT_CPU="$(LC_ALL=C lscpu | sed -n 's/^Model name: *//p' | head -n 1)"
EXPECT_OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
EXPECT_JAVA="$("$JAVA" -version 2>&1 | sed -n 2p)"
EXPECT_COOPS="$("$JAVA" -Xmx8g -XX:+PrintFlagsFinal -version 2>/dev/null | awk '$2=="UseCompressedOops"{print $4}')"
py - "$BD" "$SD" "$TD" "$MD" "$KD" "$JD" "$E4_RESULTS" "$LOGS/S2-bench.txt" "$FRESH" "$(git rev-parse HEAD)" \
    "$EXPECT_CPU" "$(nproc)" "$(uname -r)" "$EXPECT_OS" "$EXPECT_JAVA" "$ROOT" "$JAVA" "$EXPECT_COOPS" \
    > "$LOGS/S2-check.txt" 2>&1 <<'PY'
import hashlib, os, re, sys
import e5lib
bd, sd, td, md, kd, jd, e4dir, stdout, jar, head, cpu, ncpu, kernel, osname, jver, root, java, coops = sys.argv[1:19]
jar = os.path.realpath(jar)
e4 = e5lib.e4_values(e4dir)
bmap = e5lib.bench_map(root)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
RUNHDR = ("bench run rep status exit wall_s user_s sys_s max_rss_mb load1 other_java procs_running steal_pct "
          "start_ns end_ns").split()
META = ("command git-head tree-clean jar jar-sha256 benches runs reps warmup skip timeout xmx jvm-flags jdk-bodies "
        "java-tool-options java-options jdk-java-options compressed-oops host-kind flavor cpu-model cpu-count "
        "mem-total-mb kernel os java-version other-java load-start started finished").split()

def load(dd):
    try:
        return (e5lib.header(os.path.join(dd, "runs.tsv")), e5lib.read_tsv(os.path.join(dd, "runs.tsv")),
                e5lib.read_tsv(os.path.join(dd, "values.tsv")), e5lib.read_meta(os.path.join(dd, "meta.tsv")))
    except OSError as e:
        ko("%s: %s" % (dd, e))
        return [], [], [], {}

def row_problems(row, f, timeout):
    """differences between a runs.tsv row and the files of its run directory"""
    st = e5lib.status_of(int(f["exit"]), f["out"], f["wall"], timeout)
    s0, s1 = f["stat0"], f["stat1"]
    if s0 is None or s1 is None:
        return ["stat-before/stat-after without cpu/procs_running lines"]
    dall = s1[1] - s0[1]
    steal = 100.0 * (s1[0] - s0[0]) / dall if dall > 0 else 0.0
    want = {"status": st, "exit": f["exit"], "max_rss_mb": str(f["rss"]), "load1": f["load1"],
            "other_java": str(f["other_java"]), "procs_running": str(s0[2]), "start_ns": str(f["start"]),
            "end_ns": str(f["end"])}
    p = ["%s %r != %r" % (k, row.get(k), v) for k, v in want.items() if row.get(k) != v]
    for k, x in (("wall_s", f["wall"]), ("user_s", f["user"]), ("sys_s", f["sys"]), ("steal_pct", steal)):
        if not re.fullmatch(r"\d+\.\d\d", row.get(k, "")) or abs(float(row[k]) - x) > 0.0051:
            p.append("%s %r != %.2f" % (k, row.get(k), x))
    if not re.fullmatch(r"\d+(\.\d+)?", f["load1"]) or f["other_java"] is None:
        p.append("load1 %r / other-java %r not numbers" % (f["load1"], f["other_java"]))
    return p

def check_part(dd, benches, runs, reps, warmup, skip, xmx, timeout, want_status, label, jdk_bodies=False, answer=True):
    """the rows of runs.tsv against the run directories, cmd.txt, values, answers and the order of the runs"""
    hdr, rows, vals, meta = load(dd)
    (ok if hdr == RUNHDR else ko)("%s: runs.tsv header %s" % (label, hdr))
    order = e5lib.run_order(benches, runs, reps, warmup, skip)
    have = {(int(r["rep"]), r["bench"], r["run"]): r for r in rows}
    (ok if sorted(have) == sorted(order) and len(rows) == len(order) else ko)(
        "%s: %d rows for the %d runs of run_order" % (label, len(rows), len(order)))
    V = {}
    for r in vals:
        V.setdefault((r["bench"], r["run"], r["rep"]), []).append((r["key"], r["value"]))
    nice, items = 0, []
    for (k, b, run) in order:
        d = os.path.join(dd, b, run, "rep%d" % k)
        lab = "%s %s %s rep%d" % (label, b, run, k)
        files = sorted(x for x in os.listdir(d) if os.path.isfile(os.path.join(d, x))) if os.path.isdir(d) else []
        if files != sorted(e5lib.RUN_FILES) or os.path.exists(os.path.join(d, "sootOutput")):
            ko("%s: files %s (expected RUN_FILES, no sootOutput)" % (lab, files)); continue
        f = e5lib.read_run(d)
        items.append((lab, f["start"], f["end"], f["wall"]))
        probs = []
        row = have.get((k, b, run))
        probs += row_problems(row, f, timeout) if row else ["no runs.tsv row"]
        st = e5lib.status_of(int(f["exit"]), f["out"], f["wall"], timeout)
        if st != want_status:
            probs.append("status %s, expected %s" % (st, want_status))
        want = e5lib.expected_cmd(java, jar, xmx, run, b, root, bmap, jdk_bodies)
        cp = e5lib.cmd_problem(f["cmd"], want)
        if cp:
            probs.append("cmd.txt: " + cp)
        if sorted(V.get((b, run, str(k)), [])) != sorted(f["kv"]):
            probs.append("values.tsv rows != parse_out(out.txt)")
        if f["picked_up"]:
            probs.append("out.txt: the JVM picked up options from the environment")
        if st == "ok":
            keys = [x for x, _ in f["kv"]]
            if any(keys.count(q) != 1 for q in ("qilin-pta-s", "qilin-main-pta-s", "qilin-main-pta-rss-mb")):
                probs.append("qilin- keys not once each")
            probs += e5lib.time_problems(run, f["kv"], f["wall"])
            if answer:
                ref = e5lib.e4_answer(e4, b, run)
                ans = {x: y for x, y in f["kv"] if not e5lib.is_measure(x)}
                if not ref or ans != ref:
                    probs.append("answer differs from E4 in %s" % sorted(x for x in set(ans) | set(ref)
                                                                         if ans.get(x) != ref.get(x))[:6])
        if probs:
            ko("%s: %s" % (lab, "; ".join(probs)))
        else:
            nice += 1
    (ok if nice == len(order) else ko)("%s: %d of %d runs: row = files, status %s, cmd.txt exact, values = out.txt, "
                                        "times consistent%s" % (label, nice, len(order), want_status,
                                                                ", answer = E4" if answer else ""))
    ip = e5lib.interval_problems(items)
    try:
        a, z = e5lib.iso_epoch(meta["started"]) - 1, e5lib.iso_epoch(meta["finished"]) + 1
        ip += ["%s outside [started, finished] of meta.tsv" % lab for lab, s, e, _ in items
               if s is None or e is None or s / 1e9 < a or e / 1e9 > z]
    except (KeyError, ValueError) as e:
        ip.append("meta started/finished: %r" % e)
    (ok if not ip else ko)("%s: %d runs sequential in run_order, inside meta started..finished %s" % (
        label, len(items), ip[:3] if ip else ""))
    return rows, vals, meta

skip0 = e5lib.parse_skip(e5lib.DEFAULT_SKIP_S)
# 1. stdout order and last line
want = ["e5-bench: %s %s rep%d" % (b, r, k) for k, b, r in e5lib.run_order(["pmd", "luindex"], e5lib.RUNS, 2, True, skip0)]
lines = [l.strip() for l in open(stdout, errors="replace") if l.strip()]
got = [l for l in lines if re.fullmatch(r"e5-bench: \S+ \S+ rep\d+", l)]
(ok if got == want else ko)("stdout run lines in run_order (%d lines; first %s)" % (len(got), got[:4]))
(ok if lines and re.fullmatch(r"e5-bench: 18 runs, \d+ values in " + re.escape(os.path.realpath(bd)), lines[-1])
 else ko)("stdout last line %s" % lines[-1:])
# 2-6
_, _, vh, m = None, None, None, None
rows, vals, m = check_part(bd, ["pmd", "luindex"], e5lib.RUNS, 2, True, skip0, "8g", 600, "ok", "main")
try:
    vh = e5lib.header(os.path.join(bd, "values.tsv"))
except OSError:
    vh = None
(ok if vh == "bench run rep key value".split() else ko)("values.tsv header %s" % vh)
# 7. meta
try:
    with open(os.path.join(bd, "meta.tsv")) as f:
        mh = f.readline().rstrip("\n")
    keys = [r["key"] for r in e5lib.read_tsv(os.path.join(bd, "meta.tsv"))]
except OSError:
    mh, keys = "", []
(ok if mh == "key\tvalue" and keys == META else ko)("meta.tsv keys %s" % keys)
memmb = [int(l.split()[1]) // 1024 for l in open("/proc/meminfo") if l.startswith("MemTotal:")][0]
exp = {"git-head": head, "tree-clean": "yes", "jar-sha256": hashlib.sha256(open(jar, "rb").read()).hexdigest(),
       "benches": "pmd luindex", "runs": "insens ucfs-ANALYSIS ucfs-CALL_GRAPH", "reps": "2", "warmup": "1",
       "skip": e5lib.DEFAULT_SKIP_S, "timeout": "600", "xmx": "8g", "jvm-flags": "-XX:+ExitOnOutOfMemoryError",
       "jdk-bodies": "no", "java-tool-options": "", "java-options": "", "jdk-java-options": "",
       "compressed-oops": coops, "host-kind": "local", "flavor": "-", "cpu-model": cpu, "cpu-count": ncpu,
       "mem-total-mb": str(memmb), "kernel": kernel, "os": osname, "java-version": jver}
bad = {k: (m.get(k), v) for k, v in exp.items() if m.get(k) != v}
(ok if not bad and coops in ("true", "false") else ko)("meta.tsv values %s" % (bad or "as expected"))
(ok if "bash scripts/ucfs/e5-bench.sh" in m.get("command", "") and "pmd luindex" in m.get("command", "")
 and re.fullmatch(r"\d+", m.get("other-java", "")) and re.fullmatch(r"[\d.]+ [\d.]+ [\d.]+", m.get("load-start", ""))
 and m.get("started") and m.get("finished") else ko)("meta.tsv command, other-java, load-start, started, finished")
# 8. SKIP
_, _, m8 = check_part(sd, ["pmd", "xalan"], ["insens", "ucfs-CALL_GRAPH"], 1, False, {("pmd", "ucfs-CALL_GRAPH")},
                      "8g", 900, "ok", "skip")
(ok if not os.path.exists(os.path.join(sd, "pmd", "ucfs-CALL_GRAPH")) and m8.get("skip") == "pmd:ucfs-CALL_GRAPH"
 else ko)("SKIP: no pmd ucfs-CALL_GRAPH directory, skip %r" % m8.get("skip"))
# 9. timeout, OOM, killed
r9, _, _ = check_part(td, ["chart"], ["insens"], 1, False, set(), "16g", 3, "timeout", "timeout", answer=False)
(ok if [(r["status"], r["exit"]) for r in r9] == [("timeout", "124")] else ko)("TIMEOUT=3 chart: %s" % r9)
r9, _, _ = check_part(md, ["pmd"], ["insens"], 1, False, set(), "48m", 900, "oom", "oom", answer=False)
(ok if [(r["status"], r["exit"]) for r in r9] == [("oom", "3")] and float(r9[0]["wall_s"]) < 60 else ko)(
    "XMX=48m pmd: %s" % r9)
r9, _, _ = check_part(kd, ["chart"], ["insens"], 1, False, set(), "16g", 600, "killed", "killed", answer=False)
(ok if [(r["status"], r["exit"]) for r in r9] == [("killed", "137")] else ko)("SIGKILL chart: %s" % r9)
# 10. JDK bodies
r10, v10, m10 = check_part(jd, ["pmd"], ["insens"], 1, False, set(), "8g", 900, "ok", "jdk", jdk_bodies=True,
                           answer=False)
cov = e4.get(("pmd", "cov-JDK"), {})
got = {r["key"]: r["value"] for r in v10}
same = [k for k in ("Reachable Method (CI)", "Call Edge(CI)", "May Fail Cast (Total)") if cov.get(k) and got.get(k) == cov.get(k)]
(ok if m10.get("jdk-bodies") == "yes" and len(same) == 3 else ko)(
    "JDK_BODIES=yes pmd: jdk-bodies %r, equal to E4 cov-JDK %s" % (m10.get("jdk-bodies"), same))
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S2-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S2
finish S2_bench
