#!/usr/bin/env bash
# E5-S5 acceptance: the committed results of the final E5 run (docs/ai/tickets/E5-S5.md), in
# docs/ucfs-integration/e5-results/ (R below).
#  1. files: R/{setup.tsv,host.txt,full.tsv,full.log,raw.tar.xz}, R/bench/{runs,values,meta}.tsv + bench.log,
#     R/minheap/{minheap,steps,meta}.tsv + minheap.log, R/probe-cg and R/probe-jdk {runs,values,meta}.tsv +
#     bench.log;
#  2. one host and one build: the four meta.tsv agree on git-head, tree-clean (yes), jar-sha256, host-kind,
#     flavor, cpu-model, cpu-count, mem-total-mb, kernel, os, java-version; git-head = setup.tsv commit and
#     git-head; jar-sha256 = setup.tsv jar-sha256; java-version is Temurin 21.0.12.1+1 (setup.tsv); cpu-model
#     is the "Model name" of lscpu in host.txt; host-kind vm with a flavor name (<family>-<cpu>-<ram>) and
#     other-java 0 in every part, or host-kind local and R/fallback.txt with a line "lead-decision: ..."
#     (the lead's fallback, E5.md);
#  3. the results come from the code of HEAD: git-head is a commit of this repository, an ancestor of HEAD,
#     and `git diff <git-head> HEAD` is empty for qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src
#     scripts/ucfs gradle.properties *.gradle settings.gradle artifact/benchmarks;
#  4. full.tsv: parts bench, minheap, probe-cg, probe-jdk in this order, each exit 0;
#  5. the parameters fixed in E5.md: bench reps 10, warmup 1, timeout 900, xmx 16g, the 12 benchmarks, runs
#     "insens ucfs-ANALYSIS ucfs-CALL_GRAPH", the default skip, jdk-bodies no; minheap on the 6 covered
#     benchmarks, the 3 runs, default skip, hi 16384, lo 64, gran 16, factor 3, timeout 900; probe-cg
#     ucfs-CALL_GRAPH on antlr bloat checkstyle, reps 1, warmup 0, skip "", timeout 3600, xmx 52g; probe-jdk insens and
#     ucfs-ANALYSIS on luindex, jdk-bodies yes, same limits;
#  6. the TSV files are the run directories: raw.tar.xz holds cmd.txt, out.txt, time.txt, exit, load1 of every
#     run directory of the four parts; runs.tsv/values.tsv of bench, probe-cg, probe-jdk and steps.tsv of
#     minheap are re-derived here from them (e5lib.parse_time/parse_out, own status rule) and must be equal;
#  7. bench: 11 rows (rep 0..10) for every benchmark and run except the skipped ones; insens ok in all 10
#     measured repetitions on all 12; ucfs-ANALYSIS ok in >= 3 measured repetitions on >= 2 covered
#     benchmarks; every ok ucfs run has the phase lines of E5-S1; in every (bench, run) the answer key set =
#     the E4 one and every E4 value is among the values observed (a varying key is a result, table T7);
#  8. minheap: 16 searches (6 covered x 3 runs - 2 skipped); each replays the rule of E5-S3 (e5lib.replay_minheap) and its
#     reference answer = the E4 answer; minheap.tsv rows = the replay;
#  9. the code of HEAD gives the same answer here: e5-bench.sh REPS=1 WARMUP=0 RUNS="insens ucfs-ANALYSIS" on
#     pmd luindex with a fresh jar -> answer keys = those of R/bench (time differs, not compared);
# 10. acceptance/E5/e5tables.py renders the eight tables from R; tracked files unchanged.
# Usage: bash acceptance/E5/S5_results.sh          (exit 0 = PASS; about 3 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
R="$ROOT/docs/ucfs-integration/e5-results"
[ -d "$R" ] || { fail "no $R"; finish S5_results; }

for f in setup.tsv host.txt full.tsv full.log raw.tar.xz bench/runs.tsv bench/values.tsv bench/meta.tsv bench/bench.log \
         minheap/minheap.tsv minheap/steps.tsv minheap/meta.tsv minheap/minheap.log \
         probe-cg/runs.tsv probe-cg/values.tsv probe-cg/meta.tsv probe-cg/bench.log \
         probe-jdk/runs.tsv probe-jdk/values.tsv probe-jdk/meta.tsv probe-jdk/bench.log; do
    [ -f "$R/$f" ] && pass "file $f" || fail "missing $f"
