#!/usr/bin/env python3
"""critic-E5 probe of two committed check functions on crafted inputs (no Qilin run):
 (a) acceptance/E5/S2_bench.sh check_cmd (extracted unchanged from the heredoc): which cmd.txt it accepts;
 (b) acceptance/E5/e5lib.py phase_problems (S1, S2, S5): which phase lines it accepts.
Usage: python3 critic/E5/s1_s2_probe.py"""
import os, re, sys, tempfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "acceptance", "E5"))
import e5lib

src = open(os.path.join(ROOT, "acceptance", "E5", "S2_bench.sh")).read()
ns = {"os": os, "root": ROOT}
exec(re.search(r'^JDK = .*$', src, re.M).group(0), ns)
exec(src[src.index("def tokens(d):"):src.index("def rows_of(dd):")], ns)
J = os.path.join(ROOT, "artifact", "benchmarks")
base = ("-Xmx8g -XX:+ExitOnOutOfMemoryError -jar /x/qilin.jar -pae -pe -clinit=ONFLY -lcs -mh {pta} -apppath a.jar "
        "-libpath b.jar -mainclass dacapo.pmd.Main -reflectionlog r.log -jre=%s/JREs/jre1.6.0_45 -ucfsseam %s" % (J, ns["JDK"]))
cases = [
    ("contract command (control)", "java " + base, "insens"),
    ("insens with -Xint (interpreter only)", "java -Xint " + base, "insens"),
    ("insens with -XX:+UseSerialGC -XX:TieredStopAtLevel=1", "java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 " + base, "insens"),
    ("ucfs with a second -Xmx64g after -Xmx8g (the last one wins in HotSpot)", "java " + base.replace("-jar", "-Xmx64g -jar"), "ucfs-ANALYSIS"),
    ("ucfs with -XX:+UseParallelGC -XX:ParallelGCThreads=8", "java -XX:+UseParallelGC -XX:ParallelGCThreads=8 " + base, "ucfs-ANALYSIS"),
    ("control: -ucfscompare added", "java " + base + " -ucfscompare", "ucfs-ANALYSIS"),
]
print("(a) S2 check_cmd")
for name, cmd, run in cases:
    pta = "-pta=insens" if run == "insens" else "-pta=ucfs -ucfsbinding=ANALYSIS"
    d = tempfile.mkdtemp()
    open(os.path.join(d, "cmd.txt"), "w").write(cmd.format(pta=pta) + "\n")
    miss, extra = ns["check_cmd"](d, run)
    print("  %-75s -> %s" % (name, "ACCEPTED" if not miss and not extra else "rejected: missing %s extra %s" % (miss, extra)))

print("(b) e5lib.phase_problems")
def out(ph, total, ucfs):
    kv = [("UCFS-import-ucfs-ms", str(ucfs))]
    kv += [("UCFS-phase-%s-ms" % p, "%.3f" % ph[p]) for p in e5lib.PHASES]
    return kv + [("UCFS-phase-total-ms", "%.3f" % total)]
# luindex ANALYSIS shape (planner smoke1): export 66 grammar 12 rsm 50 input 13 parse 293 roots 13 pairs 7 import 8, total 467
good = dict(export=66, grammar=12, rsm=50, input=13, parse=293, roots=13, pairs=7, import_=8)
good["import"] = good.pop("import_")
cases = [
    ("contract shape (control)", dict(good), 467.0, 467),
    ("labels parse and export swapped", dict(good, parse=66, export=293), 467.0, 467),
    ("parse time booked under roots (parse 0)", dict(good, parse=0.0, roots=306), 467.0, 467),
    ("import never timed (0.000) and left out of total", dict(good, **{"import": 0.0}), 459.5, 467),
    ("antlr scale: 5 % of total unaccounted (5.3 s of 107 s)", {k: v * 107242 / 467 * 0.95 for k, v in good.items()}, 107242 * 0.95 + 1, 107242),
    ("control: sum of phases above total", dict(good, parse=400), 467.0, 467),
]
for name, ph, tot, ucfs in cases:
    pr = e5lib.phase_problems(out(ph, tot, ucfs))
    print("  %-75s -> %s" % (name, "ACCEPTED" if not pr else "rejected: %s" % pr))
