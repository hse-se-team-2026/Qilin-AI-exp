#!/usr/bin/env python3
"""Tables of the E5 benchmark document (docs/ucfs-integration/e5-benchmarks.md), made from the E5 result
files (docs/ucfs-integration/e5-results/, E5-S5) and the committed E4 results (sizes and coverage).
The document must contain each table verbatim; doc_check.py regenerates them and compares.

Usage: python3 acceptance/E5/e5tables.py <e5-results-dir> [<e4-results-dir>] [T1 ... T8]
  <e5-results-dir> holds bench/, minheap/, probe-cg/, probe-jdk/ (scripts/ucfs/e5-full.sh); a missing part
  gives a table with "-" cells. <e4-results-dir> defaults to docs/ucfs-integration/e4-results.
Prints each table after a line "<!-- E5 table Tn -->" (all eight, or the ones asked for).

Statistics are over the measured repetitions (rep >= 1; rep 0 is the warm-up) with status ok:
  median, quartiles q1/q3 of statistics.quantiles(method="inclusive"), IQR = q3 - q1, CV = population
  standard deviation / mean, and the distribution-free 95 % confidence interval of the median from order
  statistics (e5lib.median_ci; with 10 repetitions it is [x(2), x(9)], coverage 97.9 %; "-" for n <= 5).
  Times in ms are printed as integers, seconds with 2 decimals, ratios with 2 decimals.

T1  host and configuration of the bench part: the keys of bench/meta.tsv that describe the host and the run.
T2  sizes (from the E4 results, same answer as E5, checked by E5-S2/S5): D3 coverage % and "covered"
    (acceptance/E4/tables.py), Spark's global PAG edges (sum of #UCFS-seam-), edges and fields of the UCFS
    graph per binding (#UCFS-pt-edges/-fields), UCFS pairs (#UCFS-import-pairs) per binding.
T3  time, UCFS against Spark, per benchmark and binding: n = measured ok repetitions of the ucfs run;
    Spark = the solve of the Spark run (-pta=insens, "Time (sec)" of Qilin, qilin-pta-s, in ms);
    kernel = the Spark kernel inside the ucfs run (UCFS-import-spark-ms); UCFS = UCFS-import-ucfs-ms;
    UCFS/Spark = median of the per-repetition ratios UCFS_k / Spark_k (same repetition k, runs one after
    the other) with its CI; wall = median wall time of the insens and the ucfs run (s).
T4  phases of UCFS (E5-S1), medians in ms with 1 decimal: export grammar rsm input parse roots pairs import,
    total, and parse share = median of parse_k / total_k in percent (1 decimal).
T5  spread of time, per benchmark and run: n, wall median / min / max / IQR / CV %, and the same for the
    analysis time (insens: qilin-pta-s in ms; ucfs: UCFS-import-ucfs-ms), max load1 before the runs.
T6  memory: max RSS (GNU time) median and min-max (MB), Qilin's sampled RSS of the PTA (qilin-main-pta-rss-mb,
    median), and the minimum heap of minheap/minheap.tsv (MB; status when not ok), and for the ucfs runs
    the minimum heap minus that of insens.
T7  stability of the answer: answer keys (not -ms/-s/-mb) per run, how many of them take more than one value
    over the measured repetitions (and which), and how many equal the committed E4 value in every repetition.
T8  probes beyond the main budget: probe-cg and probe-jdk runs (status, wall s, max RSS MB, UCFS ms, UCFS
    pairs, -Xmx, timeout s, JDK bodies).
A (bench, run) that has no ok measured repetition shows the statuses of its rows ("timeout x10", "skipped").
"""
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "E4"))
import e5lib  # noqa: E402
import tables as e4tables  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BINDINGS = ["ANALYSIS", "CALL_GRAPH"]


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


class Part:
    """runs.tsv, values.tsv and meta.tsv of one e5-bench.sh output directory (empty if missing)."""

    def __init__(self, d):
        self.ok = os.path.isfile(os.path.join(d, "runs.tsv"))
        self.runs = e5lib.read_tsv(os.path.join(d, "runs.tsv")) if self.ok else []
        self.vals = e5lib.read_tsv(os.path.join(d, "values.tsv")) if self.ok else []
        self.meta = e5lib.read_meta(os.path.join(d, "meta.tsv")) if os.path.isfile(os.path.join(d, "meta.tsv")) else {}
        self.v = {}
        for r in self.vals:
            self.v.setdefault((r["bench"], r["run"], r["rep"]), {})[r["key"]] = r["value"]

    def measured(self, b, run):
        """rows of the measured repetitions (rep >= 1) of (b, run)."""
        return [r for r in self.runs if r["bench"] == b and r["run"] == run and int(r["rep"]) >= 1]

    def okreps(self, b, run):
        return [r["rep"] for r in self.measured(b, run) if r["status"] == "ok"]

    def series(self, b, run, key, scale=1.0, reps=None):
        reps = self.okreps(b, run) if reps is None else reps
        xs = []
        for k in reps:
            v = self.v.get((b, run, k), {}).get(key)
            if v is not None:
                xs.append(float(v) * scale)
        return xs

    def wall(self, b, run):
        return [float(r["wall_s"]) for r in self.measured(b, run) if r["status"] == "ok"]

    def statuses(self, b, run):
        rows = self.measured(b, run)
        if not rows:
            skip = self.meta.get("skip", "").split()
            return "skipped" if "%s:%s" % (b, run) in skip else "-"
        c = {}
        for r in rows:
            c[r["status"]] = c.get(r["status"], 0) + 1
        return ", ".join("%s x%d" % (s, n) for s, n in sorted(c.items()))

    def benches(self):
        have = {r["bench"] for r in self.runs}
        return [b for b in e5lib.BENCHES if b in have]