done

GH="$(py -c 'import e5lib,sys;print(e5lib.read_meta(sys.argv[1]).get("git-head",""))' "$R/bench/meta.tsv" 2>/dev/null)"
if [ -n "$GH" ] && git cat-file -e "$GH^{commit}" 2>/dev/null; then
    pass "git-head $GH is a commit of this repository"
    git merge-base --is-ancestor "$GH" HEAD && pass "git-head is an ancestor of HEAD" || fail "git-head is not an ancestor of HEAD"
    if git diff --quiet "$GH" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/ucfs gradle.properties \
            '*.gradle' settings.gradle artifact/benchmarks; then
        pass "code at git-head = code at HEAD"
    else
        fail "code differs between git-head and HEAD: $(git diff --name-only "$GH" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/ucfs gradle.properties '*.gradle' settings.gradle artifact/benchmarks | head -n 5 | tr '\n' ' ')"
    fi
else
    fail "git-head '$GH' is not a commit of this repository"
fi

RAW="$OUT/raw"
safe_reset_dir "$RAW"
tar -xJf "$R/raw.tar.xz" -C "$RAW" 2>"$LOGS/S5-tar.txt" && pass "raw.tar.xz unpacks" || fail "raw.tar.xz does not unpack"

FRESH="$OUT/qilin-fat.jar"
REPRO="$OUT/repro"
safe_reset_dir "$REPRO"
if fresh_fatjar "$FRESH"; then
    QILIN_JAR="$FRESH" REPS=1 WARMUP=0 RUNS="insens ucfs-ANALYSIS" XMX=8g bash scripts/ucfs/e5-bench.sh "$REPRO" pmd luindex \
        > "$LOGS/S5-repro.txt" 2>&1 || fail "e5-bench.sh repro exit $?"
else
    fail "fat jar build"
fi

py - "$R" "$RAW" "$E4_RESULTS" "$REPRO" > "$LOGS/S5-check.txt" 2>&1 <<'PY'
import os, re, sys
import e5lib, e5tables
R, raw, e4dir, repro = sys.argv[1:5]
e4 = e5lib.e4_values(e4dir)
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
setup = e5lib.read_meta(os.path.join(R, "setup.tsv")) if os.path.isfile(os.path.join(R, "setup.tsv")) else {}
parts = ["bench", "minheap", "probe-cg", "probe-jdk"]
M = {p: meta(p) for p in parts}
SAME = ["git-head", "tree-clean", "jar-sha256", "host-kind", "flavor", "cpu-model", "cpu-count", "mem-total-mb",
        "kernel", "os", "java-version"]
for k in SAME:
    vs = {M[p].get(k) for p in parts}
    (ok if len(vs) == 1 and None not in vs else ko)("meta %s equal in the four parts: %s" % (k, vs))
b = M["bench"]
(ok if b.get("tree-clean") == "yes" else ko)("tree-clean yes")
(ok if b.get("git-head") and b.get("git-head") == setup.get("commit") == setup.get("git-head") else ko)(
    "git-head = setup.tsv commit = setup.tsv git-head")
(ok if b.get("jar-sha256") and b.get("jar-sha256") == setup.get("jar-sha256") else ko)("jar-sha256 = setup.tsv jar-sha256")
(ok if b.get("java-version") == setup.get("java-version") and "Temurin-21.0.12.1+1" in b.get("java-version", "") else ko)(
    "java-version Temurin 21.0.12.1+1 = setup.tsv")
host = open(os.path.join(R, "host.txt"), errors="replace").read() if os.path.isfile(os.path.join(R, "host.txt")) else ""
mm = re.search(r"^Model name:\s*(.+?)\s*$", host, re.M)
(ok if mm and mm.group(1) == b.get("cpu-model") else ko)("cpu-model = lscpu Model name of host.txt")
if b.get("host-kind") == "vm":
    (ok if re.fullmatch(r"[a-z0-9]+-\d+-\d+", b.get("flavor", "")) else ko)("host-kind vm, flavor %r" % b.get("flavor"))
    (ok if all(M[p].get("other-java") == "0" for p in parts) else ko)("vm: other-java 0 in every part")
