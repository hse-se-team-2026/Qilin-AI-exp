"""Helpers of the E5 acceptance checks and of e5tables.py (python3 standard library only).

The E5 contracts (docs/ai/tickets/E5.md and E5-S1 ... E5-S6) that the checks share:
- a measurement key ends in -ms, -s or -mb (MEASURE); every other key of a run is an answer key;
- the output of one Qilin run is parsed by parse_out(): every line "#<key>: <value>" (one token value,
  the rule of scripts/ucfs/e4-bench.sh) and three lines of Qilin without '#', under fixed key names;
- the phases of the UCFS part of -pta=ucfs are printed as "#UCFS-phase-<p>-ms: <ms with 3 decimals>"
  for p in PHASES, then the total (E5-S1); they cover the total within max(5 ms, 1 %) (phase_problems);
- one run of Qilin is one directory with the files RUN_FILES (E5-S2): its command line (cmd.txt, exactly
  expected_cmd()), its output, GNU time, exit code, load1, the other java processes, start/end (epoch ns)
  and /proc/stat before and after; its status is status_of();
- the order of the runs of e5-bench.sh is run_order() (repetition, then benchmark, then the runs rotated
  by the repetition number);
- the minimum-heap search of e5-minheap.sh is replayed by replay_minheap() (E5-S3);
- statistics: median, quartiles (method "inclusive" of statistics.quantiles), and the distribution-free
  confidence interval of the median from order statistics (median_ci);
- committed results carry no secrets (secret_hits, scan_paths: E5-S5a, E5-S5b).
This module is written independently of the scripts it checks (scripts/ucfs/e5-*.sh).
"""
import csv
import datetime
import math
import os
import re
import runpy
import shlex
import statistics
import tarfile

MEASURE = re.compile(r"(-ms|-s|-mb)$")
# the time keys of the E4 checks (acceptance/E4/S5_bench.sh, S6_results.sh)
E4_TIME = re.compile(r"-ms$|time|Time")
HASH_LINE = re.compile(r"^#([^:]+):\s*(\S+)\s*$")
EXTRA = [
    (re.compile(r"^Time \(sec\):\s*(\S+)\s*$"), "qilin-pta-s"),
    (re.compile(r"^Main PTA \(including pre-analysis\) elapsed time: (\S+)s\s*$"), "qilin-main-pta-s"),
    (re.compile(r"^Main PTA consumed memory: (\S+) MB\s*$"), "qilin-main-pta-rss-mb"),
]
PHASES = ["export", "grammar", "rsm", "input", "parse", "roots", "pairs", "import"]
PHASE_TOTAL = "total"
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]
# the order of the E4 results and of every E5 table (not the order of artifact/util/benchmark.py)
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan",
           "checkstyle", "findbugs", "JPC"]
COVERED = ["antlr", "bloat", "chart", "fop", "luindex", "lusearch"]
DEFAULT_SKIP = [("antlr", "ucfs-CALL_GRAPH"), ("bloat", "ucfs-CALL_GRAPH"), ("checkstyle", "ucfs-CALL_GRAPH")]
DEFAULT_SKIP_S = " ".join("%s:%s" % p for p in DEFAULT_SKIP)
# prefixes of the E4 keys that come from -ucfscompare and -ucfspt, which the E5 runs do not pass
E4_ONLY = ("UCFS-cmp-", "UCFS-pt-", "cmp/")
JDK_EXCLUDE = "java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*"
RUNPY_OPTS = ["-pae", "-pe", "-clinit=ONFLY", "-lcs", "-mh"]
JVM_FLAGS = ["-XX:+ExitOnOutOfMemoryError"]
# the files of one run directory (e5-bench.sh) or step directory (e5-minheap.sh), E5-S2
RUN_FILES = ["cmd.txt", "out.txt", "time.txt", "exit", "load1", "other-java", "start", "end", "stat-before",
             "stat-after"]
# environment variables that change the JVM of every run; meta.tsv records them and they must be empty
JAVA_ENV = [("JAVA_TOOL_OPTIONS", "java-tool-options"), ("_JAVA_OPTIONS", "java-options"),
            ("JDK_JAVA_OPTIONS", "jdk-java-options")]
CONFIRM_MB = 32


def is_measure(key):
    return bool(MEASURE.search(key))


def read_tsv(path):
    """Rows of a TSV file with a header line, as dicts (values are strings)."""
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def header(path):
    with open(path) as f:
        return f.readline().rstrip("\n").split("\t")


