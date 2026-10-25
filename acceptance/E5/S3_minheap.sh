#!/usr/bin/env bash
# E5-S3 acceptance: the minimum-heap search scripts/ucfs/e5-minheap.sh (docs/ai/tickets/E5-S3.md).
#  1. QILIN_JAR=<fresh fat jar> RUNS="insens ucfs-ANALYSIS" bash scripts/ucfs/e5-minheap.sh <dir> pmd luindex
#     exits 0; stdout "e5-minheap: <bench> <run>" per search and the last line
#     "e5-minheap: 4 searches, <n> steps in <dir>";
#  2. steps.tsv "bench run step xmx_mb status exit wall_s max_rss_mb other_java start_ns end_ns" and minheap.tsv
#     "bench run status minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s"; step directories
#     <dir>/<bench>/<run>/s<step>-x<mb>/ with the files of e5lib.RUN_FILES; cmd.txt token for token
#     e5lib.expected_cmd with -Xmx<mb>m (the D3 options and the run options of e5-bench.sh, nothing else);
#  3. the status of every step, re-derived here from its files: e5lib.status_of (ok, timeout, killed, oom,
#     error) with the step's time limit, and differs = exit 0 with answer keys other than those of step 0;
#     the other columns = the files;
#  4. the search rule, replayed from the statuses (e5lib.replay_minheap): step 0 at HI_MB (16384) with TIMEOUT,
#     ok, its answer = the committed E4 answer; then LO_MB (64); then mid = (lo + hi) // 2 while hi - lo >
#     GRAN_MB (16), hi = mid after ok, lo = mid otherwise; a step with status error is repeated once at the
#     same -Xmx and a second error ends the search with status error; then the confirmation steps at
#     minheap + 32 (must be ok) and maxfail - 32 (must not be ok): status ok, else unconfirmed; the row of
#     minheap.tsv = the replay; step_timeout_s = max(60, ceil(TIMEOUT_FACTOR (3) * ref_wall_s)); no step ran
#     longer than its limit + 35 s; all four searches have status ok and are plausible
#     (e5lib.minheap_plausibility: minheap_mb <= ref_rss_mb; ucfs-ANALYSIS >= insens - 32);
#  5. independent of the script (this check runs java itself), with a margin of 2 x GRAN_MB against the
#     nondeterminism of GC at the threshold: -Xmx<minheap_mb + 32>m finishes with the E4 answer,
#     -Xmx<maxfail_mb - 32>m does not finish with it within step_timeout_s;
#  6. the steps ran one after the other in step order (e5lib.interval_problems) inside meta started..finished;
#  7. a step that fails for another reason than the heap (fault injection: JAVA_HOME is a copy of the JDK whose
#     bin/java is a script of this check that exits 1, or sleeps, at -Xmx8224m, the first middle step, and
#     runs the real java otherwise; pmd insens): error once -> the step is repeated and the search ends ok;
#     error every time -> two steps at 8224 MB and status error with no step after them; a spurious timeout
#     at 8224 MB (the critic's mutant MAJOR-5) -> the search is pushed above 8224 MB and the confirmation at
#     maxfail - 32 finishes ok -> status unconfirmed (not ok);
#  8. LO_MB=4096 RUNS=insens ... xalan -> status le-lo, minheap_mb 4096, 2 steps; TIMEOUT=3 RUNS=insens ...
#     chart -> status ref-timeout, 1 step;
#  9. exit 2 before any run: GRAN_MB=0, LO_MB=20000 (not below HI_MB), LO_MB=32 (the confirmation step would be
#     at <= 0), unknown run, unknown benchmark, JAVA_TOOL_OPTIONS=-Xint;
# 10. meta.tsv keys in order: command git-head tree-clean jar jar-sha256 benches runs skip timeout hi-mb lo-mb
#     gran-mb timeout-factor jvm-flags java-tool-options java-options jdk-java-options host-kind flavor cpu-model
#     cpu-count mem-total-mb kernel os java-version other-java load-start started finished (git-head = HEAD,
#     tree-clean yes, jar-sha256 of the jar run, the java option keys empty);
# 11. tracked files unchanged.
# Usage: bash acceptance/E5/S3_minheap.sh          (exit 0 = PASS; about 15 min, run it detached, E5.md)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
java_env_clean
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

