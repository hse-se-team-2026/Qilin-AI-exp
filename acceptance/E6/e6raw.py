#!/usr/bin/env python3
"""Tables of the E6 probe derived from its raw run files (docs/ai/tickets/E6-S6a.md, E6-S6b.md).

Usage: python3 acceptance/E6/e6raw.py <raw-dir> <out-dir> <bench:mode:grammar[:timeout_s]> ...
<raw-dir> holds, per run, <bench>/<mode>-<grammar>/{cmd.txt,out.txt,time.txt,exit,timeout} as
scripts/cflidr/e6-probe.sh writes them (and packs them into raw.tar.xz). Writes <out-dir>/runs.tsv,
values.tsv and evidence.tsv by the rules of the e6-probe.sh contract, implemented here independently of
the script, so that a check can compare them byte for byte with the tables the script wrote:
  runs.tsv      bench mode grammar timeout_s status exit wall_s max_rss_mb last_phase
  values.tsv    bench mode grammar key value     (every "#CFLIDR-<k>: <v>" line except #CFLIDR-error*)
  evidence.tsv  bench mode grammar exit status error_line wall_s out_sha256 cmd_sha256
status: ok (exit 0 and a "#CFLIDR-pt-over:" line), else sof (java.lang.StackOverflowError in out.txt),
else oom (java.lang.OutOfMemoryError), else timeout (exit 124 or 137), else error.
wall_s: "Elapsed (wall clock)" of GNU time in seconds, printed as awk prints a number (%.6g); max_rss_mb:
"Maximum resident set size" (KB) // 1024; last_phase: <p> of the last "#CFLIDR-<p>-ms:" line ("-" if
none); error_line: the first line starting with "#CFLIDR-error:" (the report of CflIdrRun), else the first
line with java.lang.StackOverflowError / java.lang.OutOfMemoryError in it (another thread, e.g. the timer of
qilin.util.MemoryWatcher, may print an OutOfMemoryError before the report), tabs as blanks, first 200 bytes
("-" if none). The timeout of a run is
the file <run>/timeout (the spec's own or TIMEOUT).
"""
import hashlib
import os
import re
import sys


def awk_num(x):
    s = "%.6g" % x
    return s


def main():
    raw, out, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(out, exist_ok=True)
    runs = ["bench\tmode\tgrammar\ttimeout_s\tstatus\texit\twall_s\tmax_rss_mb\tlast_phase"]
    vals = ["bench\tmode\tgrammar\tkey\tvalue"]
    evid = ["bench\tmode\tgrammar\texit\tstatus\terror_line\twall_s\tout_sha256\tcmd_sha256"]
    for spec in specs:
        b, m, g = spec.split(":")[:3]
        d = os.path.join(raw, b, "%s-%s" % (m, g))
        rd = lambda f: open(os.path.join(d, f), "rb").read()
        text = rd("out.txt").decode("utf-8", "replace")
        lines = text.split("\n")
        rc = int(rd("exit").decode().strip())
        to = rd("timeout").decode().strip()
        wall, rss = "0", "0"
        for l in rd("time.txt").decode("utf-8", "replace").split("\n"):
            if "Elapsed (wall clock)" in l:
                parts = l.split(": ")[1].split(":")
                s = 0.0
                for p in parts:
                    s = s * 60 + float(p)
                wall = awk_num(s)
            if "Maximum resident set size" in l:
                rss = str(int(int(l.split(": ")[1]) / 1024))
        has_over = any(l.startswith("#CFLIDR-pt-over:") for l in lines)
        if rc == 0 and has_over:
            st = "ok"
        elif "java.lang.StackOverflowError" in text:
            st = "sof"
        elif "java.lang.OutOfMemoryError" in text:
            st = "oom"
        elif rc in (124, 137):
            st = "timeout"
        else:
            st = "error"
        last = "-"
        for l in lines:
            mm = re.match(r"^#CFLIDR-([a-z]+)-ms:", l)
            if mm:
                last = mm.group(1)
        err = "-"
        cand = [l for l in lines if l.startswith("#CFLIDR-error:")] or \
            [l for l in lines if re.search(r"java\.lang\.(StackOverflowError|OutOfMemoryError)", l)]
        if cand:
            err = cand[0].replace("\t", " ").encode("utf-8")[:200].decode("utf-8", "ignore")
        runs.append("\t".join([b, m, g, to, st, str(rc), wall, rss, last]))
        for l in lines:
            if l.startswith("#CFLIDR-") and not l.startswith("#CFLIDR-error"):
                mm = re.match(r"^#([^:]+): *(.*)$", l)
                if mm:
                    vals.append("\t".join([b, m, g, mm.group(1), mm.group(2).split("\t")[0]]))
        evid.append("\t".join([b, m, g, str(rc), st, err, wall, hashlib.sha256(rd("out.txt")).hexdigest(),
                               hashlib.sha256(rd("cmd.txt")).hexdigest()]))
    for name, rows in (("runs.tsv", runs), ("values.tsv", vals), ("evidence.tsv", evid)):
        with open(os.path.join(out, name), "w") as f:
            f.write("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
