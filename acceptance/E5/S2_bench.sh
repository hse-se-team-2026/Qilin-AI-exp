#!/usr/bin/env bash
# E5-S2 acceptance: the repeated-measurement runner scripts/ucfs/e5-bench.sh (docs/ai/tickets/E5-S2.md).
#  1. QILIN_JAR=<fresh fat jar> REPS=2 WARMUP=1 TIMEOUT=600 XMX=8g bash scripts/ucfs/e5-bench.sh <dir> pmd luindex
#     exits 0; stdout has "e5-bench: <bench> <run> rep<k>" for k = 0, 1, 2 in the order rep, then bench (as
#     given), then run (insens ucfs-ANALYSIS ucfs-CALL_GRAPH), and the last line "e5-bench: 18 runs, <n> values
#     in <dir>";
#  2. run directories <dir>/<bench>/<run>/rep<k>/ with cmd.txt, out.txt, time.txt, exit and no sootOutput/;
#     cmd.txt: -Xmx8g -XX:+ExitOnOutOfMemoryError -jar <jar>, -pae -pe -clinit=ONFLY -lcs -mh, the run options
#     (-pta=insens | -pta=ucfs -ucfsbinding=<B>; no -ucfscompare, -ucfspt, -stats), the benchmark arguments
#     (-apppath -libpath -mainclass -reflectionlog -jre=<artifact/benchmarks/JREs/jre1.6.0_45>), -ucfsseam,
#     -exclude=<the JDK list of E4.md D3>;
#  3. runs.tsv: header "bench run rep status exit wall_s user_s sys_s max_rss_mb load1"; one row per run
#     directory (18), all ok, exit 0; wall_s, user_s, sys_s (two decimals) and max_rss_mb (MB, rounded down)
#     = time.txt; load1 a number;
#  4. values.tsv: header "bench run rep key value"; for each run exactly the pairs of e5lib.parse_out(out.txt)
#     (lines "#<key>: <value>" and Time (sec) -> qilin-pta-s, "Main PTA ... elapsed time" -> qilin-main-pta-s,
#     "Main PTA consumed memory" -> qilin-main-pta-rss-mb); every run has the three qilin- keys once; every
#     ucfs run has the phase lines of E5-S1 (e5lib.phase_problems);
#  5. the analysis is the E4 one (independent of cmd.txt): the answer keys of every run and rep (keys not
#     ending in -ms, -s, -mb) = the committed E4 values of the same benchmark and run
#     (docs/ucfs-integration/e4-results, without the -ucfscompare/-ucfspt keys);
#  6. meta.tsv: header "key value" and the keys, in this order: command git-head tree-clean jar jar-sha256
#     benches runs reps warmup skip timeout xmx jvm-flags jdk-bodies host-kind flavor cpu-model cpu-count
#     mem-total-mb kernel os java-version other-java load-start started finished, with git-head = HEAD,
#     tree-clean yes, jar-sha256 of the jar run, reps 2, warmup 1, skip "antlr:ucfs-CALL_GRAPH
#     bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH" (default), jdk-bodies no, host-kind local, flavor "-", cpu-model = lscpu "Model
#     name", cpu-count = nproc, mem-total-mb = MemTotal / 1024, kernel = uname -r, os = PRETTY_NAME of
#     /etc/os-release, java-version = second line of `java -version`, other-java a count;
#  7. SKIP="pmd:ucfs-CALL_GRAPH" RUNS="insens ucfs-CALL_GRAPH" REPS=1 WARMUP=0 ... pmd xalan: no pmd
#     ucfs-CALL_GRAPH directory or row, xalan has it, meta skip = "pmd:ucfs-CALL_GRAPH";
#  8. TIMEOUT=3 RUNS=insens REPS=1 WARMUP=0 ... chart -> status timeout, exit 124; XMX=48m RUNS=insens ...
#     pmd -> status oom, exit 3, wall < 60 s (the JVM exits on OutOfMemoryError instead of hanging);
#  9. JDK_BODIES=yes RUNS=insens REPS=1 WARMUP=0 ... pmd: cmd.txt without -exclude, meta jdk-bodies yes, and
#     Reachable Method (CI), Call Edge(CI), May Fail Cast (Total) = those of the E4 cov-JDK run of pmd;
# 10. exit 2 before any run: unknown run name, unknown benchmark, REPS=0, WARMUP=2, E5_HOST_KIND=cloud,
#     XMX=lots, JDK_BODIES=maybe;
# 11. tracked files unchanged.
# Usage: bash acceptance/E5/S2_bench.sh          (exit 0 = PASS; about 5 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
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
[ -z "$(find "$BADD" -name exit 2>/dev/null)" ] && pass "bad arguments: no run started" || fail "bad arguments: a run was started"