# 7. fault injection: a JDK whose bin/java fails at -Xmx8224m (mode once / always / sleep), real java otherwise
FAULT_MB=8224
fake_jdk() {
    local d="$1" mode="$2" f
    rm -rf "$d"; mkdir -p "$d/bin"
    for f in "$JAVA_HOME"/*; do [ "$(basename "$f")" = bin ] || ln -s "$f" "$d/$(basename "$f")"; done
    for f in "$JAVA_HOME"/bin/*; do [ "$(basename "$f")" = java ] || ln -s "$f" "$d/bin/$(basename "$f")"; done
    cat > "$d/bin/java" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
    if [ "\$a" = "-Xmx${FAULT_MB}m" ]; then
        case "$mode" in
            once) if [ ! -e "$d/fired" ]; then touch "$d/fired"; echo "injected error" >&2; exit 1; fi ;;
            always) echo "injected error" >&2; exit 1 ;;
            sleep) exec sleep 100000 ;;
        esac
    fi
done
exec "$JAVA_HOME/bin/java" "\$@"
EOF
    chmod +x "$d/bin/java"
}
for mode in once always sleep; do
    fake_jdk "$OUT/fakejdk-$mode" "$mode"
    FD="$OUT/minheap-fault-$mode"
    safe_reset_dir "$FD"
    JAVA_HOME="$OUT/fakejdk-$mode" QILIN_JAR="$FRESH" RUNS=insens bash scripts/ucfs/e5-minheap.sh "$FD" pmd \
        > "$LOGS/S3-fault-$mode.txt" 2>&1
    rc=$?
    [ $rc -eq 0 ] && pass "e5-minheap.sh with the fault '$mode' exit 0" || fail "e5-minheap.sh fault '$mode': exit $rc"
done

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
bad "LO_MB=32" LO_MB=32 bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
bad "unknown run" RUNS="insens foo" bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
bad "unknown benchmark" bash scripts/ucfs/e5-minheap.sh "$BADD" nosuchbench
bad "JAVA_TOOL_OPTIONS=-Xint" JAVA_TOOL_OPTIONS=-Xint bash scripts/ucfs/e5-minheap.sh "$BADD" xalan
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

py - "$HD" "$LD" "$TD" "$OUT" "$E4_RESULTS" "$LOGS/S3-minheap.txt" "$FRESH" "$(git rev-parse HEAD)" "$ROOT" "$JAVA" \
    "$FAULT_MB" > "$LOGS/S3-check.txt" 2>&1 <<'PY'
import hashlib, math, os, re, sys
import e5lib
hd, ld, td, out, e4dir, stdout, jar, head, root, java, fault_mb = sys.argv[1:12]
jar, fault_mb = os.path.realpath(jar), int(fault_mb)
e4 = e5lib.e4_values(e4dir)
bmap = e5lib.bench_map(root)
fails = 0
def ok(m): print("PASS: " + m)
def ko(m):
    global fails
    fails += 1
    print("FAIL: " + m)
SH = "bench run step xmx_mb status exit wall_s max_rss_mb other_java start_ns end_ns".split()
MH = "bench run status minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s".split()
META = ("command git-head tree-clean jar jar-sha256 benches runs skip timeout hi-mb lo-mb gran-mb timeout-factor "
        "jvm-flags java-tool-options java-options jdk-java-options host-kind flavor cpu-model cpu-count mem-total-mb "
        "kernel os java-version other-java load-start started finished").split()

def answer(d):
    return e5lib.answer_of(e5lib.read(os.path.join(d, "out.txt"), ""))

def status(d, ref, timeout):
    """e5lib.status_of of the files of d, and differs for an ok step whose answer is not ref"""
    rc = int(e5lib.read(os.path.join(d, "exit"), "-1").strip())
    st = e5lib.status_of(rc, e5lib.read(os.path.join(d, "out.txt"), ""), e5lib.parse_time(os.path.join(d, "time.txt"))[0]
                         if os.path.isfile(os.path.join(d, "time.txt")) else 0.0, timeout)
    return "differs" if st == "ok" and ref is not None and answer(d) != ref else st

def search(dd, label, java_bin, lo_mb=64, expect=None):
    """checks one output directory of e5-minheap.sh; returns {(bench, run): (row, steps)}"""
    res = {}
    try:
        (ok if e5lib.header(os.path.join(dd, "steps.tsv")) == SH else ko)("%s: steps.tsv header" % label)
        (ok if e5lib.header(os.path.join(dd, "minheap.tsv")) == MH else ko)("%s: minheap.tsv header" % label)
        steps = e5lib.read_tsv(os.path.join(dd, "steps.tsv"))
        mins = e5lib.read_tsv(os.path.join(dd, "minheap.tsv"))
        meta = e5lib.read_meta(os.path.join(dd, "meta.tsv"))
    except OSError as e:
        ko("%s: %s" % (label, e)); return res
    items = []
    for m in mins:
        b, run = m["bench"], m["run"]
        ss = [s for s in steps if (s["bench"], s["run"]) == (b, run)]
        probs = []
        ref = None
        step_to = int(meta.get("timeout", "900"))
        for s in ss:
            d = os.path.join(dd, b, run, "s%s-x%s" % (s["step"], s["xmx_mb"]))
            lab = "%s %s %s step %s" % (label, b, run, s["step"])
            f = e5lib.read_run(d)
            if f is None:
                probs.append("step %s: files %s missing" % (s["step"], e5lib.run_files_missing(d))); continue
            items.append((lab, f["start"], f["end"], f["wall"]))
            if s["step"] == "0":
                ref = answer(d) if f["exit"] == "0" else None
                st = status(d, None, step_to)
                if ref != e5lib.e4_answer(e4, b, run):
                    probs.append("step 0 answer != E4")
            else:
                st = status(d, ref, int(m["step_timeout_s"]) if m["step_timeout_s"] != "-" else step_to)
            want = {"status": st, "exit": f["exit"], "max_rss_mb": str(f["rss"]), "other_java": str(f["other_java"]),
                    "start_ns": str(f["start"]), "end_ns": str(f["end"])}
            diff = ["%s %r != %r" % (k, s.get(k), v) for k, v in want.items() if s.get(k) != v]
            if abs(f["wall"] - float(s["wall_s"])) > 0.0051:
                diff.append("wall_s %s != %.2f" % (s["wall_s"], f["wall"]))
            cp = e5lib.cmd_problem(f["cmd"], e5lib.expected_cmd(java_bin, jar, s["xmx_mb"] + "m", run, b, root, bmap))
            if cp:
                diff.append("cmd.txt: " + cp)
            if f["picked_up"]:
                diff.append("JVM options picked up from the environment")
            limit = step_to if s["step"] == "0" else int(m["step_timeout_s"])
            if f["wall"] > limit + 35:
                diff.append("ran %.0f s, longer than its limit %d + 35" % (f["wall"], limit))
            if diff:
                probs.append("step %s x%s: %s" % (s["step"], s["xmx_mb"], "; ".join(diff)))
        rp, rst, hi, lo = e5lib.replay_minheap(ss, lo_mb=lo_mb)
        probs += rp
        sto = "-" if rst is None or rst.startswith("ref-") else str(max(60, math.ceil(3 * float(ss[0]["wall_s"]))))
        want = (rst, "-" if hi is None else str(hi), "-" if lo is None else str(lo), str(len(ss)), ss[0]["wall_s"] if ss else "-",
                ss[0]["max_rss_mb"] if ss else "-", sto)
        have = (m["status"], m["minheap_mb"], m["maxfail_mb"], m["steps"], m["ref_wall_s"], m["ref_rss_mb"], m["step_timeout_s"])
        if have != want:
            probs.append("minheap.tsv row %s, replay %s" % (have, want))
        res[(b, run)] = (m, ss, probs)
    ip = e5lib.interval_problems(items)
    try:
        a, z = e5lib.iso_epoch(meta["started"]) - 1, e5lib.iso_epoch(meta["finished"]) + 1
        ip += ["%s outside meta started..finished" % lab for lab, s, e, _ in items if s is None or e is None
               or s / 1e9 < a or e / 1e9 > z]
    except (KeyError, ValueError) as e:
        ip.append("meta started/finished %r" % e)
    (ok if not ip else ko)("%s: %d steps one after the other in step order %s" % (label, len(items), ip[:3] if ip else ""))
    return res

# 1.
lines = [l.strip() for l in open(stdout, errors="replace") if l.strip()]
want = ["e5-minheap: %s %s" % (b, r) for b in ("pmd", "luindex") for r in ("insens", "ucfs-ANALYSIS")]
(ok if [l for l in lines if re.fullmatch(r"e5-minheap: \S+ \S+", l)] == want else ko)("stdout search lines")
(ok if lines and re.fullmatch(r"e5-minheap: 4 searches, \d+ steps in " + re.escape(os.path.realpath(hd)), lines[-1])
 else ko)("stdout last line %s" % lines[-1:])
# 2-6 main
res = search(hd, "main", java)
(ok if sorted(res) == sorted((b, r) for b in ("pmd", "luindex") for r in ("insens", "ucfs-ANALYSIS")) else ko)(
    "minheap.tsv rows %s" % sorted(res))
for (b, run), (m, ss, probs) in sorted(res.items()):
    hi, lo = m["minheap_mb"], m["maxfail_mb"]
    if m["status"] != "ok":
        probs.append("status %s, expected ok" % m["status"])
    else:
        cu = os.path.join(out, "confirm-%s-%s-%d" % (b, run, int(hi) + 32))
        cd = os.path.join(out, "confirm-%s-%s-%d" % (b, run, int(lo) - 32))
        ref = e5lib.e4_answer(e4, b, run)
        if not os.path.exists(os.path.join(cu, "exit")) or e5lib.read(os.path.join(cu, "exit")).strip() != "0" or answer(cu) != ref:
            probs.append("own confirmation at %d MB: not ok" % (int(hi) + 32))
        if os.path.exists(os.path.join(cd, "exit")) and e5lib.read(os.path.join(cd, "exit")).strip() == "0" and answer(cd) == ref:
            probs.append("own confirmation at %d MB: finished with the answer" % (int(lo) - 32))
    if probs:
        ko("%s %s: %s" % (b, run, "; ".join(probs)))
    else:
        ok("%s %s: %d steps, replayed, minheap %s MB, maxfail %s MB, confirmed by the script and here at %d (ok) and %d (not ok)" % (
            b, run, len(ss), hi, lo, int(hi) + 32, int(lo) - 32))
pp = e5lib.minheap_plausibility([m for m, _, _ in res.values()])
(ok if not pp else ko)("plausible: minheap <= RSS of the reference, ucfs-ANALYSIS >= insens - 32 %s" % (pp or ""))
# 7. fault injection
for mode, want_st in (("once", "ok"), ("always", "error"), ("sleep", "unconfirmed")):
    r = search(os.path.join(out, "minheap-fault-" + mode), "fault-" + mode, os.path.join(out, "fakejdk-" + mode, "bin", "java"))
    m, ss, probs = r.get(("pmd", "insens"), ({}, [], ["no row"]))
    at = [s["status"] for s in ss if s["xmx_mb"] == str(fault_mb)]
    exp_at = {"once": ["error", "ok"], "always": ["error", "error"], "sleep": ["timeout"]}[mode]
    if at != exp_at:
        probs.append("steps at %d MB: %s, expected %s" % (fault_mb, at, exp_at))
    if mode == "always" and ss and ss[-1]["xmx_mb"] != str(fault_mb):
        probs.append("steps after the second error")
    if m.get("status") != want_st:
        probs.append("status %s, expected %s" % (m.get("status"), want_st))
    (ko if probs else ok)("fault '%s' at %d MB: status %s, steps there %s %s" % (mode, fault_mb, m.get("status"), at,
                                                                               "; ".join(probs)))
# 8.
try:
    r8 = e5lib.read_tsv(os.path.join(ld, "minheap.tsv"))
    (ok if [(r["status"], r["minheap_mb"], r["steps"]) for r in r8] == [("le-lo", "4096", "2")] else ko)("LO_MB=4096 xalan: %s" % r8)
    r8 = e5lib.read_tsv(os.path.join(td, "minheap.tsv"))
    (ok if [(r["status"], r["steps"]) for r in r8] == [("ref-timeout", "1")] else ko)("TIMEOUT=3 chart: %s" % r8)
except OSError as e:
    ko(str(e))
search(ld, "le-lo", java, lo_mb=4096)
search(td, "ref-timeout", java)
# 10.
try:
    with open(os.path.join(hd, "meta.tsv")) as f:
        mh = f.readline().rstrip("\n")
    meta = e5lib.read_tsv(os.path.join(hd, "meta.tsv"))
except OSError:
    mh, meta = "", []
mm = {r["key"]: r["value"] for r in meta}
(ok if mh == "key\tvalue" and [r["key"] for r in meta] == META and mm.get("git-head") == head
 and mm.get("tree-clean") == "yes" and mm.get("jar-sha256") == hashlib.sha256(open(jar, "rb").read()).hexdigest()
 and (mm.get("hi-mb"), mm.get("lo-mb"), mm.get("gran-mb"), mm.get("timeout-factor"), mm.get("timeout")) == ("16384", "64", "16", "3", "900")
 and (mm.get("java-tool-options"), mm.get("java-options"), mm.get("jdk-java-options")) == ("", "", "")
 else ko)("meta.tsv keys and values %s" % [r["key"] for r in meta])
sys.exit(1 if fails else 0)
PY
rc=$?
cat "$LOGS/S3-check.txt"
[ $rc -eq 0 ] || FAILS=$((FAILS + 1))
tracked_clean S3
finish S3_minheap
