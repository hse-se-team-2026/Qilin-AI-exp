#!/usr/bin/env bash
# E5-S5b acceptance: the committed results of the final E5 run (docs/ai/tickets/E5-S5b.md), in
# docs/ucfs-integration/e5-results/ (R below), packed from the copy that E5-S5a brought back from the VM.
#  1. files: R/{setup.tsv,host.txt,full.tsv,full.log}; R/bench/{runs,values,meta}.tsv + bench.log + raw.tar.xz;
#     R/minheap/{minheap,steps,meta}.tsv + minheap.log + raw.tar.xz; R/probe-cg and R/probe-jdk
#     {runs,values,meta}.tsv + bench.log + raw.tar.xz; and R/vm-run.tsv (host-kind vm) or R/fallback.txt
#     (host-kind local);
#  2. one host and one build: the four meta.tsv agree on git-head, tree-clean (yes), jar-sha256, host-kind,
#     flavor, cpu-model, cpu-count, mem-total-mb, kernel, os, java-version and the java option keys, which are
#     empty; git-head = setup.tsv commit and git-head; jar-sha256 = setup.tsv jar-sha256; java-version is
#     Temurin 21.0.12.1+1 (setup.tsv); the host facts of meta.tsv are those observed in host.txt (lscpu Model
#     name, nproc, MemTotal, PRETTY_NAME of os-release, uname -a); host.txt ends with the section kernel-oom;
#     host-kind is vm or local, nothing else:
#     vm  -> flavor gen-8-64 and, observed in host.txt, nproc 8, MemTotal >= 60000 MB, Ubuntu 24.04,
#            systemd-detect-virt not "none", a Xeon CPU; other-java 0 in every meta.tsv and before every run;
#            vm-run.tsv passes acceptance/E5/e5vm.py (the checks of S5a_vmrun.sh on R itself), outcome complete,
#            so the committed results are the copy of the VM run byte for byte (results-manifest-sha256);
#     local -> R/fallback.txt with a line "lead-decision: ..." (the lead's fallback, E5.md D7);
#  3. the results come from the code of HEAD: git-head is a commit of this repository, an ancestor of HEAD,
#     and `git diff <git-head> HEAD` is empty for qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src
#     scripts/ucfs gradle.properties *.gradle settings.gradle artifact/benchmarks;
#  4. full.tsv: parts bench, minheap, probe-cg, probe-jdk in this order, each exit 0;
#  5. the parameters fixed in E5.md: bench reps 10, warmup 1, timeout 900, xmx 16g, the 12 benchmarks in the
#     order of e5lib.BENCHES, runs "insens ucfs-ANALYSIS ucfs-CALL_GRAPH", the default skip, jdk-bodies no;
#     minheap on the 6 covered benchmarks, the 3 runs, default skip, hi 16384, lo 64, gran 16, factor 3,
#     timeout 900; probe-cg ucfs-CALL_GRAPH on antlr bloat checkstyle, reps 1, warmup 0, skip "", timeout
#     3600, xmx 52g; probe-jdk insens and ucfs-ANALYSIS on luindex, jdk-bodies yes, same limits;
#     compressed-oops recorded (true or false) in bench and the probes;
#  6. the TSV files are the run directories: <part>/raw.tar.xz holds exactly the files of e5lib.RUN_FILES of
#     the run directories of the part; runs.tsv/values.tsv of bench, probe-cg, probe-jdk and steps.tsv of
#     minheap are re-derived here from them (status with e5lib.status_of: exit 137 before the timeout is
#     killed, not timeout) and must be equal; every cmd.txt is token for token e5lib.expected_cmd
#     (<jdk21 of setup.tsv>/bin/java, the jar of meta.tsv, the clone next to it, -Xmx16g / -Xmx52g /
#     -Xmx<mb>m), so all runs differ only in -pta/-ucfsbinding/-Xmx; no out.txt reports "Picked up" JVM
#     options;
#  7. the runs were sequential and in the planned order: [start, end] of every run directory of the four parts,
#     in the order bench (e5lib.run_order) -> minheap (searches bench -> run, steps in order) -> probe-cg ->
#     probe-jdk, do not overlap, hold the wall time of GNU time, and lie inside started..finished of their
#     part in full.tsv (+- 1 s);
#  8. bench: 11 rows (rep 0..10) for every benchmark and run except the skipped ones; insens ok in all 10
#     measured repetitions on all 12; ucfs-ANALYSIS ok in >= 3 measured repetitions on >= 2 covered
#     benchmarks; the times of every ok run are consistent (e5lib.time_problems: phases of E5-S1 within
#     max(5 ms, 1 %), kernel + UCFS <= 1000 * qilin-pta-s + 2, qilin-pta-s <= qilin-main-pta-s <= wall_s); for
#     every (benchmark, ucfs run) with >= 3 ok repetitions the median kernel (UCFS-import-spark-ms) / median
#     Spark of the insens run (1000 * qilin-pta-s) lies in [0.67, 1.5] (the same work, E5.md D14); in every
#     (bench, run) the answer key set = the E4 one and every E4 value is among the values observed;
#  9. minheap: 16 searches (6 covered x 3 runs - 2 skipped); each replays the rule of E5-S3
#     (e5lib.replay_minheap: repeat after error, confirmation at +32 / -32) and its reference answer = the E4
#     answer; minheap.tsv rows = the replay; the rows with status ok are plausible (e5lib.minheap_plausibility);
#     >= 2 covered benchmarks have status ok for both insens and ucfs-ANALYSIS;
# 10. no secret in any committed result file or any member of the raw.tar.xz archives (e5lib.scan_paths: IPv4
#     except 127.x/10.x, bearer token, Authorization, private/SSH key, keyId/secret/password, UUID);
# 11. the code of HEAD gives the same answer here: e5-bench.sh REPS=1 WARMUP=0 RUNS="insens ucfs-ANALYSIS" on
#     pmd luindex with a fresh jar -> answer keys = those of R/bench, times consistent (time differs, not
#     compared);
# 12. acceptance/E5/e5tables.py renders the eight tables from R; tracked files unchanged.
# Usage: bash acceptance/E5/S5_results.sh          (exit 0 = PASS; about 5 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
R="$ROOT/docs/ucfs-integration/e5-results"
[ -d "$R" ] || { fail "no $R"; finish S5_results; }

