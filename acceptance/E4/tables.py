#!/usr/bin/env python3
"""Tables of the E4 comparison document, made from the result files of scripts/ucfs/e4-bench.sh
(E4-S6, docs/ai/tickets/E4-S6.md). The document must contain each table verbatim; doc_check.py
regenerates them from the committed results and compares.

Usage: python3 acceptance/E4/tables.py <results-dir with runs.tsv and values.tsv> [T1|T2|T3|T4]
Prints the markdown tables (all four, each after a line "<!-- E4 table Tn -->", or the one asked for).

T1  size and time: global PAG edges of Spark (sum of the four #UCFS-seam- counts of the insens run),
    vertices/edges/fields of the UCFS graph (ANALYSIS), wall time and peak RSS of each run, UCFS time
    (#UCFS-import-ucfs-ms) of the ucfs runs; one run each (single measurements, E5 repeats them).
T2  Qilin metrics per view (SPARK, UCFS, UCFS_TYPED) from ucfs-compare/metrics.tsv: reachable methods,
    call edges and polymorphic call sites (one value: the call graph is Spark's in every view, a cell
    "differs" if the views disagree), may-fail casts and average points-to (3 decimals).
T3  pairs (variable, object): Spark, UCFS (with ROOT), UCFS_TYPED and the classes of UcfsCompare.
T4  one step of dispatch: Spark's call edges at the recorded instance sites, edges found over SPARK,
    new edges over UCFS, UCFS_TYPED, SPARK.
A run that did not finish shows its status (timeout, error) in its cells.
"""
import os
import sys

RUNS = ["ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]


def load(d):
    runs, vals = {}, {}
    for l in open(os.path.join(d, "runs.tsv")):
        f = l.rstrip("\n").split("\t")
        if f[0] != "bench" and len(f) == 6:
            runs[(f[0], f[1])] = f
    for l in open(os.path.join(d, "values.tsv")):
        f = l.rstrip("\n").split("\t")
        if f[0] != "bench" and len(f) == 4:
            vals[(f[0], f[1], f[2])] = f[3]
    return runs, vals


def benches(runs):
    order = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan", "checkstyle",
             "findbugs", "JPC"]
    present = {b for b, _ in runs}
    return [b for b in order if b in present] + sorted(present - set(order))


def status(runs, b, r):
    f = runs.get((b, r))
    return f[2] if f else "-"


def table(header, rows):
    out = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)


def t1(runs, vals):
    rows = []
    for b in benches(runs):
        g = lambda r, k: vals.get((b, r, k), "-")
        try:
            pag = str(sum(int(vals[(b, "insens", "UCFS-seam-" + k)]) for k in ["NEW", "ASSIGN", "LOAD", "STORE"]))
        except KeyError:
            pag = "-"
        row = [b, pag]
        a = "ucfs-ANALYSIS"
        row.append("%s/%s/%s" % (g(a, "UCFS-pt-vertices"), g(a, "UCFS-pt-edges"), g(a, "UCFS-pt-fields"))
                   if status(runs, b, a) == "ok" else status(runs, b, a))
        for r in ["insens"] + RUNS:
            st = status(runs, b, r)
            f = runs.get((b, r))
            if st == "ok":
                cell = "%s s, %s MB" % (f[4], f[5])
                if r != "insens":
                    cell += ", UCFS %s ms" % g(r, "UCFS-import-ucfs-ms")
            else:
                cell = "%s (%s s, %s MB)" % (st, f[4], f[5]) if f else "-"
            row.append(cell)
        rows.append(row)
    return table(["bench", "PAG edges", "UCFS graph V/E/fields", "insens", "ucfs ANALYSIS", "ucfs CALL_GRAPH"], rows)


def num(x, avg=False):
    if x is None:
        return "-"
    return ("%.3f" % float(x)) if avg else x


def t2(runs, vals):
    rows = []
    for b in benches(runs):
        for r in RUNS:
            st = status(runs, b, r)
            if st != "ok":
                rows.append([b, r[5:], st] + ["-"] * 8)
                continue
            g = lambda v, m: vals.get((b, r, "cmp/%s/%s" % (v, m)))
            row = [b, r[5:]]
            for m in ["Reachable Method (CI)", "Call Edge(CI)", "Virtual Call Site(Polymorphic)"]:
                xs = {g(v, m) for v in ["SPARK", "UCFS", "UCFS_TYPED"]}
                row.append(xs.pop() if len(xs) == 1 else "differs")
            for v in ["SPARK", "UCFS", "UCFS_TYPED"]:
                row.append(num(g(v, "May Fail Cast (Total)")))
            for v in ["SPARK", "UCFS", "UCFS_TYPED"]:
                row.append(num(g(v, "Avg Points-to Target without Native Var(CI)"), True))
            rows.append(row)
    return table(["bench", "binding", "reach", "call edges", "poly", "may-fail S", "may-fail U", "may-fail T",
                  "avg pts S", "avg pts U", "avg pts T"], rows)


def t3(runs, vals):
    keys = ["spark-pairs", "ucfs-pairs", "typed-pairs", "SAME", "R3", "R4b", "R1", "R2", "R5", "UNEXPLAINED", "MISSING"]
    rows = []
    for b in benches(runs):
        for r in RUNS:
            st = status(runs, b, r)
            if st != "ok":
                rows.append([b, r[5:]] + [st] + ["-"] * (len(keys) - 1))
                continue
            rows.append([b, r[5:]] + [vals.get((b, r, "UCFS-cmp-" + k), "-") for k in keys])
    return table(["bench", "binding", "Spark", "UCFS", "UCFS_TYPED", "SAME", "R3", "R4b", "R1", "R2", "R5",
                  "UNEXPLAINED", "MISSING"], rows)


def t4(runs, vals):
    keys = ["cg-edges", "edges-SPARK", "new-edges-UCFS", "new-edges-UCFS_TYPED", "new-edges-SPARK"]
    rows = []
    for b in benches(runs):
        for r in RUNS:
            st = status(runs, b, r)
            if st != "ok":
                rows.append([b, r[5:], st] + ["-"] * (len(keys) - 1))
                continue
            rows.append([b, r[5:]] + [vals.get((b, r, "UCFS-cmp-dispatch-" + k), "-") for k in keys])
    return table(["bench", "binding", "CG edges at sites", "found over SPARK", "new over UCFS",
                  "new over UCFS_TYPED", "new over SPARK"], rows)


TABLES = {"T1": t1, "T2": t2, "T3": t3, "T4": t4}


def render(d, which=None):
    runs, vals = load(d)
    names = [which] if which else list(TABLES)
    return {n: TABLES[n](runs, vals) for n in names}


if __name__ == "__main__":
    which = sys.argv[2] if len(sys.argv) > 2 else None
    for n, t in render(sys.argv[1], which).items():
        print("<!-- E4 table %s -->" % n)
        print(t)
        print()
