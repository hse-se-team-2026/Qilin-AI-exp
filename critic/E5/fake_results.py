#!/usr/bin/env python3
"""critic-E5 probe: fabricates a complete docs/ucfs-integration/e5-results tree (and a repro directory of
e5-bench.sh) WITHOUT running Qilin, from the committed E4 answers and invented times, to show what the
committed E5 acceptance (S5_results.sh, e5tables.py, doc_check.py) can and cannot tell apart.

Usage: python3 critic/E5/fake_results.py <out-root> [mutation ...]
  writes <out-root>/R (the results tree, with raw.tar.xz) and <out-root>/REPRO (as e5-bench.sh would for
  pmd luindex, insens ucfs-ANALYSIS, REPS=1 WARMUP=0). Mutations (each a defect S5 should reject):
    flavor       host is a shared-CPU low-cost VM: flavor lowcost10-8-64, cpu-count 2, mem 3900 MB, Debian
    cmdflags     cmd.txt of the runs carries other JVM flags per run (insens -Xmx2g -XX:+UseSerialGC -Xint,
                 ucfs -Xmx64g -XX:+UseParallelGC) instead of -Xmx16g
    javaopts     every out.txt starts with "Picked up JAVA_TOOL_OPTIONS: -XX:TieredStopAtLevel=1"
    overlap      bench meta started/finished 10 minutes apart while the walls of the part sum to hours
    kill137      probe-cg antlr: exit 137 after 412 s with TIMEOUT 3600 (kernel OOM killer, not a timeout)
    inconsistent antlr ucfs-ANALYSIS: UCFS-import-ucfs-ms 10x larger than the wall time of the process
    kernel       the Spark kernel inside -pta=ucfs (UCFS-import-spark-ms) 10x the Spark run (qilin-pta-s)
    minheap      antlr insens: one spurious timeout at 8224 MB -> min heap 8239 MB (7x the RSS of the 16 GB run)
    secret       host.txt holds a public IPv4 address, full.log a bearer token and a private key header
    load         load1 7.90 before every run on the 8-vCPU VM
    localasvm    a run on this laptop labelled host-kind vm / flavor gen-8-64 (cpu-model Core Ultra 7 155H, 22 CPUs)
Times are invented (lognormal noise around the E4 magnitudes); the answers are the E4 ones.
"""
import os
import random
import sys
import tarfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "acceptance", "E5"))
import e5lib  # noqa: E402

E4DIR = os.path.join(ROOT, "docs", "ucfs-integration", "e4-results")
JDK = "-exclude=java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*"
JAVA_VERSION = 'OpenJDK Runtime Environment Temurin-21.0.12.1+1 (build 21.0.12.1+1-LTS)'
CPU = "Intel Xeon Processor (Cascadelake)"
SKIP = "antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH"
SHARE = [("export", .10), ("grammar", .02), ("rsm", .08), ("input", .03), ("parse", .70), ("roots", .03),
         ("pairs", .02), ("import", .015)]


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def tsv(path, header, rows):
    w(path, "\t".join(header) + "\n" + "".join("\t".join(str(c) for c in r) + "\n" for r in rows))