else:
    fb = os.path.join(R, "fallback.txt")
    (ok if os.path.isfile(fb) and any(l.startswith("lead-decision: ") for l in open(fb)) else ko)(
        "host-kind %s: fallback.txt with lead-decision" % b.get("host-kind"))

ft = e5lib.read_tsv(os.path.join(R, "full.tsv")) if os.path.isfile(os.path.join(R, "full.tsv")) else []
(ok if [(r["part"], r["exit"]) for r in ft] == [(p, "0") for p in parts] else ko)("full.tsv parts %s" % [(r["part"], r["exit"]) for r in ft])

# 5. parameters
want = {"bench": {"reps": "10", "warmup": "1", "timeout": "900", "xmx": "16g", "benches": " ".join(e5lib.BENCHES),
                  "runs": " ".join(e5lib.RUNS), "skip": "antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH", "jdk-bodies": "no"},
        "minheap": {"benches": " ".join(e5lib.COVERED), "runs": " ".join(e5lib.RUNS),
                    "skip": "antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH", "hi-mb": "16384", "lo-mb": "64", "gran-mb": "16",
                    "timeout-factor": "3", "timeout": "900"},
        "probe-cg": {"runs": "ucfs-CALL_GRAPH", "benches": "antlr bloat checkstyle", "reps": "1", "warmup": "0", "skip": "",
                     "timeout": "3600", "xmx": "52g", "jdk-bodies": "no"},
        "probe-jdk": {"runs": "insens ucfs-ANALYSIS", "benches": "luindex", "reps": "1", "warmup": "0", "skip": "",
                      "timeout": "3600", "xmx": "52g", "jdk-bodies": "yes"}}
for p, w in want.items():
    bad = {k: (M[p].get(k), v) for k, v in w.items() if M[p].get(k) != v}
    (ok if not bad else ko)("%s parameters %s" % (p, bad or "as fixed in E5.md"))

# 6. re-derive from raw
def status(d):
    rc = int(open(os.path.join(d, "exit")).read().strip())
    txt = open(os.path.join(d, "out.txt"), errors="replace").read()
    if rc == 0:
        return "ok"
    if rc in (124, 137):
        return "timeout"
    if rc == 3 and "OutOfMemoryError" in txt:
        return "oom"
    return "error"
for p in ("bench", "probe-cg", "probe-jdk"):
    try:
        runs = e5lib.read_tsv(os.path.join(R, p, "runs.tsv"))
        vals = e5lib.read_tsv(os.path.join(R, p, "values.tsv"))
    except OSError:
        ko("%s: TSV missing" % p); continue
    V = {}
    for r in vals:
        V.setdefault((r["bench"], r["run"], r["rep"]), []).append((r["key"], r["value"]))
    bad = 0
    dirs = set()
    base = os.path.join(raw, p)
    for bb in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        for rr in sorted(os.listdir(os.path.join(base, bb))):
            for kk in sorted(os.listdir(os.path.join(base, bb, rr))):
                dirs.add((bb, rr, kk[3:]))
    if dirs != {(r["bench"], r["run"], r["rep"]) for r in runs}:
        ko("%s: run directories of raw.tar.xz %d != rows of runs.tsv %d" % (p, len(dirs), len(runs))); continue
    for r in runs:
        d = os.path.join(base, r["bench"], r["run"], "rep" + r["rep"])
        w, u, s, rss = e5lib.parse_time(os.path.join(d, "time.txt"))
        kv = e5lib.parse_out(open(os.path.join(d, "out.txt"), errors="replace").read())
        l1 = open(os.path.join(d, "load1")).read().strip()
        if (r["status"] != status(d) or r["exit"] != open(os.path.join(d, "exit")).read().strip()
                or abs(float(r["wall_s"]) - w) > 0.0051 or abs(float(r["user_s"]) - u) > 0.0051
                or abs(float(r["sys_s"]) - s) > 0.0051 or int(r["max_rss_mb"]) != rss or r["load1"] != l1
                or sorted(V.get((r["bench"], r["run"], r["rep"]), [])) != sorted(kv)):
            bad += 1
            if bad <= 3:
                ko("%s %s %s rep%s: row/values differ from the raw run directory" % (p, r["bench"], r["run"], r["rep"]))
    (ok if bad == 0 else ko)("%s: %d rows re-derived from raw.tar.xz, %d differ" % (p, len(runs), bad))