EXPECT_CPU="$(LC_ALL=C lscpu | sed -n 's/^Model name: *//p' | head -n 1)"
EXPECT_OS="$(. /etc/os-release; echo "$PRETTY_NAME")"
EXPECT_JAVA="$("$JAVA" -version 2>&1 | sed -n 2p)"
py - "$BD" "$SD" "$TD" "$MD" "$JD" "$E4_RESULTS" "$LOGS/S2-bench.txt" "$FRESH" "$(git rev-parse HEAD)" \
    "$EXPECT_CPU" "$(nproc)" "$(uname -r)" "$EXPECT_OS" "$EXPECT_JAVA" "$ROOT" > "$LOGS/S2-check.txt" 2>&1 <<'PY'
import hashlib, os, re, sys
import e5lib
bd, sd, td, md, jd, e4dir, stdout, jar, head, cpu, ncpu, kernel, osname, jver, root = sys.argv[1:16]
e4 = e5lib.e4_values(e4dir)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
JDK = "-exclude=java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*"
RUNHDR = "bench run rep status exit wall_s user_s sys_s max_rss_mb load1".split()

def tokens(d):
    return open(os.path.join(d, "cmd.txt")).read().replace("\\", "").split()

def check_cmd(d, run, exclude=True):
    t = tokens(d)
    need = ["-Xmx8g", "-XX:+ExitOnOutOfMemoryError", "-jar", "-pae", "-pe", "-clinit=ONFLY", "-lcs", "-mh",
            "-ucfsseam", "-apppath", "-libpath", "-mainclass", "-reflectionlog",
            "-jre=" + os.path.join(root, "artifact", "benchmarks", "JREs", "jre1.6.0_45")]
    need += ["-pta=insens"] if run == "insens" else ["-pta=ucfs", "-ucfsbinding=" + run[len("ucfs-"):]]
    if exclude:
        need.append(JDK)
    miss = [x for x in need if x not in t]
    extra = [x for x in t if x in ("-ucfscompare", "-ucfspt", "-stats", "-dumpstats")
             or (x.startswith("-pta=") and x not in need)]
    if not exclude:
        extra += [x for x in t if x.startswith("-exclude")]
    return miss, extra

def rows_of(dd):
    try:
        return e5lib.read_tsv(os.path.join(dd, "runs.tsv")), e5lib.read_tsv(os.path.join(dd, "values.tsv"))
    except OSError as e:
        ko("%s: %s" % (dd, e))
        return [], []

# 1. stdout order and last line
want = ["e5-bench: %s %s rep%d" % (b, r, k) for k in (0, 1, 2) for b in ("pmd", "luindex")
        for r in e5lib.RUNS]
got = [l.strip() for l in open(stdout, errors="replace") if re.match(r"e5-bench: \S+ \S+ rep\d+$", l.strip())]
(ok if got == want else ko)("stdout run lines in rep/bench/run order (%d lines)" % len(got))
last = [l.strip() for l in open(stdout, errors="replace") if l.strip()][-1:]
(ok if last and re.fullmatch(r"e5-bench: 18 runs, \d+ values in " + re.escape(os.path.realpath(bd)), last[0])
 else ko)("stdout last line %s" % last)

# 2-5
runs, vals = rows_of(bd)
with open(os.path.join(bd, "runs.tsv")) as f:
    hdr = f.readline().rstrip("\n").split("\t")
