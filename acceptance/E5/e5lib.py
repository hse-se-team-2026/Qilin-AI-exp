"""Helpers of the E5 acceptance checks and of e5tables.py (python3 standard library only).

The E5 contracts (docs/ai/tickets/E5.md and E5-S1 ... E5-S6) that the checks share:
- a measurement key ends in -ms, -s or -mb (MEASURE); every other key of a run is an answer key;
- the output of one Qilin run is parsed by parse_out(): every line "#<key>: <value>" (one token value,
  the rule of scripts/ucfs/e4-bench.sh) and three lines of Qilin without '#', under fixed key names;
- the phases of the UCFS part of -pta=ucfs are printed as "#UCFS-phase-<p>-ms: <ms with 3 decimals>"
  for p in PHASES, then the total (E5-S1);
- statistics: median, quartiles (method "inclusive" of statistics.quantiles), and the distribution-free
  confidence interval of the median from order statistics (median_ci).
This module is written independently of the scripts it checks (scripts/ucfs/e5-*.sh).
"""
import csv
import math
import os
import re
import statistics

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
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan",
           "checkstyle", "findbugs", "JPC"]
COVERED = ["antlr", "bloat", "chart", "fop", "luindex", "lusearch"]
DEFAULT_SKIP = [("antlr", "ucfs-CALL_GRAPH"), ("bloat", "ucfs-CALL_GRAPH"), ("checkstyle", "ucfs-CALL_GRAPH")]
# prefixes of the E4 keys that come from -ucfscompare and -ucfspt, which the E5 runs do not pass
E4_ONLY = ("UCFS-cmp-", "UCFS-pt-", "cmp/")


def is_measure(key):
    return bool(MEASURE.search(key))


def read_tsv(path):
    """Rows of a TSV file with a header line, as dicts (values are strings)."""
    with open(path, newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def read_meta(path):
    return {r["key"]: r["value"] for r in read_tsv(path)}


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


def phase_problems(pairs):
    """Problems of the #UCFS-phase- lines of one -pta=ucfs run ([(key, value)] of parse_out); [] = fine.
    Contract (E5-S1): each of PHASES and then total once, in this order, after #UCFS-import-ucfs-ms;
    values with three decimals, >= 0; the sum of the phases <= total + 0.01 and >= total - max(5 ms,
    5 % of total) (the phases are disjoint parts of the total); total <= UCFS-import-ucfs-ms + 1.5."""
    probs = []
    names = [k for k, _ in pairs if k.startswith("UCFS-phase-")]
    want = ["UCFS-phase-%s-ms" % p for p in PHASES + [PHASE_TOTAL]]
    if names != want:
        return ["phase lines %s, expected %s" % (names, want)]
    keys = [k for k, _ in pairs]
    if "UCFS-import-ucfs-ms" not in keys or keys.index("UCFS-import-ucfs-ms") > keys.index(want[0]):
        probs.append("phase lines do not follow #UCFS-import-ucfs-ms")
    d = dict(pairs)
    vals = {}
    for k in want:
        if not re.fullmatch(r"\d+\.\d{3}", d[k]):
            probs.append("%s: %r is not a number with three decimals" % (k, d[k]))
            return probs
        vals[k] = float(d[k])
    s = sum(vals["UCFS-phase-%s-ms" % p] for p in PHASES)
    tot = vals["UCFS-phase-total-ms"]
    if s > tot + 0.01:
        probs.append("sum of phases %.3f > total %.3f" % (s, tot))
    if s < tot - max(5.0, 0.05 * tot):
        probs.append("sum of phases %.3f < total %.3f - max(5, 5%%)" % (s, tot))
    ucfs = float(d["UCFS-import-ucfs-ms"])
    if tot > ucfs + 1.5:
        probs.append("total %.3f > UCFS-import-ucfs-ms %s + 1.5" % (tot, d["UCFS-import-ucfs-ms"]))
    if tot < ucfs - max(5.0, 0.05 * ucfs):
        probs.append("total %.3f < UCFS-import-ucfs-ms %s - max(5, 5%%)" % (tot, d["UCFS-import-ucfs-ms"]))
    return probs


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


def replay_minheap(steps, lo_mb=64, hi_mb=16384, gran_mb=16):
    """Replays the search of scripts/ucfs/e5-minheap.sh (E5-S3) on the steps.tsv rows of one (bench, run),
    in step order. Returns (problems, status, minheap, maxfail): step 0 at hi_mb; if it is not ok the status is
    ref-<status>; step 1 at lo_mb (ok -> le-lo); then mid = (lo + hi) // 2 while hi - lo > gran_mb, hi = mid
    after an ok step, lo = mid otherwise."""
    probs = []
    if [int(s["step"]) for s in steps] != list(range(len(steps))) or not steps:
        return ["steps not numbered 0.."], None, None, None
    if int(steps[0]["xmx_mb"]) != hi_mb:
        probs.append("step 0 at %s MB, expected %d" % (steps[0]["xmx_mb"], hi_mb))
    if steps[0]["status"] != "ok":
        if len(steps) != 1:
            probs.append("steps after a failed reference")
        return probs, "ref-" + steps[0]["status"], None, None
    if len(steps) < 2 or int(steps[1]["xmx_mb"]) != lo_mb:
        return probs + ["step 1 is not at %d MB" % lo_mb], None, None, None
    if steps[1]["status"] == "ok":
        if len(steps) != 2:
            probs.append("steps after an ok run at LO_MB")
        return probs, "le-lo", lo_mb, None
    lo, hi, exp, k = lo_mb, hi_mb, [], 2
    while hi - lo > gran_mb:
        mid = (lo + hi) // 2
        exp.append(mid)
        if k >= len(steps) or int(steps[k]["xmx_mb"]) != mid:
            break
        if steps[k]["status"] == "ok":
            hi = mid
        else:
            lo = mid
        k += 1
    got = [int(s["xmx_mb"]) for s in steps[2:]]
    if got != exp or hi - lo > gran_mb:
        probs.append("bisection %s, expected %s" % (got, exp))
    return probs, "ok", hi, lo
