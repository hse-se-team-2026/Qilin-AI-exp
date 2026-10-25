#!/usr/bin/env bash
# E5-S3 acceptance: the minimum-heap search scripts/ucfs/e5-minheap.sh (docs/ai/tickets/E5-S3.md).
#  1. QILIN_JAR=<fresh fat jar> RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e5-minheap.sh <dir> pmd luindex
#     exits 0; stdout "e5-minheap: <bench> <run>" per search and the last line
#     "e5-minheap: 4 searches, <n> steps in <dir>";
#  2. steps.tsv "bench run step xmx_mb status exit wall_s max_rss_mb" and minheap.tsv "bench run status
#     minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s"; run directories
#     <dir>/<bench>/<run>/x<mb>/ with cmd.txt (-Xmx<mb>m -XX:+ExitOnOutOfMemoryError, the D3 options and the
#     run options of e5-bench.sh), out.txt, time.txt, exit;
#  3. the status of every step, re-derived here from exit and out.txt: ok = exit 0 and the answer keys
#     (e5lib: keys not ending in -ms, -s, -mb) equal those of step 0; differs = exit 0, other answer;
#     oom = exit 3 with OutOfMemoryError; timeout = exit 124 or 137; error otherwise;
#  4. the search rule, replayed from the statuses: step 0 at HI_MB (16384) with TIMEOUT, ok, and its answer =
#     the committed E4 answer of the run; step 1 at LO_MB (64); then mid = (lo + hi) // 2 while hi - lo >
#     GRAN_MB (16), hi = mid after ok, lo = mid otherwise; minheap_mb = hi, maxfail_mb = lo, status ok,
#     steps = number of steps; step_timeout_s = max(60, ceil(TIMEOUT_FACTOR (3) * ref_wall_s)) and no step
#     ran longer than it + 35 s;
#  5. independent of the script (this check runs java itself), with a margin of 2 x GRAN_MB against the
#     nondeterminism of GC at the threshold: -Xmx<minheap_mb + 32>m finishes with the E4 answer,
#     -Xmx<maxfail_mb - 32>m does not finish with it within step_timeout_s;
#  6. LO_MB=4096 RUNS=insens ... xalan -> status le-lo, minheap_mb 4096, 2 steps; TIMEOUT=3 RUNS=insens ...
#     chart -> status ref-timeout, 1 step;
#  7. exit 2 before any run: GRAN_MB=0, LO_MB=20000 (not below HI_MB), unknown run, unknown benchmark;
#  8. meta.tsv keys in order: command git-head tree-clean jar jar-sha256 benches runs skip timeout hi-mb lo-mb
#     gran-mb timeout-factor jvm-flags host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version
#     other-java load-start started finished (git-head = HEAD, tree-clean yes, jar-sha256 of the jar run);
#  9. tracked files unchanged.
# Usage: bash acceptance/E5/S3_minheap.sh          (exit 0 = PASS; about 6 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed"

FRESH="$OUT/qilin-fat.jar"
fresh_fatjar "$FRESH" || { fail "fat jar build"; finish S3_minheap; }

HD="$OUT/minheap"
safe_reset_dir "$HD"
QILIN_JAR="$FRESH" RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e5-minheap.sh "$HD" pmd luindex > "$LOGS/S3-minheap.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-minheap.sh pmd luindex exit 0" || fail "e5-minheap.sh exit $rc (see $LOGS/S3-minheap.txt)"

LD="$OUT/minheap-lo"
safe_reset_dir "$LD"
QILIN_JAR="$FRESH" LO_MB=4096 RUNS=insens bash scripts/ucfs/e5-minheap.sh "$LD" xalan > "$LOGS/S3-lo.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-minheap.sh LO_MB=4096 exit 0" || fail "e5-minheap.sh LO_MB=4096 exit $rc"
TD="$OUT/minheap-timeout"
safe_reset_dir "$TD"
QILIN_JAR="$FRESH" TIMEOUT=3 RUNS=insens bash scripts/ucfs/e5-minheap.sh "$TD" chart > "$LOGS/S3-timeout.txt" 2>&1
rc=$?
[ $rc -eq 0 ] && pass "e5-minheap.sh TIMEOUT=3 exit 0" || fail "e5-minheap.sh TIMEOUT=3 exit $rc"

bad() {
    local what="$1" rc
    shift
    env QILIN_JAR="$FRESH" "$@" > "$LOGS/S3-bad.txt" 2>&1
    rc=$?
    [ $rc -eq 2 ] && pass "$what: exit 2" || fail "$what: exit $rc"
}
BADD="$OUT/minheap-bad"
safe_reset_dir "$BADD"
bad "GRAN_MB=0" GRAN_MB=0 bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
bad "LO_MB=20000" LO_MB=20000 bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
bad "unknown run" RUNS="insens foo" bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
bad "unknown benchmark" bash scripts/ucfs/e5-minheap.sh "$BADD" nosuchbench
[ -z "$(find "$BADD" -name exit 2>/dev/null)" ] && pass "bad arguments: no run started" || fail "bad arguments: a run was started"