try:
    steps = e5lib.read_tsv(os.path.join(R, "minheap", "steps.tsv"))
    mins = e5lib.read_tsv(os.path.join(R, "minheap", "minheap.tsv"))
except OSError:
    steps, mins = [], []
bad = 0
refans = {}
for s in steps:
    d = os.path.join(raw, "minheap", s["bench"], s["run"], "x" + s["xmx_mb"])
    if not os.path.isfile(os.path.join(d, "exit")):
        bad += 1; continue
    st = status(d)
    ans = {k: v for k, v in e5lib.parse_out(open(os.path.join(d, "out.txt"), errors="replace").read()) if not e5lib.is_measure(k)}
    if s["step"] == "0":
        refans[(s["bench"], s["run"])] = ans
    elif st == "ok" and ans != refans.get((s["bench"], s["run"])):
        st = "differs"
    w = e5lib.parse_time(os.path.join(d, "time.txt"))[0]
    if st != s["status"] or abs(w - float(s["wall_s"])) > 0.0051:
        bad += 1
(ok if steps and bad == 0 else ko)("minheap: %d steps re-derived from raw.tar.xz, %d differ" % (len(steps), bad))

# 7. bench
bench = e5tables.Part(os.path.join(R, "bench"))
skip = set(tuple(x.split(":")) for x in want["bench"]["skip"].split())
for bb in e5lib.BENCHES:
    for run in e5lib.RUNS:
        rows = [r for r in bench.runs if (r["bench"], r["run"]) == (bb, run)]
        exp = [] if (bb, run) in skip else [str(k) for k in range(11)]
        if sorted(r["rep"] for r in rows) != sorted(exp):
            ko("%s %s: reps %s" % (bb, run, sorted(r["rep"] for r in rows)))
okins = [bb for bb in e5lib.BENCHES if len(bench.okreps(bb, "insens")) == 10]
(ok if len(okins) == 12 else ko)("insens ok in 10 measured reps on %d of 12" % len(okins))
okan = [bb for bb in e5lib.COVERED if len(bench.okreps(bb, "ucfs-ANALYSIS")) >= 3]
(ok if len(okan) >= 2 else ko)("ucfs-ANALYSIS ok in >= 3 measured reps on covered %s" % okan)
pbad = abad = 0
for (bb, run, rep), d in bench.v.items():
    st = [r["status"] for r in bench.runs if (r["bench"], r["run"], r["rep"]) == (bb, run, rep)]
    if st != ["ok"]:
        continue
    if run != "insens" and e5lib.phase_problems(list(d.items())):
        pbad += 1
(ok if pbad == 0 else ko)("phase lines of every ok ucfs run (%d bad)" % pbad)
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

# 8. minheap
pairs = [(bb, r) for bb in e5lib.COVERED for r in e5lib.RUNS if (bb, r) not in skip]
(ok if [(m["bench"], m["run"]) for m in mins] == pairs else ko)("minheap.tsv: %d searches" % len(mins))
for m in mins:
    ss = [s for s in steps if (s["bench"], s["run"]) == (m["bench"], m["run"])]
    probs, st, hi, lo = e5lib.replay_minheap(ss)
    if refans.get((m["bench"], m["run"])) != e5lib.e4_answer(e4, m["bench"], m["run"]) and st != None and not st.startswith("ref-"):
        probs.append("reference answer != E4")
    if st and (m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"]) != (st, str(hi) if hi else "-", str(lo) if lo else "-", str(len(ss))):
        probs.append("row %s, replay %s %s %s %d" % ((m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"]), st, hi, lo, len(ss)))
    (ko if probs else ok)("minheap %s %s: %s" % (m["bench"], m["run"], "; ".join(probs) if probs else "%s %s MB" % (st, hi)))

# 9. repro
rp = e5tables.Part(repro)
for bb in ("pmd", "luindex"):
    for run in ("insens", "ucfs-ANALYSIS"):
        got = {k: v for k, v in rp.v.get((bb, run, "1"), {}).items() if not e5lib.is_measure(k)}
        reps = bench.okreps(bb, run)
        com = {k: v for k, v in bench.v.get((bb, run, reps[0]), {}).items() if not e5lib.is_measure(k)} if reps else {}
        (ok if got and got == com else ko)("repro %s %s: %d answer keys = committed" % (bb, run, len(got)))

# 10.
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
