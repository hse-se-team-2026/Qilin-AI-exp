#!/usr/bin/env python3
"""critic-E5 probe: how selective is the number rule of acceptance/E5/doc_check.py (E9 #41)?
Rebuilds doc_check's per-benchmark pool `known[b]` exactly as main() does (code copied from the committed
doc_check.py by exec of its source between '# --- known numbers' and 'word_re ='), on a results tree,
and prints which share of the integers 1..N would be accepted as "a value of <bench>".
Usage: python3 critic/E5/doc_pool_density.py <e5-results-dir> [N=200]"""
import os, re, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "acceptance", "E5"))
import importlib.util
import e5lib, e5tables
# load acceptance/E5/doc_check.py by path (e5tables puts acceptance/E4 first on sys.path, which has its own doc_check)
_spec = importlib.util.spec_from_file_location("e5_doc_check", os.path.join(ROOT, "acceptance", "E5", "doc_check.py"))
doc_check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(doc_check)
res = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 200
src = open(os.path.join(ROOT, "acceptance", "E5", "doc_check.py")).read()
body = src[src.index("    # --- known numbers, per benchmark"):src.index("    word_re = ")]
body = "\n".join(l[4:] for l in body.split("\n"))
ns = dict(vars(doc_check))
ns.update(bench=e5tables.Part(os.path.join(res, "bench")), res=res, rendered=e5tables.render(res))
exec(body, ns)
known = ns["known"]
for b in e5lib.BENCHES:
    hit = [i for i in range(1, N + 1) if str(i) in known[b]]
    print("%-10s %3d of %d integers 1..%d accepted (%.0f %%); 1..30 missing: %s" % (
        b, len(hit), N, N, 100.0 * len(hit) / N, [i for i in range(1, 31) if str(i) not in known[b]]))