# 5. own confirmation runs at minheap + 32 and maxfail - 32 (arguments built here, as in acceptance/E4/lib.sh)
confirm() {
    local b="$1" run="$2" mb="$3" to="$4" dir opts rc
    dir="$OUT/confirm-$b-$run-$mb"
    safe_reset_dir "$dir"
    case "$run" in insens) opts="-pta=insens" ;; *) opts="-pta=ucfs -ucfsbinding=${run#ucfs-}" ;; esac
    # shellcheck disable=SC2086
    (cd "$dir" && timeout -k 30 "$to" "$JAVA" "-Xmx${mb}m" -XX:+ExitOnOutOfMemoryError -jar "$FRESH" -jre="$JRE_DIR" \
        $RUNPY_OPTS $opts $(dacapo_args "$b") -ucfsseam "-exclude=$JDK_EXCLUDE" > out.txt 2>&1 < /dev/null)
    rc=$?
    echo "$rc" > "$dir/exit"
}
if [ -f "$HD/minheap.tsv" ]; then
    while IFS=$'\t' read -r b run st mh mf n rw rr sto; do
        [ "$b" = bench ] && continue
        [ "$st" = ok ] || continue
        confirm "$b" "$run" $((mh + 32)) "$sto"
        [ $((mf - 32)) -ge 1 ] && confirm "$b" "$run" $((mf - 32)) "$sto"
    done < "$HD/minheap.tsv"
fi

py - "$HD" "$LD" "$TD" "$OUT" "$E4_RESULTS" "$LOGS/S3-minheap.txt" "$FRESH" "$(git rev-parse HEAD)" \
    > "$LOGS/S3-check.txt" 2>&1 <<'PY'
import hashlib, math, os, re, sys
import e5lib
hd, ld, td, out, e4dir, stdout, jar, head = sys.argv[1:9]
e4 = e5lib.e4_values(e4dir)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
SH = "bench run step xmx_mb status exit wall_s max_rss_mb".split()
MH = "bench run status minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s".split()

def header(p):
    with open(p) as f:
        return f.readline().rstrip("\n").split("\t")

def answer(d):
    return {k: v for k, v in e5lib.parse_out(open(os.path.join(d, "out.txt"), errors="replace").read())
            if not e5lib.is_measure(k)}

def status(d, ref):
    rc = int(open(os.path.join(d, "exit")).read().strip())
    txt = open(os.path.join(d, "out.txt"), errors="replace").read()
    if rc == 0:
        return "ok" if ref is None or answer(d) == ref else "differs"
    if rc == 3 and "OutOfMemoryError" in txt:
        return "oom"
    if rc in (124, 137):
        return "timeout"
    return "error"

lines = [l.strip() for l in open(stdout, errors="replace") if l.strip()]
want = ["e5-minheap: %s %s" % (b, r) for b in ("pmd", "luindex") for r in ("insens", "ucfs-ANALYSIS")]
(ok if [l for l in lines if re.fullmatch(r"e5-minheap: \S+ \S+", l)] == want else ko)("stdout search lines")
(ok if lines and re.fullmatch(r"e5-minheap: 4 searches, \d+ steps in " + re.escape(os.path.realpath(hd)), lines[-1])
 else ko)("stdout last line %s" % lines[-1:])
try:
    (ok if header(os.path.join(hd, "steps.tsv")) == SH else ko)("steps.tsv header")
    (ok if header(os.path.join(hd, "minheap.tsv")) == MH else ko)("minheap.tsv header")
    steps = e5lib.read_tsv(os.path.join(hd, "steps.tsv"))
    mins = e5lib.read_tsv(os.path.join(hd, "minheap.tsv"))
except OSError as e:
    ko(str(e)); steps, mins = [], []
(ok if [(r["bench"], r["run"]) for r in mins] == [(b, r) for b in ("pmd", "luindex") for r in ("insens", "ucfs-ANALYSIS")]
 else ko)("minheap.tsv rows %s" % [(r["bench"], r["run"]) for r in mins])