def read_meta(path):
    return {r["key"]: r["value"] for r in read_tsv(path)}


def read(path, default=None):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return default


def parse_out(text):
    """[(key, value)] of the output of one Qilin run, in the order of the lines."""
    res = []
    for line in text.splitlines():
        m = HASH_LINE.match(line)
        if m:
            res.append((m.group(1).strip(), m.group(2)))
            continue
        s = line.strip()
        for rx, key in EXTRA:
            m = rx.match(s)
            if m:
                res.append((key, m.group(1)))
    return res


def answer_of(text):
    """{key: value} of the answer keys of the output of one run."""
    return {k: v for k, v in parse_out(text) if not is_measure(k)}


def _secs(s):
    x = 0.0
    for part in s.split(":"):
        x = x * 60 + float(part)
    return x


def parse_time(path):
    """(wall_s, user_s, sys_s, max_rss_mb) of a report of /usr/bin/time -v."""
    v = {}
    with open(path, errors="replace") as f:
        for line in f:
            if ": " in line:
                k, val = line.strip().rsplit(": ", 1)
                v[k] = val
    wall = _secs(v.get("Elapsed (wall clock) time (h:mm:ss or m:ss)", "0"))
    return (wall, float(v.get("User time (seconds)", 0)), float(v.get("System time (seconds)", 0)),
            int(v.get("Maximum resident set size (kbytes)", 0)) // 1024)


def parse_stat(text):
    """(steal ticks, all ticks, procs_running) of the aggregate "cpu" line and the procs_running line of
    /proc/stat; None when a line is missing."""
    cpu = re.search(r"^cpu\s+(\d+(?:\s+\d+)*)\s*$", text or "", re.M)
    pr = re.search(r"^procs_running\s+(\d+)\s*$", text or "", re.M)
    if not cpu or not pr:
        return None
    f = [int(x) for x in cpu.group(1).split()]
    return (f[7] if len(f) > 7 else 0), sum(f[:8]), int(pr.group(1))


def status_of(rc, out_text, wall_s, timeout_s):
    """Status of one run (E5-S2): ok = exit 0; timeout = exit 124, or 137 after at least timeout_s - 5 s
    (timeout -k sent SIGKILL); killed = exit 137 earlier (killed from outside, e.g. by the OOM killer);
    oom = exit 3 with OutOfMemoryError in the output (-XX:+ExitOnOutOfMemoryError); error otherwise."""
    if rc == 0:
        return "ok"
    if rc == 124:
        return "timeout"
    if rc == 137:
        return "timeout" if wall_s >= timeout_s - 5 else "killed"
    if rc == 3 and "OutOfMemoryError" in (out_text or ""):
        return "oom"
    return "error"


def run_files_missing(d):
    return [f for f in RUN_FILES if not os.path.isfile(os.path.join(d, f))]


def read_run(d):
    """The facts of one run directory: exit, wall/user/sys/rss of time.txt, load1, other-java, start/end ns,
    the /proc/stat facts before and after, the parsed output and whether the JVM picked up options from
    the environment. None when a file of RUN_FILES is missing."""
    if run_files_missing(d):
        return None
    out = read(os.path.join(d, "out.txt"), "")
    w, u, s, rss = parse_time(os.path.join(d, "time.txt"))
    def num(f):
        t = read(os.path.join(d, f), "").strip()
        return int(t) if re.fullmatch(r"\d+", t) else None
    return {"exit": read(os.path.join(d, "exit"), "").strip(), "wall": w, "user": u, "sys": s, "rss": rss,
            "load1": read(os.path.join(d, "load1"), "").strip(), "other_java": num("other-java"),
            "start": num("start"), "end": num("end"),
            "stat0": parse_stat(read(os.path.join(d, "stat-before"))),
            "stat1": parse_stat(read(os.path.join(d, "stat-after"))),
            "out": out, "kv": parse_out(out), "picked_up": picked_up(out), "cmd": cmd_tokens(d)}


def picked_up(out_text):
    """True when the JVM reports options taken from the environment ("Picked up JAVA_TOOL_OPTIONS: ...",
    "Picked up _JAVA_OPTIONS", "NOTE: Picked up JDK_JAVA_OPTIONS")."""
    return bool(re.search(r"Picked up (JAVA_TOOL_OPTIONS|_JAVA_OPTIONS|JDK_JAVA_OPTIONS)", out_text or ""))


def e4_values(results_dir):
    """{(bench, run): {key: value}} of docs/ucfs-integration/e4-results/values.tsv."""
    res = {}
    for r in read_tsv(os.path.join(results_dir, "values.tsv")):
        res.setdefault((r["bench"], r["run"]), {})[r["key"]] = r["value"]
    return res


def e4_answer(e4, bench, run):
    """The answer keys of an E5 run (bench, run) expected from the E4 results: the E4 keys of the same
    run that are not E4 time keys and not from -ucfscompare/-ucfspt."""
    return {k: v for k, v in e4.get((bench, run), {}).items()
            if not E4_TIME.search(k) and not k.startswith(E4_ONLY)}


def phase_tol(x):
    return max(5.0, 0.01 * x)


def phase_problems(pairs):
    """Problems of the #UCFS-phase- lines of one -pta=ucfs run ([(key, value)] of parse_out); [] = fine.
    Contract (E5-S1): each of PHASES and then total once, in this order, after #UCFS-import-ucfs-ms;
    values with three decimals, every phase > 0; the phases are disjoint parts of the total that cover
    it: sum <= total + 0.01 and >= total - max(5 ms, 1 % of total); total <= UCFS-import-ucfs-ms + 1.5
    and >= UCFS-import-ucfs-ms - max(5 ms, 1 %)."""
    probs = []
    names = [k for k, _ in pairs if k.startswith("UCFS-phase-")]
    want = ["UCFS-phase-%s-ms" % p for p in PHASES + [PHASE_TOTAL]]
    if names != want:
        return ["phase lines %s, expected %s" % (names, want)]
    keys = [k for k, _ in pairs]
    if "UCFS-import-ucfs-ms" not in keys or keys.index("UCFS-import-ucfs-ms") > keys.index(want[0]):
        probs.append("phase lines do not follow #UCFS-import-ucfs-ms")
        return probs
    d = dict(pairs)
    vals = {}
    for k in want:
        if not re.fullmatch(r"\d+\.\d{3}", d[k]):
            probs.append("%s: %r is not a number with three decimals" % (k, d[k]))
            return probs
        vals[k] = float(d[k])
    zero = [p for p in PHASES if vals["UCFS-phase-%s-ms" % p] <= 0]
    if zero:
        probs.append("phases %s are 0.000 (not timed)" % zero)
    s = sum(vals["UCFS-phase-%s-ms" % p] for p in PHASES)
    tot = vals["UCFS-phase-total-ms"]
    if s > tot + 0.01:
        probs.append("sum of phases %.3f > total %.3f" % (s, tot))
    if s < tot - phase_tol(tot):
        probs.append("sum of phases %.3f < total %.3f - max(5, 1%%)" % (s, tot))
    ucfs = float(d["UCFS-import-ucfs-ms"])
    if tot > ucfs + 1.5:
        probs.append("total %.3f > UCFS-import-ucfs-ms %s + 1.5" % (tot, d["UCFS-import-ucfs-ms"]))
    if tot < ucfs - phase_tol(ucfs):
        probs.append("total %.3f < UCFS-import-ucfs-ms %s - max(5, 1%%)" % (tot, d["UCFS-import-ucfs-ms"]))
    return probs


def time_problems(run, kv, wall_s):
    """Internal consistency of the times of one ok run (E5.md D14): qilin-pta-s <= qilin-main-pta-s <=
    wall_s (+ 0.05 s rounding); for a ucfs run UCFS-import-spark-ms + UCFS-import-ucfs-ms <= 1000 *
    qilin-pta-s + 2 (the Spark kernel and the UCFS part are inside pureRun, which the evaluator times);
    the phases as in phase_problems."""
    d = dict(kv)
    probs = []
    try:
        pta, main = float(d["qilin-pta-s"]), float(d["qilin-main-pta-s"])
    except (KeyError, ValueError):
        return ["no qilin-pta-s / qilin-main-pta-s"]
    if not pta <= main + 0.001:
        probs.append("qilin-pta-s %s > qilin-main-pta-s %s" % (d["qilin-pta-s"], d["qilin-main-pta-s"]))
    if not main <= wall_s + 0.05:
        probs.append("qilin-main-pta-s %s > wall_s %.2f" % (d["qilin-main-pta-s"], wall_s))
    if run != "insens":
        try:
            k, u = float(d["UCFS-import-spark-ms"]), float(d["UCFS-import-ucfs-ms"])
        except (KeyError, ValueError):
            return probs + ["no UCFS-import-spark-ms / -ucfs-ms"]
        if k + u > 1000.0 * pta + 2:
            probs.append("kernel %s + UCFS %s ms > 1000 * qilin-pta-s %s + 2" % (d["UCFS-import-spark-ms"],
                                                                               d["UCFS-import-ucfs-ms"], d["qilin-pta-s"]))
        probs += phase_problems(kv)
    return probs


def bench_map(root):
    """{name: {apppath, libpath, mainclass, refl, jre}} of artifact/util/benchmark.py of the repository at root."""
    m = runpy.run_path(os.path.join(root, "artifact", "util", "benchmark.py"))
    res = {}
    for b in m["BENCHMARKS"]:
        res[b] = {"apppath": m["APPPATH"][b], "libpath": m["LIBPATH"].get(b), "mainclass": m["MAINCLASSES"][b],
                  "refl": m["TAMIFLEXLOG"][b], "jre": "benchmarks/JREs/" + m["JREVERSION"][b]}
    return res


def expected_cmd(java, jar, xmx, run, bench, clone, bmap, jdk_bodies=False):
    """The command line of one run (E5-S2), as a token list: <java> -Xmx<xmx> -XX:+ExitOnOutOfMemoryError
    -jar <jar> -pae -pe -clinit=ONFLY -lcs -mh <run options> -apppath <a> [-libpath <l>] -mainclass <m>
    -reflectionlog <r> -jre=<j> -ucfsseam [-exclude=<JDK list>]; the paths of the benchmark are
    <clone>/artifact/<path of artifact/util/benchmark.py>."""
    a = clone.rstrip("/") + "/artifact/"
    b = bmap[bench]
    opts = ["-pta=insens"] if run == "insens" else ["-pta=ucfs", "-ucfsbinding=" + run[len("ucfs-"):]]
    t = [java, "-Xmx" + xmx] + JVM_FLAGS + ["-jar", jar] + RUNPY_OPTS + opts + ["-apppath", a + b["apppath"]]
    if b["libpath"]:
        t += ["-libpath", a + b["libpath"]]
    t += ["-mainclass", b["mainclass"], "-reflectionlog", a + b["refl"], "-jre=" + a + b["jre"], "-ucfsseam"]
    if not jdk_bodies:
        t.append("-exclude=" + JDK_EXCLUDE)
    return t


def cmd_tokens(d):
    """Tokens of <d>/cmd.txt, a bash-quoted command line (printf %q), or None."""
    t = read(os.path.join(d, "cmd.txt"))
    if t is None:
        return None
    try:
        return shlex.split(t)
    except ValueError:
        return None


def cmd_problem(got, want):
    """'' when the token lists are equal, else a short description of the first difference."""
    if got == want:
        return ""
    if got is None:
        return "cmd.txt missing or not a quoted command line"
    for i, (g, w) in enumerate(zip(got, want)):
        if g != w:
            return "token %d is %r, expected %r" % (i, g, w)
    return "%d tokens, expected %d (extra %s, missing %s)" % (len(got), len(want), got[len(want):][:3],
                                                              want[len(got):][:3])


def run_order(benches, runs, reps, warmup, skip):
    """[(rep, bench, run)] of e5-bench.sh (E5-S2): repetitions (0 when warmup, then 1 ... reps), inside each
    the benchmarks in the given order, inside each the runs of RUNS rotated left by the repetition number
    (rep k starts with runs[k mod n]); pairs of skip are left out."""
    res = []
    n = len(runs)
    for k in range(0 if warmup else 1, reps + 1):
        rot = runs[k % n:] + runs[:k % n]
        for b in benches:
            for r in rot:
                if (b, r) not in skip:
                    res.append((k, b, r))
    return res


def parse_skip(s):
    return set(tuple(x.split(":", 1)) for x in (s or "").split())


def quartiles(xs):
    """(q1, median, q3) with statistics.quantiles(method="inclusive"); one value -> (x, x, x)."""
    xs = sorted(xs)
    if len(xs) == 1:
        return xs[0], xs[0], xs[0]
    q = statistics.quantiles(xs, n=4, method="inclusive")
    return q[0], q[1], q[2]


def _binom_cdf(k, n):
    return sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n


def median_ci(xs, level=0.95):
    """Distribution-free confidence interval of the median: (x_(j), x_(n-j+1)) for the largest j with
    coverage 1 - 2 P(B <= j-1) >= level, B ~ Binomial(n, 1/2); None when even (min, max) does not reach
    the level (n <= 5 for 95 %). Returns (lo, hi, coverage)."""
    xs = sorted(xs)
    n = len(xs)
    best = None
    for j in range(1, n // 2 + 1):
        cov = 1 - 2 * _binom_cdf(j - 1, n)
        if cov >= level:
            best = (xs[j - 1], xs[n - j], cov)
    return best


def fmt(x, digits):
    return ("%." + str(digits) + "f") % x


def replay_minheap(steps, lo_mb=64, hi_mb=16384, gran_mb=16, confirm_mb=CONFIRM_MB):
    """Replays the search of scripts/ucfs/e5-minheap.sh (E5-S3) on the steps.tsv rows of one (bench, run),
    in step order. Returns (problems, status, minheap, maxfail).
    Rule: step 0 at hi_mb is the reference; not ok -> status ref-<status>, no other step. Every later step
    whose status is error is repeated once at the same -Xmx; a second error ends the search with status
    error (an error says nothing about the heap, so it never moves a bound). Step at lo_mb: ok -> le-lo.
    Then mid = (lo + hi) // 2 while hi - lo > gran_mb: ok -> hi = mid, otherwise (oom, timeout, killed,
    differs) lo = mid. Then two confirmation steps: at hi + confirm_mb (must be ok) and at lo - confirm_mb
    (must not be ok); status ok when both hold, else unconfirmed. minheap = hi, maxfail = lo."""
    probs = []
    if not steps or [int(s["step"]) for s in steps] != list(range(len(steps))):
        return ["steps not numbered 0.."], None, None, None
    xs = [int(s["xmx_mb"]) for s in steps]
    st = [s["status"] for s in steps]
    if xs[0] != hi_mb:
        probs.append("step 0 at %d MB, expected %d" % (xs[0], hi_mb))
    if st[0] != "ok":
        if len(steps) != 1:
            probs.append("steps after a failed reference")
        return probs, "ref-" + st[0], None, None
    pos = [1]

    def take(mb):
        """status of the step at mb (with its one repeat after an error); None if the steps do not match."""
        k = pos[0]
        if k >= len(steps) or xs[k] != mb:
            probs.append("step %d at %s MB, expected %d" % (k, xs[k] if k < len(steps) else "-", mb))
            return None
        pos[0] += 1
        if st[k] != "error":
            return st[k]
        if pos[0] >= len(steps) or xs[pos[0]] != mb:
            probs.append("step %d (error at %d MB) is not repeated" % (k, mb))
            return None
        pos[0] += 1
        return st[k + 1]

    def end(status, hi, lo):
        if pos[0] != len(steps):
            probs.append("%d steps after the end of the search" % (len(steps) - pos[0]))
        return probs, status, hi, lo

    s1 = take(lo_mb)
    if s1 is None:
        return probs, None, None, None
    if s1 == "error":
        return end("error", None, None)
    if s1 == "ok":
        return end("le-lo", lo_mb, None)
    lo, hi = lo_mb, hi_mb
    while hi - lo > gran_mb:
        mid = (lo + hi) // 2
        s = take(mid)
        if s is None:
            return probs, None, None, None
        if s == "error":
            return end("error", None, None)
        if s == "ok":
            hi = mid
        else:
            lo = mid
    c1 = take(hi + confirm_mb)
    if c1 is None:
        return probs, None, None, None
    if c1 == "error":
        return end("error", None, None)
    c2 = take(lo - confirm_mb)
    if c2 is None:
        return probs, None, None, None
    if c2 == "error":
        return end("error", None, None)
    return end("ok" if c1 == "ok" and c2 != "ok" else "unconfirmed", hi, lo)


def minheap_plausibility(rows):
    """Problems of the minheap.tsv rows with status ok (E5-S3, E5-S5b): minheap_mb <= ref_rss_mb (the run
    at the reference heap touched at least the minimum heap) and, per benchmark, the minimum heap of
    every ucfs run >= that of insens - CONFIRM_MB (a ucfs run solves Spark first and keeps its state)."""
    probs = []
    ok = {(r["bench"], r["run"]): r for r in rows if r["status"] == "ok"}
    for (b, run), r in ok.items():
        if int(r["minheap_mb"]) > int(r["ref_rss_mb"]):
            probs.append("%s %s: minheap %s MB > RSS %s MB of the reference" % (b, run, r["minheap_mb"], r["ref_rss_mb"]))
        base = ok.get((b, "insens"))
        if run != "insens" and base and int(r["minheap_mb"]) < int(base["minheap_mb"]) - CONFIRM_MB:
            probs.append("%s %s: minheap %s MB < insens %s MB - %d" % (b, run, r["minheap_mb"], base["minheap_mb"],
                                                                      CONFIRM_MB))
    return probs


def iso_epoch(s):
    """Seconds since the epoch of a date -Iseconds string (with its offset)."""
    return datetime.datetime.fromisoformat(s.strip()).timestamp()


def interval_problems(items, tol_s=0.05):
    """items = [(label, start_ns, end_ns, wall_s)] in the order the runs must have run. Problems: start or end
    missing, end <= start, the wall time of GNU time longer than end - start (+ tol_s), a run that starts
    before the previous one ended (overlap or another order)."""
    probs = []
    prev = None
    for label, a, z, w in items:
        if a is None or z is None:
            probs.append("%s: start/end missing" % label)
            continue
        if z <= a:
            probs.append("%s: end %d <= start %d" % (label, z, a))
        if w is not None and w > (z - a) / 1e9 + tol_s:
            probs.append("%s: wall_s %.2f > end - start %.3f s" % (label, w, (z - a) / 1e9))
        if prev is not None and a < prev[2]:
            probs.append("%s starts before %s ended (overlap or order)" % (label, prev[0]))
        prev = (label, a, z)
    return probs


# --- secrets (E5-S5a, E5-S5b): what must not appear in committed results ------------------------------
_IPV4 = re.compile(r"(?<![\w.+-])((?:\d{1,3}\.){3}\d{1,3})(?![\w+-]|\.\w)")
SECRET_RX = [
    ("bearer token", re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{8,}")),
    ("authorization header", re.compile(r"(?i)\bauthorization\s*:")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("ssh key", re.compile(r"\bssh-(?:ed25519|rsa|dss|ecdsa\S*) AAAA")),
    ("credential word", re.compile(r"(?i)\b(?:key_?id|secret|client_secret|access_?key|api_?key|password|passwd)\b")),
    ("uuid", re.compile(r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")),
]


def secret_hits(text):
    """[(kind, match)] of the secret patterns in text: an IPv4 address other than 127.x.x.x and 10.x.x.x
    (a dotted quad inside a version such as 21.0.12.1+1 or after 'version "' is not an address), a bearer token, an
    Authorization header, a private key, an SSH public key, a credential word (keyId, secret, password,
    ...) and a UUID (the ids of Cloud.ru resources)."""
    hits = []
    for m in _IPV4.finditer(text):
        q = [int(x) for x in m.group(1).split(".")]
        if text[max(0, m.start() - 9):m.start()] == 'version "':
            continue  # java -version: openjdk version "21.0.12.1"
        if max(q) <= 255 and q[0] not in (127, 10):
            hits.append(("ipv4", m.group(1)))
    for kind, rx in SECRET_RX:
        for m in rx.finditer(text):
            hits.append((kind, m.group(0)[:40]))
    return hits


def scan_paths(paths):
    """[(file, kind, match)] of secret_hits over the files under paths (directories are walked) and over
    every member file of the tar archives among them (*.tar.xz, *.tar.gz, *.tar)."""
    res = []

    def scan_bytes(name, data):
        for kind, s in secret_hits(data.decode("utf-8", "replace")):
            res.append((name, kind, s))

    files = []
    for p in paths:
        if os.path.isdir(p):
            for dp, dn, fn in os.walk(p):
                dn.sort()
                files += [os.path.join(dp, f) for f in sorted(fn)]
        elif os.path.isfile(p):
            files.append(p)
    for f in files:
        if re.search(r"\.tar(\.xz|\.gz)?$", f):
            try:
                with tarfile.open(f) as t:
                    for m in t.getmembers():
                        if m.isfile():
                            scan_bytes("%s!%s" % (f, m.name), t.extractfile(m).read())
            except (tarfile.TarError, OSError) as e:
                res.append((f, "unreadable archive", str(e)[:40]))
        else:
            with open(f, "rb") as fh:
                scan_bytes(f, fh.read())
    return res