def main(argv):
    out, muts = argv[1], set(argv[2:])
    rnd = random.Random(5)
    e4 = e5lib.e4_values(E4DIR)
    e4runs = {(r["bench"], r["run"]): r for r in e5lib.read_tsv(os.path.join(E4DIR, "runs.tsv"))}
    R = os.path.join(out, "R")
    head = os.popen("git -C %s rev-parse HEAD" % ROOT).read().strip()
    jar_sha = "ab" * 32
    flavor, ncpu, mem, osname = "gen-8-64", "8", "63487", "Ubuntu 24.04.3 LTS"
    if "flavor" in muts:
        flavor, ncpu, mem, osname = "lowcost10-8-64", "2", "3900", "Debian GNU/Linux 12 (bookworm)"
    global CPU
    if "localasvm" in muts:
        # this laptop, labelled with E5_HOST_KIND=vm E5_FLAVOR=gen-8-64 (both are plain environment variables)
        CPU, ncpu, mem, osname = "Intel(R) Core(TM) Ultra 7 155H", "22", "31726", "Ubuntu 26.04 LTS"
    files = []

    def noise(x, cv=0.03):
        return x * rnd.lognormvariate(0, cv)

    def meta(part, extra, started="2026-11-01T10:00:00+03:00", finished="2026-11-01T13:00:00+03:00"):
        keys = [("command", "bash scripts/ucfs/e5-bench.sh ..."), ("git-head", head), ("tree-clean", "yes"),
                ("jar", "/home/ubuntu/e5/jar/Qilin-fat.jar"), ("jar-sha256", jar_sha)]
        keys += extra
        keys += [("jvm-flags", "-XX:+ExitOnOutOfMemoryError")] if part != "minheap" else []
        return keys + [("host-kind", "vm"), ("flavor", flavor), ("cpu-model", CPU), ("cpu-count", ncpu),
                       ("mem-total-mb", mem), ("kernel", "6.8.0-139-generic"), ("os", osname),
                       ("java-version", JAVA_VERSION), ("other-java", "0"), ("load-start", "0.08 0.12 0.10"),
                       ("started", started), ("finished", finished)]

    def write_meta(path, keys):
        tsv(path, ["key", "value"], keys)

    def out_txt(b, run, spark_ms, ucfs_ms, kernel_ms, rss):
        lines = []
        if "javaopts" in muts:
            lines.append("Picked up JAVA_TOOL_OPTIONS: -XX:TieredStopAtLevel=1")
        lines.append("Context-Insensitive ...")
        for k, v in e5lib.e4_answer(e4, b, run).items():
            lines.append("#%s: %s" % (k, v))
        lines.append("Time (sec): %s" % ((kernel_ms + ucfs_ms) / 1000.0 if run != "insens" else spark_ms / 1000.0))
        lines.append("Main PTA (including pre-analysis) elapsed time: %.3fs" % ((spark_ms + ucfs_ms) / 1000.0 + 2))
        lines.append("Main PTA consumed memory: %.2f MB" % (rss * 0.9))
        if run != "insens":
            lines.append("#UCFS-import-spark-ms: %d" % kernel_ms)
            lines.append("#UCFS-import-ucfs-ms: %d" % ucfs_ms)
            tot = ucfs_ms - 0.4
            for p, s in SHARE:
                lines.append("#UCFS-phase-%s-ms: %.3f" % (p, tot * s))
            lines.append("#UCFS-phase-total-ms: %.3f" % tot)
        return "\n".join(lines) + "\n"

    def time_txt(wall, user, sys_, rss):
        m, s = divmod(wall, 60)
        return ("\tCommand being timed: \"java ...\"\n\tUser time (seconds): %.2f\n\tSystem time (seconds): %.2f\n"
                "\tElapsed (wall clock) time (h:mm:ss or m:ss): %d:%05.2f\n\tMaximum resident set size (kbytes): %d\n"
                "\tExit status: 0\n" % (user, sys_, m, s, rss * 1024))

    def cmd_txt(b, run, xmx):
        jvm = ["-Xmx" + xmx, "-XX:+ExitOnOutOfMemoryError"]
        if "cmdflags" in muts:
            jvm = ["-Xmx2g", "-XX:+UseSerialGC", "-Xint", "-XX:+ExitOnOutOfMemoryError"] if run == "insens" else \
                ["-Xmx64g", "-XX:+UseParallelGC", "-XX:+ExitOnOutOfMemoryError"]
        bench = "/home/ubuntu/e5/Qilin-AI-exp/artifact/benchmarks"
        opts = ["-pta=insens"] if run == "insens" else ["-pta=ucfs", "-ucfsbinding=" + run[5:]]
        return " ".join(["/home/ubuntu/e5/jdks/jdk-21.0.12.1+1/bin/java"] + jvm + [
            "-jar", "/home/ubuntu/e5/jar/Qilin-fat.jar", "-pae", "-pe", "-clinit=ONFLY", "-lcs", "-mh"] + opts + [
            "-apppath", "%s/dacapo2006/%s.jar" % (bench, b), "-libpath", "%s/dacapo2006/%s-deps.jar" % (bench, b),
            "-mainclass", "dacapo.%s.Main" % b, "-reflectionlog", "%s/dacapo2006/%s-refl.log" % (bench, b),
            "-jre=%s/JREs/jre1.6.0_45" % bench, "-ucfsseam", JDK]) + "\n"

    def base(b, run):
        kern = float(e4.get((b, "ucfs-ANALYSIS"), {}).get("UCFS-import-spark-ms", 3000))
        ucfs = float(e4.get((b, run), {}).get("UCFS-import-ucfs-ms", 0)) if run != "insens" else 0.0
        e4w = float(e4runs.get((b, run), e4runs[(b, "insens")])["wall_s"])
        rss = int(e4runs.get((b, run), e4runs[(b, "insens")])["max_rss_mb"])
        return kern, ucfs, e4w, rss

    def one_run(part, b, run, rep, xmx, status="ok", d=None):
        d = d or os.path.join(R, part, b, run, "rep%d" % rep)
        kern, ucfs, e4w, rss = base(b, run)
        spark_ms = int(noise(kern))
        kernel_ms = int(noise(kern)) * (10 if "kernel" in muts else 1)
        ucfs_ms = int(noise(ucfs)) if run != "insens" else 0
        wall = round(noise(max(e4w * 0.8, 3.0)), 2)
        if "inconsistent" in muts and (b, run) == ("antlr", "ucfs-ANALYSIS"):
            ucfs_ms = int(wall * 1000 * 10)
        rss_v = int(noise(rss, 0.02))
        user, sys_ = round(wall * 1.6, 2), round(wall * 0.05, 2)
        l1 = "7.90" if "load" in muts else "%.2f" % rnd.uniform(0.9, 1.6)
        text = out_txt(b, run, spark_ms, ucfs_ms, kernel_ms, rss_v)
        rc = "0"
        if status == "timeout":
            rc, text = "124", "Context-Insensitive ...\n"
            wall = float(part_timeout(part)) + 0.4
            if "kill137" in muts and (part, b) == ("probe-cg", "antlr"):
                rc, wall = "137", 412.0
        w(os.path.join(d, "cmd.txt"), cmd_txt(b, run, xmx))
        w(os.path.join(d, "out.txt"), text)
        w(os.path.join(d, "time.txt"), time_txt(wall, user, sys_, rss_v))
        w(os.path.join(d, "exit"), rc + "\n")
        w(os.path.join(d, "load1"), l1 + "\n")
        st = "ok" if rc == "0" else "timeout"
        row = [b, run, rep, st, rc, "%.2f" % wall, "%.2f" % user, "%.2f" % sys_, rss_v, l1]
        vals = [[b, run, rep, k, v] for k, v in e5lib.parse_out(text)]
        return row, vals

    def part_timeout(part):
        return 3600 if part.startswith("probe") else 900

    # --- bench
    runs, vals = [], []
    skip = set(tuple(x.split(":")) for x in SKIP.split())
    for rep in range(0, 11):
        for b in e5lib.BENCHES:
            for run in e5lib.RUNS:
                if (b, run) in skip:
                    continue
                r, v = one_run("bench", b, run, rep, "16g")
                runs.append(r)
                vals += v
    HR = "bench run rep status exit wall_s user_s sys_s max_rss_mb load1".split()
    tsv(os.path.join(R, "bench", "runs.tsv"), HR, runs)
    tsv(os.path.join(R, "bench", "values.tsv"), "bench run rep key value".split(), vals)
    started, finished = "2026-11-01T10:00:00+03:00", "2026-11-01T13:00:00+03:00"
    if "overlap" in muts:
        finished = "2026-11-01T10:10:00+03:00"
    write_meta(os.path.join(R, "bench", "meta.tsv"), _order_bench(meta("bench", [
        ("benches", " ".join(e5lib.BENCHES)), ("runs", " ".join(e5lib.RUNS)), ("reps", "10"), ("warmup", "1"),
        ("skip", SKIP), ("timeout", "900"), ("xmx", "16g"), ("jdk-bodies", "no")], started, finished)))
    w(os.path.join(R, "bench", "bench.log"), "e5-bench: ...\n")
    print("bench: %d runs, sum of wall_s %.0f s, meta started %s finished %s" % (
        len(runs), sum(float(r[5]) for r in runs), started, finished))

    # --- probes
    for part, plan, jdkb in (("probe-cg", [("antlr", "ucfs-CALL_GRAPH", "timeout"), ("bloat", "ucfs-CALL_GRAPH", "timeout"),
                                           ("checkstyle", "ucfs-CALL_GRAPH", "ok")], "no"),
                             ("probe-jdk", [("luindex", "insens", "ok"), ("luindex", "ucfs-ANALYSIS", "timeout")], "yes")):
        pr, pv = [], []
        for b, run, st in plan:
            r, v = one_run(part, b, run, 1, "52g", st)
            pr.append(r)
            pv += v
        tsv(os.path.join(R, part, "runs.tsv"), HR, pr)
        tsv(os.path.join(R, part, "values.tsv"), "bench run rep key value".split(), pv)
        runs_s = "ucfs-CALL_GRAPH" if part == "probe-cg" else "insens ucfs-ANALYSIS"
        benches = "antlr bloat checkstyle" if part == "probe-cg" else "luindex"
        write_meta(os.path.join(R, part, "meta.tsv"), _order_bench(meta(part, [
            ("benches", benches), ("runs", runs_s), ("reps", "1"), ("warmup", "0"), ("skip", ""),
            ("timeout", "3600"), ("xmx", "52g"), ("jdk-bodies", jdkb)])))
        w(os.path.join(R, part, "bench.log"), "e5-bench: ...\n")

    # --- minheap
    steps, mins = [], []
    for b in e5lib.COVERED:
        for run in e5lib.RUNS:
            if (b, run) in skip:
                continue
            kern, ucfs, e4w, rss = base(b, run)
            thr = int(rss * 0.25) + 7
            seq = []
            lo, hi = 64, 16384

            def step(mb, k):
                d = os.path.join(R, "minheap", b, run, "x%d" % mb)
                wall = round(noise(max(e4w * 0.8, 3.0)), 2)
                spurious = "minheap" in muts and (b, run, mb) == ("antlr", "insens", 8224)
                if spurious:
                    w(os.path.join(d, "out.txt"), "Context-Insensitive ...\n")
                    rc, st, wall = "124", "timeout", 60.4
                elif mb >= thr:
                    kern2, _, _, _ = base(b, run)
                    w(os.path.join(d, "out.txt"), out_txt(b, run, int(kern2), int(ucfs), int(kern2), rss))
                    rc, st = "0", "ok"
                else:
                    w(os.path.join(d, "out.txt"), "Context-Insensitive ...\njava.lang.OutOfMemoryError: Java heap space\n"
                      "Terminating due to java.lang.OutOfMemoryError: Java heap space\n")
                    rc, st, wall = "3", "oom", round(rnd.uniform(1.5, 4.0), 2)
                w(os.path.join(d, "cmd.txt"), cmd_txt(b, run, "%dm" % mb))
                w(os.path.join(d, "time.txt"), time_txt(wall, wall, 0.1, min(rss, mb + 200)))
                w(os.path.join(d, "exit"), rc + "\n")
                steps.append([b, run, k, mb, st, rc, "%.2f" % wall, min(rss, mb + 200)])
                return st, wall
            st0, w0 = step(hi, 0)
            st1, _ = step(lo, 1)
            k = 2
            while hi - lo > 16:
                mid = (lo + hi) // 2
                st, _ = step(mid, k)
                k += 1
                if st == "ok":
                    hi = mid
                else:
                    lo = mid
            import math
            mins.append([b, run, "ok", hi, lo, k, "%.2f" % w0, steps[-k][7], max(60, math.ceil(3 * w0))])
    tsv(os.path.join(R, "minheap", "steps.tsv"), "bench run step xmx_mb status exit wall_s max_rss_mb".split(), steps)
    tsv(os.path.join(R, "minheap", "minheap.tsv"),
        "bench run status minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s".split(), mins)
    mk = [("command", "bash scripts/ucfs/e5-minheap.sh ..."), ("git-head", head), ("tree-clean", "yes"),
          ("jar", "/home/ubuntu/e5/jar/Qilin-fat.jar"), ("jar-sha256", jar_sha), ("benches", " ".join(e5lib.COVERED)),
          ("runs", " ".join(e5lib.RUNS)), ("skip", SKIP), ("timeout", "900"), ("hi-mb", "16384"), ("lo-mb", "64"),
          ("gran-mb", "16"), ("timeout-factor", "3"), ("jvm-flags", "-XX:+ExitOnOutOfMemoryError")]
    mk += [kv for kv in meta("minheap", []) if kv[0] in ("host-kind", "flavor", "cpu-model", "cpu-count", "mem-total-mb",
                                                          "kernel", "os", "java-version", "other-java", "load-start",
                                                          "started", "finished")]
    write_meta(os.path.join(R, "minheap", "meta.tsv"), mk)
    w(os.path.join(R, "minheap", "minheap.log"), "e5-minheap: ...\n")
    for m in mins:
        if m[0] == "antlr" and m[1] == "insens":
            print("minheap antlr insens: %s MB (ref RSS of the 16 GB run %s MB)" % (m[3], m[7]))

    # --- top-level files
    host = ("== lscpu\nArchitecture: x86_64\nCPU(s): %s\nModel name: %s\n== head -n 3 /proc/meminfo\nMemTotal: %s kB\n"
            "== uname -a\nLinux e5-bench 6.8.0-139-generic x86_64 GNU/Linux\n== nproc\n%s\n" % (ncpu, CPU, int(mem) * 1024, ncpu))
    log = "e5-full: bench started\ne5-full: bench finished exit 0\n"
    if "secret" in muts:
        host += "== ip -4 addr\n    inet 89.208.17.42/24 brd 89.208.17.255 scope global eth0\n"
        log += ("curl -H 'Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MWVhYjI2YyJ9.c2lnbmF0dXJl'\n"
                "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ\n")
    w(os.path.join(R, "host.txt"), host)
    w(os.path.join(R, "full.log"), log)
    tsv(os.path.join(R, "full.tsv"), "part started finished exit".split(),
        [[p, "2026-11-01T10:00:00", "2026-11-01T18:00:00", 0] for p in ("bench", "minheap", "probe-cg", "probe-jdk")])
    tsv(os.path.join(R, "setup.tsv"), ["key", "value"], [
        ("repo-url", "https://github.com/hse-se-team-2026/Qilin-AI-exp.git"), ("commit", head), ("git-head", head),
        ("tree-clean", "yes"), ("jdk21", "/home/ubuntu/e5/jdks/jdk-21.0.12.1+1"),
        ("jdk21-sha256", "ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94"),
        ("jdk11", "/home/ubuntu/e5/jdks/jdk-11.0.32.1+1"),
        ("jdk11-sha256", "5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d"),
        ("java-version", JAVA_VERSION), ("jar", "/home/ubuntu/e5/jar/Qilin-fat.jar"), ("jar-sha256", jar_sha),
        ("started", "2026-11-01T09:40:00+03:00"), ("finished", "2026-11-01T10:00:00+03:00")])
    with tarfile.open(os.path.join(R, "raw.tar.xz"), "w:xz") as t:
        for part in ("bench", "minheap", "probe-cg", "probe-jdk"):
            for dp, dn, fn in os.walk(os.path.join(R, part)):
                for f in sorted(fn):
                    if f in ("cmd.txt", "out.txt", "time.txt", "exit", "load1"):
                        p = os.path.join(dp, f)
                        t.add(p, arcname=os.path.relpath(p, R))
    # remove the run directories from R (S5 reads them from raw.tar.xz), keep TSV and logs
    import shutil
    for part in ("bench", "minheap", "probe-cg", "probe-jdk"):
        for e in os.listdir(os.path.join(R, part)):
            if os.path.isdir(os.path.join(R, part, e)):
                shutil.rmtree(os.path.join(R, part, e))

    # --- repro (e5-bench.sh REPS=1 WARMUP=0 RUNS="insens ucfs-ANALYSIS" pmd luindex)
    rr, rv = [], []
    for b in ("pmd", "luindex"):
        for run in ("insens", "ucfs-ANALYSIS"):
            r, v = one_run("bench", b, run, 1, "8g", d=os.path.join(out, "REPRO", b, run, "rep1"))
            rr.append(r)
            rv += v
    tsv(os.path.join(out, "REPRO", "runs.tsv"), HR, rr)
    tsv(os.path.join(out, "REPRO", "values.tsv"), "bench run rep key value".split(), rv)
    print("written %s (mutations: %s)" % (out, " ".join(sorted(muts)) or "none"))


def _order_bench(keys):
    """meta.tsv keys of e5-bench.sh in the contract order (E5-S2)."""
    order = ("command git-head tree-clean jar jar-sha256 benches runs reps warmup skip timeout xmx jvm-flags jdk-bodies "
             "host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version other-java load-start started "
             "finished").split()
    d = dict(keys)
    return [(k, d.get(k, "")) for k in order]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