(ok if hdr == RUNHDR else ko)("runs.tsv header %s" % hdr)
with open(os.path.join(bd, "values.tsv")) as f:
    vh = f.readline().rstrip("\n").split("\t")
(ok if vh == "bench run rep key value".split() else ko)("values.tsv header %s" % vh)
(ok if len(runs) == 18 else ko)("runs.tsv: %d rows" % len(runs))
V = {}
for r in vals:
    V.setdefault((r["bench"], r["run"], r["rep"]), []).append((r["key"], r["value"]))
nrun = 0
for b in ("pmd", "luindex"):
    for run in e5lib.RUNS:
        ref = e5lib.e4_answer(e4, b, run)
        for k in ("0", "1", "2"):
            d = os.path.join(bd, b, run, "rep" + k)
            row = [r for r in runs if (r["bench"], r["run"], r["rep"]) == (b, run, k)]
            if not all(os.path.exists(os.path.join(d, f)) for f in ("cmd.txt", "out.txt", "time.txt", "exit")):
                ko("%s: files missing" % d); continue
            if os.path.exists(os.path.join(d, "sootOutput")):
                ko("%s: sootOutput/ left" % d)
            if len(row) != 1:
                ko("%s %s rep%s: %d rows" % (b, run, k, len(row))); continue
            row = row[0]
            w, u, s, rss = e5lib.parse_time(os.path.join(d, "time.txt"))
            rc = open(os.path.join(d, "exit")).read().strip()
            good = (row["status"] == "ok" and row["exit"] == "0" == rc
                    and abs(float(row["wall_s"]) - w) <= 0.0051 and abs(float(row["user_s"]) - u) <= 0.0051
                    and abs(float(row["sys_s"]) - s) <= 0.0051 and int(row["max_rss_mb"]) == rss and w > 0
                    and rss > 0 and re.fullmatch(r"\d+\.\d\d", row["wall_s"])
                    and re.fullmatch(r"\d+(\.\d+)?", row["load1"]))
            if not good:
                ko("%s %s rep%s row %s vs time.txt %s exit %s" % (b, run, k, row, (w, u, s, rss), rc)); continue
            miss, extra = check_cmd(d, run)
            if miss or extra:
                ko("%s %s rep%s cmd.txt: missing %s, extra %s" % (b, run, k, miss, extra)); continue
            kv = e5lib.parse_out(open(os.path.join(d, "out.txt"), errors="replace").read())
            if sorted(V.get((b, run, k), [])) != sorted(kv):
                ko("%s %s rep%s: values.tsv rows != parse_out(out.txt)" % (b, run, k)); continue
            keys = [x for x, _ in kv]
            if any(keys.count(q) != 1 for q in ("qilin-pta-s", "qilin-main-pta-s", "qilin-main-pta-rss-mb")):
                ko("%s %s rep%s: qilin- keys not once each" % (b, run, k)); continue
            if run != "insens":
                pr = e5lib.phase_problems(kv)
                if pr:
                    ko("%s %s rep%s phases: %s" % (b, run, k, pr)); continue
            ans = {x: y for x, y in kv if not e5lib.is_measure(x)}
            if not ref or ans != ref:
                ko("%s %s rep%s: answer differs from E4 %s" % (b, run, k,
                   sorted(x for x in set(ans) | set(ref) if ans.get(x) != ref.get(x))[:6])); continue
            nrun += 1
(ok if nrun == 18 else ko)("%d of 18 runs: row = time.txt, cmd.txt, values = out.txt, phases, answer = E4" % nrun)

# 6. meta
try:
    with open(os.path.join(bd, "meta.tsv")) as f:
        mh = f.readline().rstrip("\n")
    meta = e5lib.read_tsv(os.path.join(bd, "meta.tsv"))
except OSError:
    mh, meta = "", []
keys = [r["key"] for r in meta]
WANT = ("command git-head tree-clean jar jar-sha256 benches runs reps warmup skip timeout xmx jvm-flags jdk-bodies "
        "host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version other-java load-start started "
        "finished").split()