for m in mins:
    b, run = m["bench"], m["run"]
    ss = [s for s in steps if (s["bench"], s["run"]) == (b, run)]
    if [int(s["step"]) for s in ss] != list(range(len(ss))) or not ss:
        ko("%s %s: steps not numbered 0.." % (b, run)); continue
    d0 = os.path.join(hd, b, run, "x" + ss[0]["xmx_mb"])
    ref = answer(d0) if os.path.exists(os.path.join(d0, "out.txt")) else None
    probs = []
    if ss[0]["xmx_mb"] != "16384" or ss[0]["status"] != "ok":
        probs.append("step 0 %s %s" % (ss[0]["xmx_mb"], ss[0]["status"]))
    if ref != e5lib.e4_answer(e4, b, run):
        probs.append("step 0 answer != E4")
    for s in ss:
        d = os.path.join(hd, b, run, "x" + s["xmx_mb"])
        if not all(os.path.exists(os.path.join(d, f)) for f in ("cmd.txt", "out.txt", "time.txt", "exit")):
            probs.append("x%s files missing" % s["xmx_mb"]); continue
        t = open(os.path.join(d, "cmd.txt")).read().replace("\\", "").split()
        if "-Xmx%sm" % s["xmx_mb"] not in t or "-XX:+ExitOnOutOfMemoryError" not in t or "-ucfsseam" not in t \
                or not any(x.startswith("-exclude=java.*;") for x in t):
            probs.append("x%s cmd.txt" % s["xmx_mb"])
        st = status(d, ref if s["step"] != "0" else None)
        if st != s["status"] or s["exit"] != open(os.path.join(d, "exit")).read().strip():
            probs.append("x%s status %s, re-derived %s" % (s["xmx_mb"], s["status"], st))
        w = e5lib.parse_time(os.path.join(d, "time.txt"))[0]
        if abs(w - float(s["wall_s"])) > 0.0051:
            probs.append("x%s wall_s %s vs time.txt %.2f" % (s["xmx_mb"], s["wall_s"], w))
    # replay
    rw = float(ss[0]["wall_s"])
    sto = max(60, math.ceil(3 * rw))
    rp, rst, hi, lo = e5lib.replay_minheap(ss)
    probs += rp
    if rst != "ok":
        probs.append("replayed status %s" % rst)
        hi, lo = hi or 0, lo or 0
    if (m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"], m["ref_wall_s"], m["step_timeout_s"]) != \
            ("ok", str(hi), str(lo), str(len(ss)), ss[0]["wall_s"], str(sto)) or m["ref_rss_mb"] != ss[0]["max_rss_mb"]:
        probs.append("minheap.tsv row %s, expected ok %d %d %d %s %d" % (m, hi, lo, len(ss), ss[0]["wall_s"], sto))
    if any(float(s["wall_s"]) > sto + 35 for s in ss[1:]):
        probs.append("a step ran longer than step_timeout_s + 35")
    # 5. confirmation
    cu = os.path.join(out, "confirm-%s-%s-%d" % (b, run, hi + 32))
    cd = os.path.join(out, "confirm-%s-%s-%d" % (b, run, lo - 32))
    if not os.path.exists(os.path.join(cu, "exit")) or status(cu, ref) != "ok":
        probs.append("confirm at %d MB: not ok" % (hi + 32))
    if lo - 32 >= 1 and (not os.path.exists(os.path.join(cd, "exit")) or status(cd, ref) == "ok"):
        probs.append("confirm at %d MB: finished with the answer" % (lo - 32))
    if probs:
        ko("%s %s: %s" % (b, run, "; ".join(probs)))
    else:
        ok("%s %s: %d steps, minheap %s MB, maxfail %s MB, confirmed at %d (ok) and %d (not ok)" % (
            b, run, len(ss), hi, lo, hi + 32, lo - 32))

# 6.
try:
    r6 = e5lib.read_tsv(os.path.join(ld, "minheap.tsv"))
    (ok if [(r["status"], r["minheap_mb"], r["steps"]) for r in r6] == [("le-lo", "4096", "2")] else ko)("LO_MB=4096 xalan: %s" % r6)
    r6 = e5lib.read_tsv(os.path.join(td, "minheap.tsv"))
    (ok if [(r["status"], r["steps"]) for r in r6] == [("ref-timeout", "1")] else ko)("TIMEOUT=3 chart: %s" % r6)
except OSError as e:
    ko(str(e))

# 8.
try:
    with open(os.path.join(hd, "meta.tsv")) as f:
        mh = f.readline().rstrip("\n")
    meta = e5lib.read_tsv(os.path.join(hd, "meta.tsv"))
except OSError:
    mh, meta = "", []
WANT = ("command git-head tree-clean jar jar-sha256 benches runs skip timeout hi-mb lo-mb gran-mb timeout-factor "
        "jvm-flags host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version other-java load-start "
        "started finished").split()
mm = {r["key"]: r["value"] for r in meta}
(ok if mh == "key\tvalue" and [r["key"] for r in meta] == WANT and mm.get("git-head") == head
 and mm.get("tree-clean") == "yes" and mm.get("jar-sha256") == hashlib.sha256(open(jar, "rb").read()).hexdigest()
 and (mm.get("hi-mb"), mm.get("lo-mb"), mm.get("gran-mb"), mm.get("timeout-factor"), mm.get("timeout")) == ("16384", "64", "16", "3", "900")
 else ko)("meta.tsv keys and values %s" % mm)
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S3-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S3
finish S3_minheap