for f in setup.tsv host.txt full.tsv full.log \
         bench/runs.tsv bench/values.tsv bench/meta.tsv bench/bench.log bench/raw.tar.xz \
         minheap/minheap.tsv minheap/steps.tsv minheap/meta.tsv minheap/minheap.log minheap/raw.tar.xz \
         probe-cg/runs.tsv probe-cg/values.tsv probe-cg/meta.tsv probe-cg/bench.log probe-cg/raw.tar.xz \
         probe-jdk/runs.tsv probe-jdk/values.tsv probe-jdk/meta.tsv probe-jdk/bench.log probe-jdk/raw.tar.xz; do
    [ -f "$R/$f" ] && pass "file $f" || fail "missing $f"
done

GH="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("git-head",""))' "$R/bench/meta.tsv" 2>/dev/null)"
CODE=(qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/ucfs gradle.properties '*.gradle' settings.gradle artifact/benchmarks)
if [ -n "$GH" ] && git cat-file -e "$GH^{commit}" 2>/dev/null; then
    pass "git-head $GH is a commit of this repository"
    git merge-base --is-ancestor "$GH" HEAD && pass "git-head is an ancestor of HEAD" || fail "git-head is not an ancestor of HEAD"
    if git diff --quiet "$GH" HEAD -- "${CODE[@]}"; then
        pass "code at git-head = code at HEAD"
    else
        fail "code differs between git-head and HEAD: $(git diff --name-only "$GH" HEAD -- "${CODE[@]}" | head -n 5 | tr '\n' ' ')"
    fi
else
    fail "git-head '$GH' is not a commit of this repository"
fi

RAW="$OUT/raw"
safe_reset_dir "$RAW"
for p in bench minheap probe-cg probe-jdk; do
    tar -xJf "$R/$p/raw.tar.xz" -C "$RAW" 2>>"$LOGS/S5-tar.txt" && pass "$p/raw.tar.xz unpacks" || fail "$p/raw.tar.xz does not unpack"
done

FRESH="$OUT/qilin-fat.jar"
REPRO="$OUT/repro"
safe_reset_dir "$REPRO"
if fresh_fatjar "$FRESH"; then
    QILIN_JAR="$FRESH" REPS=1 WARMUP=0 RUNS="insens ucfs-ANALYSIS" XMX=8g bash scripts/ucfs/e5-bench.sh "$REPRO" pmd luindex \
        > "$LOGS/S5-repro.txt" 2>&1 || fail "e5-bench.sh repro exit $?"
