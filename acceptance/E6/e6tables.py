#!/usr/bin/env python3
"""Table T1 of the E6 feasibility probe (docs/ai/tickets/E6-S6.md, E6-S7.md) from the committed results.

Usage: python3 acceptance/E6/e6tables.py <e6-results-dir>
Reads <dir>/runs.tsv (bench mode grammar status exit wall_s max_rss_mb) and <dir>/values.tsv
(bench mode grammar key value; keys without the leading '#') and prints one markdown table, one row per
run in the order of runs.tsv: bench | mode | grammar | status | wall_s | max_rss_mb | vertices | edges |
sites | fields | pt-under | pt-over ("-" where the run printed no value).
"""
import os
import sys

d = sys.argv[1]
runs = [l.split("\t") for l in open(os.path.join(d, "runs.tsv")).read().strip().split("\n")]
head, runs = runs[0], runs[1:]
vals = {}
for l in open(os.path.join(d, "values.tsv")).read().strip().split("\n")[1:]:
    b, m, g, k, v = l.split("\t")
    vals[(b, m, g, k)] = v
keys = ["CFLIDR-vertices", "CFLIDR-edges", "CFLIDR-sites", "CFLIDR-fields", "CFLIDR-pt-under", "CFLIDR-pt-over"]
cols = ["bench", "mode", "grammar", "status", "wall_s", "max_rss_mb", "vertices", "edges", "sites", "fields",
        "pt-under", "pt-over"]
print("| " + " | ".join(cols) + " |")
print("|" + "---|" * len(cols))
ix = {h: i for i, h in enumerate(head)}
for r in runs:
    b, m, g = r[ix["bench"]], r[ix["mode"]], r[ix["grammar"]]
    cells = [b, m, g, r[ix["status"]], r[ix["wall_s"]], r[ix["max_rss_mb"]]] + [vals.get((b, m, g, k), "-") for k in keys]
    print("| " + " | ".join(cells) + " |")