(ok if mh == "key\tvalue" and keys == WANT else ko)("meta.tsv keys %s" % keys)
m = {r["key"]: r["value"] for r in meta}
memmb = [int(l.split()[1]) // 1024 for l in open("/proc/meminfo") if l.startswith("MemTotal:")][0]
exp = {"git-head": head, "tree-clean": "yes", "jar-sha256": hashlib.sha256(open(jar, "rb").read()).hexdigest(),
       "benches": "pmd luindex", "runs": "insens ucfs-ANALYSIS ucfs-CALL_GRAPH", "reps": "2", "warmup": "1",
       "skip": "antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH", "timeout": "600", "xmx": "8g",
       "jvm-flags": "-XX:+ExitOnOutOfMemoryError", "jdk-bodies": "no", "host-kind": "local", "flavor": "-",
       "cpu-model": cpu, "cpu-count": ncpu, "mem-total-mb": str(memmb), "kernel": kernel, "os": osname,
       "java-version": jver}
bad = {k: (m.get(k), v) for k, v in exp.items() if m.get(k) != v}
(ok if not bad else ko)("meta.tsv values %s" % (bad or "as expected"))
(ok if "bash scripts/ucfs/e5-bench.sh" in m.get("command", "") and "pmd luindex" in m.get("command", "")
 and re.fullmatch(r"\d+", m.get("other-java", "")) and re.fullmatch(r"[\d.]+ [\d.]+ [\d.]+", m.get("load-start", ""))
 and m.get("started") and m.get("finished") else ko)("meta.tsv command, other-java, load-start, started, finished")

# 7. SKIP
runs7, _ = rows_of(sd)
have = sorted((r["bench"], r["run"]) for r in runs7)
m7 = e5lib.read_meta(os.path.join(sd, "meta.tsv")) if os.path.exists(os.path.join(sd, "meta.tsv")) else {}
(ok if have == [("pmd", "insens"), ("xalan", "insens"), ("xalan", "ucfs-CALL_GRAPH")]
 and not os.path.exists(os.path.join(sd, "pmd", "ucfs-CALL_GRAPH")) and m7.get("skip") == "pmd:ucfs-CALL_GRAPH"
 and all(r["status"] == "ok" for r in runs7) else ko)("SKIP: rows %s, skip %r" % (have, m7.get("skip")))

# 8. timeout and OOM
r8, _ = rows_of(td)
(ok if [(r["status"], r["exit"]) for r in r8] == [("timeout", "124")] else ko)("TIMEOUT=3 chart: %s" % r8)
r8, _ = rows_of(md)
(ok if [(r["status"], r["exit"]) for r in r8] == [("oom", "3")] and float(r8[0]["wall_s"]) < 60 else ko)(
    "XMX=48m pmd: %s" % r8)

# 9. JDK bodies
r9, v9 = rows_of(jd)
m9 = e5lib.read_meta(os.path.join(jd, "meta.tsv")) if os.path.exists(os.path.join(jd, "meta.tsv")) else {}
d9 = os.path.join(jd, "pmd", "insens", "rep1")
miss, extra = check_cmd(d9, "insens", exclude=False) if os.path.exists(os.path.join(d9, "cmd.txt")) else (["cmd.txt"], [])
cov = e4.get(("pmd", "cov-JDK"), {})
got = {r["key"]: r["value"] for r in v9}
same = [k for k in ("Reachable Method (CI)", "Call Edge(CI)", "May Fail Cast (Total)") if cov.get(k) and got.get(k) == cov.get(k)]
(ok if [(r["status"]) for r in r9] == ["ok"] and not miss and not extra and m9.get("jdk-bodies") == "yes" and len(same) == 3
 else ko)("JDK_BODIES=yes pmd: status %s, cmd missing %s extra %s, jdk-bodies %r, equal to E4 cov-JDK %s" % (
    [r["status"] for r in r9], miss, extra, m9.get("jdk-bodies"), same))
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S2-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S2
finish S2_bench