else
    fail "fat jar build"
fi

py - "$R" "$RAW" "$E4_RESULTS" "$REPRO" "$ROOT" > "$LOGS/S5-check.txt" 2>&1 <<'PY'
import os, re, sys
import e5lib, e5tables, e5vm
R, raw, e4dir, repro, root = sys.argv[1:6]
e4 = e5lib.e4_values(e4dir)
bmap = e5lib.bench_map(root)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
def meta(p):
    try:
        return e5lib.read_meta(os.path.join(R, p, "meta.tsv"))
    except OSError:
        return {}
def tsv(*p):
    try:
        return e5lib.read_tsv(os.path.join(R, *p))
    except OSError:
        return []
setup = e5lib.read_meta(os.path.join(R, "setup.tsv")) if os.path.isfile(os.path.join(R, "setup.tsv")) else {}
parts = ["bench", "minheap", "probe-cg", "probe-jdk"]
M = {p: meta(p) for p in parts}
ENV = [k for _, k in e5lib.JAVA_ENV]
SAME = ["git-head", "tree-clean", "jar-sha256", "host-kind", "flavor", "cpu-model", "cpu-count", "mem-total-mb",
        "kernel", "os", "java-version"] + ENV
for k in SAME:
    vs = {M[p].get(k) for p in parts}
    (ok if len(vs) == 1 and None not in vs else ko)("meta %s equal in the four parts: %s" % (k, vs))
b = M["bench"]
(ok if all(M[p].get(k) == "" for p in parts for k in ENV) else ko)("java option keys %s empty in every part" % ENV)
(ok if b.get("tree-clean") == "yes" else ko)("tree-clean yes")
(ok if b.get("git-head") and b.get("git-head") == setup.get("commit") == setup.get("git-head") else ko)(
    "git-head = setup.tsv commit = setup.tsv git-head")
(ok if b.get("jar-sha256") and b.get("jar-sha256") == setup.get("jar-sha256") else ko)("jar-sha256 = setup.tsv jar-sha256")
(ok if b.get("java-version") == setup.get("java-version") and "Temurin-21.0.12.1+1" in b.get("java-version", "") else ko)(
    "java-version Temurin 21.0.12.1+1 = setup.tsv")

# 2. host facts observed in host.txt
host = e5lib.read(os.path.join(R, "host.txt"), "")
sec = {}
for m in re.finditer(r"^== (.+)\n((?:(?!== ).*\n?)*)", host, re.M):
    sec.setdefault(m.group(1).strip(), m.group(2))
def first(rx, text):
    mm = re.search(rx, text or "", re.M)
    return mm.group(1).strip() if mm else None