def med(xs, digits=0):
    if not xs:
        return "-"
    return e5lib.fmt(statistics.median(xs), digits)


def med_ci(xs, digits=0):
    if not xs:
        return "-"
    ci = e5lib.median_ci(xs)
    m = e5lib.fmt(statistics.median(xs), digits)
    return m if ci is None else "%s [%s, %s]" % (m, e5lib.fmt(ci[0], digits), e5lib.fmt(ci[1], digits))


def t1(bench):
    keys = ["host-kind", "flavor", "cpu-model", "cpu-count", "mem-total-mb", "kernel", "os", "java-version",
            "jvm-flags", "xmx", "timeout", "reps", "warmup", "skip", "other-java", "git-head", "started", "finished"]
    return table(["key", "value"], [[k, bench.meta.get(k, "-") or "-"] for k in keys])


def t2(e4dir, bench):
    runs, vals = e4tables.load(e4dir)
    rows = []
    for b in e5lib.BENCHES:
        cov = e4tables.coverage(runs, vals, b)
        seam = sum(int(vals.get((b, "insens", "UCFS-seam-" + k), 0)) for k in ("NEW", "ASSIGN", "LOAD", "STORE"))
        row = [b, "-" if cov is None else "%.1f" % cov, "yes" if cov is not None and cov >= e4tables.COVERED_PCT else "no",
               seam]
        for B in BINDINGS:
            r = "ucfs-" + B
            row += [vals.get((b, r, "UCFS-pt-edges"), "-"), vals.get((b, r, "UCFS-pt-fields"), "-"),
                    vals.get((b, r, "UCFS-import-pairs"), "-")]
        rows.append(row)
    return table(["bench", "coverage %", "covered", "PAG edges", "edges AN", "fields AN", "pairs AN",
                  "edges CG", "fields CG", "pairs CG"], rows)


def t3(bench):
    rows = []
    for b in bench.benches():
        sp_reps = set(bench.okreps(b, "insens"))
        for B in BINDINGS:
            run = "ucfs-" + B
            reps = bench.okreps(b, run)
            if not reps:
                rows.append([b, B, 0, med_ci(bench.series(b, "insens", "qilin-pta-s", 1000.0)), bench.statuses(b, run),
                             "-", "-", med(bench.wall(b, "insens"), 2), "-"])
                continue
            ratios = []
            for k in reps:
                if k in sp_reps:
                    u = float(bench.v[(b, run, k)]["UCFS-import-ucfs-ms"])
                    s = float(bench.v[(b, "insens", k)]["qilin-pta-s"]) * 1000.0
                    if s > 0:
                        ratios.append(u / s)
            rows.append([b, B, len(reps), med_ci(bench.series(b, "insens", "qilin-pta-s", 1000.0)),
                         med(bench.series(b, run, "UCFS-import-spark-ms")),
                         med_ci(bench.series(b, run, "UCFS-import-ucfs-ms")), med_ci(ratios, 2),
                         med(bench.wall(b, "insens"), 2), med(bench.wall(b, run), 2)])
    return table(["bench", "binding", "n", "Spark ms", "kernel ms", "UCFS ms", "UCFS/Spark", "wall insens s",
                  "wall ucfs s"], rows)


def t4(bench):
    rows = []
    for b in bench.benches():
        for B in BINDINGS:
            run = "ucfs-" + B
            reps = bench.okreps(b, run)
            if not reps:
                rows.append([b, B, 0] + [bench.statuses(b, run)] + ["-"] * len(e5lib.PHASES) + ["-"])
                continue
            cells = [med(bench.series(b, run, "UCFS-phase-%s-ms" % p), 1) for p in e5lib.PHASES + ["total"]]
            share = []
            for k in reps:
                d = bench.v[(b, run, k)]
                t = float(d["UCFS-phase-total-ms"])
                if t > 0:
                    share.append(100.0 * float(d["UCFS-phase-parse-ms"]) / t)
            rows.append([b, B, len(reps)] + cells + [med(share, 1)])
    return table(["bench", "binding", "n"] + e5lib.PHASES + ["total", "parse %"], rows)


def spread(xs, digits):
    if not xs:
        return ["-"] * 5
    q1, _, q3 = e5lib.quartiles(xs)
    m = statistics.fmean(xs)
    cv = 100.0 * statistics.pstdev(xs) / m if m > 0 else 0.0
    return [e5lib.fmt(statistics.median(xs), digits), e5lib.fmt(min(xs), digits), e5lib.fmt(max(xs), digits),
            e5lib.fmt(q3 - q1, digits), "%.1f" % cv]