obs = {"cpu-model": first(r"^Model name:\s*(.+)$", sec.get("lscpu")),
       "cpu-count": first(r"^\s*(\d+)\s*$", sec.get("nproc")),
       "mem-total-mb": (lambda kb: str(int(kb) // 1024) if kb else None)(first(r"^MemTotal:\s*(\d+) kB", sec.get("head -n 3 /proc/meminfo"))),
       "os": (lambda v: v.strip('"') if v else None)(first(r"^PRETTY_NAME=(.+)$", sec.get("cat /etc/os-release")))}
diff = {k: (b.get(k), v) for k, v in obs.items() if b.get(k) != v}
(ok if not diff else ko)("meta host facts = host.txt observations %s" % (diff or ""))
(ok if b.get("kernel") and b.get("kernel") in (sec.get("uname -a") or "") else ko)("kernel %r in uname -a of host.txt" % b.get("kernel"))
(ok if list(sec)[-1:] == ["kernel-oom"] else ko)("host.txt ends with the section kernel-oom (%s)" % list(sec)[-1:])
virt = (sec.get("systemd-detect-virt") or "").strip()
hk = b.get("host-kind")
if hk == "vm":
    want = {"flavor": "gen-8-64"}
    probs = ["flavor %r" % b.get("flavor")] if b.get("flavor") != "gen-8-64" else []
    if obs["cpu-count"] != "8":
        probs.append("nproc %r (gen-8-64 has 8 vCPU)" % obs["cpu-count"])
    if not obs["mem-total-mb"] or int(obs["mem-total-mb"]) < 60000:
        probs.append("MemTotal %r MB < 60000" % obs["mem-total-mb"])
    if not (obs["os"] or "").startswith("Ubuntu 24.04"):
        probs.append("os %r is not Ubuntu 24.04" % obs["os"])
    if virt in ("", "none"):
        probs.append("systemd-detect-virt %r (not a VM)" % virt)
    if "Xeon" not in (obs["cpu-model"] or ""):
        probs.append("cpu-model %r is not a Xeon" % obs["cpu-model"])
    if any(M[p].get("other-java") != "0" for p in parts):
        probs.append("other-java of meta.tsv %s" % [M[p].get("other-java") for p in parts])
    (ok if not probs else ko)("host-kind vm: the observed host is the gen-8-64 VM of E5.md D7 %s" % (probs or ""))
    vp = e5vm.vmrun_problems(os.path.join(R, "vm-run.tsv"), R)
    vm = e5lib.read_meta(os.path.join(R, "vm-run.tsv")) if os.path.isfile(os.path.join(R, "vm-run.tsv")) else {}
    if vm.get("outcome") != "complete":
        vp.append("outcome %r" % vm.get("outcome"))
    (ok if not vp else ko)("vm-run.tsv: S5a record, results = the copy of the VM run (manifest) %s" % vp[:4])
elif hk == "local":
    fb = os.path.join(R, "fallback.txt")
    (ok if os.path.isfile(fb) and any(l.startswith("lead-decision: ") for l in open(fb)) else ko)(
        "host-kind local: fallback.txt with lead-decision")
else:
    ko("host-kind %r is neither vm nor local" % hk)

ft = tsv("full.tsv")
(ok if [(r["part"], r["exit"]) for r in ft] == [(p, "0") for p in parts] else ko)("full.tsv parts %s" % [(r["part"], r["exit"]) for r in ft])

# 5. parameters
want = {"bench": {"reps": "10", "warmup": "1", "timeout": "900", "xmx": "16g", "benches": " ".join(e5lib.BENCHES),
                  "runs": " ".join(e5lib.RUNS), "skip": e5lib.DEFAULT_SKIP_S, "jdk-bodies": "no"},
        "minheap": {"benches": " ".join(e5lib.COVERED), "runs": " ".join(e5lib.RUNS), "skip": e5lib.DEFAULT_SKIP_S,
                    "hi-mb": "16384", "lo-mb": "64", "gran-mb": "16", "timeout-factor": "3", "timeout": "900"},
        "probe-cg": {"runs": "ucfs-CALL_GRAPH", "benches": "antlr bloat checkstyle", "reps": "1", "warmup": "0", "skip": "",
                     "timeout": "3600", "xmx": "52g", "jdk-bodies": "no"},
        "probe-jdk": {"runs": "insens ucfs-ANALYSIS", "benches": "luindex", "reps": "1", "warmup": "0", "skip": "",
                      "timeout": "3600", "xmx": "52g", "jdk-bodies": "yes"}}
for p, w in want.items():
    bad = {k: (M[p].get(k), v) for k, v in w.items() if M[p].get(k) != v}
    if p != "minheap" and M[p].get("compressed-oops") not in ("true", "false"):
        bad["compressed-oops"] = (M[p].get("compressed-oops"), "true|false")
    (ok if not bad else ko)("%s parameters %s" % (p, bad or "as fixed in E5.md"))

# 6. re-derive from raw; 7. order of all runs
jar = b.get("jar", "")
java = os.path.join(setup.get("jdk21", ""), "bin", "java")
clone = os.path.join(os.path.dirname(os.path.dirname(jar)), "Qilin-AI-exp")
vm = hk == "vm"
skip0 = e5lib.parse_skip(e5lib.DEFAULT_SKIP_S)
plan = {"bench": e5lib.run_order(e5lib.BENCHES, e5lib.RUNS, 10, True, skip0),
        "probe-cg": e5lib.run_order(["antlr", "bloat", "checkstyle"], ["ucfs-CALL_GRAPH"], 1, False, set()),
        "probe-jdk": e5lib.run_order(["luindex"], ["insens", "ucfs-ANALYSIS"], 1, False, set())}
RUNHDR = ("bench run rep status exit wall_s user_s sys_s max_rss_mb load1 other_java procs_running steal_pct "
          "start_ns end_ns").split()
STEPHDR = "bench run step xmx_mb status exit wall_s max_rss_mb other_java start_ns end_ns".split()
items = {p: [] for p in parts}

def run_problems(f, row, st, cmd_want, cols):
    p = []
    s0, s1 = f["stat0"], f["stat1"]
    if s0 is None or s1 is None:
        return ["stat-before/after"]
    dall = s1[1] - s0[1]
    steal = 100.0 * (s1[0] - s0[0]) / dall if dall > 0 else 0.0
    exp = {"status": st, "exit": f["exit"], "max_rss_mb": str(f["rss"]), "other_java": str(f["other_java"]),
           "start_ns": str(f["start"]), "end_ns": str(f["end"]), "load1": f["load1"], "procs_running": str(s0[2])}
    p += ["%s %r != %r" % (k, row.get(k), v) for k, v in exp.items() if k in cols and row.get(k) != v]
    num = [("wall_s", f["wall"]), ("user_s", f["user"]), ("sys_s", f["sys"]), ("steal_pct", steal)]
    p += ["%s %r != %.2f" % (k, row.get(k), x) for k, x in num if k in cols and (
        not re.fullmatch(r"\d+\.\d\d", row.get(k, "")) or abs(float(row[k]) - x) > 0.0051)]
    cp = e5lib.cmd_problem(f["cmd"], cmd_want)
    if cp:
        p.append("cmd.txt " + cp)
    if f["picked_up"]:
        p.append("JVM options picked up from the environment")
    if vm and f["other_java"] != 0:
        p.append("other-java %s before the run on the VM" % f["other_java"])
    return p

for p in ("bench", "probe-cg", "probe-jdk"):
    runs, vals = tsv(p, "runs.tsv"), tsv(p, "values.tsv")
    try:
        (ok if e5lib.header(os.path.join(R, p, "runs.tsv")) == RUNHDR else ko)("%s: runs.tsv header" % p)
    except OSError:
        ko("%s: no runs.tsv" % p)
    V = {}
    for r in vals:
        V.setdefault((r["bench"], r["run"], r["rep"]), []).append((r["key"], r["value"]))
    rows = {(int(r["rep"]), r["bench"], r["run"]): r for r in runs}
    base = os.path.join(raw, p)
    dirs = set()
    for bb in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        for rr in sorted(os.listdir(os.path.join(base, bb))) if os.path.isdir(os.path.join(base, bb)) else []:
            for kk in sorted(os.listdir(os.path.join(base, bb, rr))):
                dirs.add((int(kk[3:]), bb, rr))
    (ok if dirs == set(rows) == set(plan[p]) and len(runs) == len(plan[p]) else ko)(
        "%s: run directories of raw.tar.xz %d = rows of runs.tsv %d = planned runs %d" % (p, len(dirs), len(runs), len(plan[p])))
    timeout = float(M[p].get("timeout", "900"))
    xmx = M[p].get("xmx", "16g")
    bad = 0
    for key in plan[p]:
        k, bb, rr = key
        d = os.path.join(base, bb, rr, "rep%d" % k)
        f = e5lib.read_run(d) if os.path.isdir(d) else None
        if f is None or key not in rows:
            bad += 1
            ko("%s %s %s rep%d: run directory or row missing" % (p, bb, rr, k)); continue
        items[p].append(("%s %s %s rep%d" % (p, bb, rr, k), f["start"], f["end"], f["wall"]))
        st = e5lib.status_of(int(f["exit"]), f["out"], f["wall"], timeout)
        probs = run_problems(f, rows[key], st, e5lib.expected_cmd(java, jar, xmx, rr, bb, clone, bmap,
                                                                  M[p].get("jdk-bodies") == "yes"), RUNHDR)
        if sorted(V.get((bb, rr, str(k)), [])) != sorted(f["kv"]):
            probs.append("values.tsv != out.txt")
        if probs:
            bad += 1
            if bad <= 3:
                ko("%s %s %s rep%d: %s" % (p, bb, rr, k, "; ".join(probs)[:300]))
    (ok if bad == 0 else ko)("%s: %d rows re-derived from raw.tar.xz (status, time, files, cmd.txt exact), %d differ" % (
        p, len(runs), bad))

steps, mins = tsv("minheap", "steps.tsv"), tsv("minheap", "minheap.tsv")
try:
    (ok if e5lib.header(os.path.join(R, "minheap", "steps.tsv")) == STEPHDR else ko)("minheap: steps.tsv header")
except OSError:
    ko("minheap: no steps.tsv")
mrow = {(m["bench"], m["run"]): m for m in mins}
bad = 0
refans = {}
pairs = [(bb, r) for bb in e5lib.COVERED for r in e5lib.RUNS if (bb, r) not in skip0]
want_dirs = set()
for bb, rr in pairs:
    ss = [s for s in steps if (s["bench"], s["run"]) == (bb, rr)]
    for s in ss:
        want_dirs.add((bb, rr, "s%s-x%s" % (s["step"], s["xmx_mb"])))
        d = os.path.join(raw, "minheap", bb, rr, "s%s-x%s" % (s["step"], s["xmx_mb"]))
        f = e5lib.read_run(d) if os.path.isdir(d) else None
        if f is None:
            bad += 1; continue
        items["minheap"].append(("minheap %s %s step %s" % (bb, rr, s["step"]), f["start"], f["end"], f["wall"]))
        m = mrow.get((bb, rr), {})
        to = float(M["minheap"].get("timeout", "900")) if s["step"] == "0" else float(m.get("step_timeout_s", "0") or 0)
        st = e5lib.status_of(int(f["exit"]), f["out"], f["wall"], to)
        ans = e5lib.answer_of(f["out"])
        if s["step"] == "0":
            refans[(bb, rr)] = ans
        elif st == "ok" and ans != refans.get((bb, rr)):
            st = "differs"
        probs = run_problems(f, s, st, e5lib.expected_cmd(java, jar, s["xmx_mb"] + "m", rr, bb, clone, bmap), STEPHDR)
        if probs:
            bad += 1
            if bad <= 3:
                ko("minheap %s %s step %s: %s" % (bb, rr, s["step"], "; ".join(probs)[:300]))
have_dirs = set()
mb = os.path.join(raw, "minheap")
for bb in os.listdir(mb) if os.path.isdir(mb) else []:
    for rr in os.listdir(os.path.join(mb, bb)) if os.path.isdir(os.path.join(mb, bb)) else []:
        have_dirs |= {(bb, rr, x) for x in os.listdir(os.path.join(mb, bb, rr))}
(ok if steps and bad == 0 and have_dirs == want_dirs else ko)(
    "minheap: %d steps re-derived from raw.tar.xz, %d differ, %d step directories for %d rows" % (
        len(steps), bad, len(have_dirs), len(steps)))

# 7. order and overlap of all runs
seq = []
for p, row in zip(parts, ft):
    a, z = e5lib.iso_epoch(row["started"]) - 1, e5lib.iso_epoch(row["finished"]) + 1
    out_of = [x[0] for x in items[p] if x[1] is None or x[2] is None or x[1] / 1e9 < a or x[2] / 1e9 > z]
    (ok if not out_of and items[p] else ko)("%s: %d runs inside started..finished of full.tsv %s" % (p, len(items[p]), out_of[:3]))
    seq += items[p]
ip = e5lib.interval_problems(seq)
(ok if not ip else ko)("all %d runs sequential, without overlap, in the planned order %s" % (len(seq), ip[:3]))

# 8. bench
bench = e5tables.Part(os.path.join(R, "bench"))
for bb in e5lib.BENCHES:
    for run in e5lib.RUNS:
        rows = [r for r in bench.runs if (r["bench"], r["run"]) == (bb, run)]
        exp = [] if (bb, run) in skip0 else [str(k) for k in range(11)]
        if sorted(r["rep"] for r in rows) != sorted(exp):
            ko("%s %s: reps %s" % (bb, run, sorted(r["rep"] for r in rows)))
okins = [bb for bb in e5lib.BENCHES if len(bench.okreps(bb, "insens")) == 10]
(ok if len(okins) == 12 else ko)("insens ok in 10 measured reps on %d of 12" % len(okins))
okan = [bb for bb in e5lib.COVERED if len(bench.okreps(bb, "ucfs-ANALYSIS")) >= 3]
(ok if len(okan) >= 2 else ko)("ucfs-ANALYSIS ok in >= 3 measured reps on covered %s" % okan)
tbad = []
for r in bench.runs:
    if r["status"] == "ok":
        pr = e5lib.time_problems(r["run"], list(bench.v.get((r["bench"], r["run"], r["rep"]), {}).items()), float(r["wall_s"]))
        if pr:
            tbad.append("%s %s rep%s: %s" % (r["bench"], r["run"], r["rep"], pr[0]))
(ok if not tbad else ko)("times of every ok run consistent (phases, kernel + UCFS inside pureRun, <= wall) %s" % tbad[:3])
kbad, kn = [], 0
for bb in e5lib.BENCHES:
    for run in e5lib.RUNS[1:]:
        if len(bench.okreps(bb, run)) >= 3 and bench.okreps(bb, "insens"):
            kr = e5tables.kernel_ratio(bench, bb, run)
            kn += 1
            if kr is None or not 0.67 <= kr <= 1.5:
                kbad.append("%s %s %s" % (bb, run, kr if kr is None else "%.2f" % kr))
(ok if kn and not kbad else ko)("kernel/Spark medians in [0.67, 1.5] on %d (bench, run) %s" % (kn, kbad))
abad = 0
for bb in e5lib.BENCHES:
    for run in e5lib.RUNS:
        reps = bench.okreps(bb, run)
        if not reps:
            continue
        ref = e5lib.e4_answer(e4, bb, run)
        seen = {}
        for k in reps:
            for key, val in bench.v[(bb, run, k)].items():
                if not e5lib.is_measure(key):
                    seen.setdefault(key, set()).add(val)
        if set(seen) != set(ref) or any(ref[k] not in seen[k] for k in ref):
            abad += 1
            ko("%s %s: answer keys/values vs E4: %s" % (bb, run, sorted(k for k in set(seen) | set(ref)
                                                                         if ref.get(k) not in seen.get(k, set()))[:6]))
(ok if abad == 0 else ko)("answers: every E4 value observed, key sets equal")

# 9. minheap
(ok if [(m["bench"], m["run"]) for m in mins] == pairs else ko)("minheap.tsv: %d searches" % len(mins))
for m in mins:
    ss = [s for s in steps if (s["bench"], s["run"]) == (m["bench"], m["run"])]
    probs, st, hi, lo = e5lib.replay_minheap(ss)
    if st and not st.startswith("ref-") and refans.get((m["bench"], m["run"])) != e5lib.e4_answer(e4, m["bench"], m["run"]):
        probs.append("reference answer != E4")
    if (m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"]) != (st, "-" if hi is None else str(hi),
                                                                      "-" if lo is None else str(lo), str(len(ss))):
        probs.append("row %s, replay %s %s %s %d" % ((m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"]), st, hi, lo, len(ss)))
    (ko if probs else ok)("minheap %s %s: %s" % (m["bench"], m["run"], "; ".join(probs) if probs else "%s %s MB" % (st, hi)))
pp = e5lib.minheap_plausibility(mins)
(ok if not pp else ko)("minheap rows with status ok plausible %s" % (pp or ""))
both = [bb for bb in e5lib.COVERED if all(mrow.get((bb, r), {}).get("status") == "ok" for r in ("insens", "ucfs-ANALYSIS"))]
(ok if len(both) >= 2 else ko)("minheap ok for insens and ucfs-ANALYSIS on covered %s" % both)

# 10. secrets
hits = e5lib.scan_paths([R])
(ok if not hits else ko)("no secret in the committed results and their archives %s" % [
    (os.path.relpath(f.split("!")[0], R), k, s[:12]) for f, k, s in hits[:5]])

# 11. repro
rp = e5tables.Part(repro)
for bb in ("pmd", "luindex"):
    for run in ("insens", "ucfs-ANALYSIS"):
        d = rp.v.get((bb, run, "1"), {})
        got = {k: v for k, v in d.items() if not e5lib.is_measure(k)}
        reps = bench.okreps(bb, run)
        com = {k: v for k, v in bench.v.get((bb, run, reps[0]), {}).items() if not e5lib.is_measure(k)} if reps else {}
        row = [r for r in rp.runs if (r["bench"], r["run"], r["rep"]) == (bb, run, "1")]
        tp = e5lib.time_problems(run, list(d.items()), float(row[0]["wall_s"])) if row else ["no row"]
        (ok if got and got == com and not tp else ko)("repro %s %s: %d answer keys = committed, times consistent %s" % (
            bb, run, len(got), tp[:1]))

# 12.
try:
    t = e5tables.render(R)
    (ok if len(t) == 8 else ko)("e5tables.py renders %d tables" % len(t))
except Exception as e:
    ko("e5tables.py: %r" % e)
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S5-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S5
finish S5_results