def t5(bench):
    rows = []
    for b in bench.benches():
        for run in e5lib.RUNS:
            reps = bench.okreps(b, run)
            if not reps:
                rows.append([b, run, 0, bench.statuses(b, run)] + ["-"] * 10)
                continue
            key, scale = ("qilin-pta-s", 1000.0) if run == "insens" else ("UCFS-import-ucfs-ms", 1.0)
            loads = [float(r["load1"]) for r in bench.measured(b, run) if r["status"] == "ok"]
            rows.append([b, run, len(reps)] + spread(bench.wall(b, run), 2) + spread(bench.series(b, run, key, scale), 0)
                        + ["%.2f" % max(loads)])
    return table(["bench", "run", "n", "wall med s", "wall min", "wall max", "wall IQR", "wall CV %", "time med ms",
                  "time min", "time max", "time IQR", "time CV %", "max load1"],
                 rows)


def t6(bench, minheap):
    mh = {(r["bench"], r["run"]): r for r in minheap}
    rows = []
    for b in bench.benches():
        base = mh.get((b, "insens"))
        for run in e5lib.RUNS:
            rss = [float(r["max_rss_mb"]) for r in bench.measured(b, run) if r["status"] == "ok"]
            m = mh.get((b, run))
            mcell = "-" if m is None else (m["minheap_mb"] if m["status"] == "ok" else "%s %s" % (m["status"], m["minheap_mb"]))
            diff = "-"
            if run != "insens" and m and base and m["status"] == "ok" and base["status"] == "ok":
                diff = str(int(m["minheap_mb"]) - int(base["minheap_mb"]))
            if not rss:
                rows.append([b, run, 0, bench.statuses(b, run), "-", "-", mcell, diff])
                continue
            rows.append([b, run, len(rss), med(rss), "%d-%d" % (min(rss), max(rss)),
                         med(bench.series(b, run, "qilin-main-pta-rss-mb")), mcell, diff])
    return table(["bench", "run", "n", "max RSS med MB", "max RSS min-max", "Qilin RSS med MB", "min heap MB",
                  "min heap - insens MB"], rows)


def t7(bench, e4dir):
    e4 = e5lib.e4_values(e4dir)
    rows = []
    for b in bench.benches():
        for run in e5lib.RUNS:
            reps = bench.okreps(b, run)
            if not reps:
                rows.append([b, run, 0, bench.statuses(b, run), "-", "-"])
                continue
            seen = {}
            for k in reps:
                for key, val in bench.v.get((b, run, k), {}).items():
                    if not e5lib.is_measure(key):
                        seen.setdefault(key, set()).add(val)
            ref = e5lib.e4_answer(e4, b, run)
            varying = sorted(k for k, s in seen.items() if len(s) > 1)
            same = sum(1 for k, s in seen.items() if s == {ref.get(k)})
            rows.append([b, run, len(reps), len(seen), "%d%s" % (len(varying), (": " + ", ".join(varying)) if varying else ""),
                         "%d of %d" % (same, len(seen))])
    return table(["bench", "run", "n", "answer keys", "varying", "= E4 in every rep"], rows)


def t8(probes):
    rows = []
    for name, p in probes:
        for r in p.runs:
            d = p.v.get((r["bench"], r["run"], r["rep"]), {})
            rows.append([name, r["bench"], r["run"], r["status"], r["wall_s"], r["max_rss_mb"],
                         d.get("UCFS-import-ucfs-ms", "-"), d.get("UCFS-import-pairs", "-"),
                         p.meta.get("xmx", "-"), p.meta.get("timeout", "-"), p.meta.get("jdk-bodies", "-")])
    return table(["probe", "bench", "run", "status", "wall s", "max RSS MB", "UCFS ms", "UCFS pairs", "xmx",
                  "timeout s", "JDK bodies"], rows)


def render(res, e4dir=None, which=None):
    e4dir = e4dir or os.path.join(ROOT, "docs", "ucfs-integration", "e4-results")
    bench = Part(os.path.join(res, "bench"))
    mhp = os.path.join(res, "minheap", "minheap.tsv")
    minheap = e5lib.read_tsv(mhp) if os.path.isfile(mhp) else []
    probes = [(n, Part(os.path.join(res, n))) for n in ("probe-cg", "probe-jdk")]
    make = {"T1": lambda: t1(bench), "T2": lambda: t2(e4dir, bench), "T3": lambda: t3(bench),
            "T4": lambda: t4(bench), "T5": lambda: t5(bench), "T6": lambda: t6(bench, minheap),
            "T7": lambda: t7(bench, e4dir), "T8": lambda: t8(probes)}
    return {n: "<!-- E5 table %s -->\n%s" % (n, make[n]()) for n in (which or sorted(make))}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    res = argv[1]
    rest = argv[2:]
    e4dir = None
    if rest and not rest[0].startswith("T"):
        e4dir, rest = rest[0], rest[1:]
    for t in render(res, e4dir, rest or None).values():
        print(t)
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
