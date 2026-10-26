#!/usr/bin/env bash
# E5 minimum heap: for each (benchmark, run) the smallest -Xmx, in steps of GRAN_MB, at which the run finishes
# with the answer of the reference run in at most TIMEOUT_FACTOR times its wall time (E5.md D3; the main memory
# measure of E5, peak RSS of e5-bench.sh is the second one). A step is one JVM with the command line of
# e5-bench.sh for the same run and -Xmx<mb>m (scripts/ucfs/e5-lib.sh, e5_command); the steps go one after
# another, nothing else of this script runs in parallel with a step.
# Contract: docs/ai/tickets/E5-S3.md (in the Diploma_work docs, not in this repository).
#
# Usage: bash scripts/ucfs/e5-minheap.sh <out-dir> <bench>...
#   <bench> is a name of artifact/util/benchmark.py (as for e5-bench.sh). Wrong arguments or environment (below)
#   exit 2 before the first run. Exit 0 when every search was made and the TSV files are written; the outcome of
#   a search is its row in minheap.tsv, not the exit code of this script.
#
# The search of one (benchmark, run), in the order benchmark, then run of RUNS ((bench, run) of SKIP left out):
#   step 0, the reference: -Xmx<HI_MB>m with the limit TIMEOUT. Its answer is the set of the keys of its output
#     that do not end in -ms, -s or -mb (as e5-bench.sh parses them: "#<key>: <value>" and the result lines of
#     Qilin). Status not ok -> the search ends with status ref-<status>.
#     Otherwise the limit of every later step is T = max(60, ceil(TIMEOUT_FACTOR * wall_s of step 0)).
#   take(mb): one step at -Xmx<mb>m with the limit T. Its status (e5-lib.sh, status of run_facts with the limit
#     T): ok = exit 0 and the answer of step 0; differs = exit 0 and another answer; oom = exit 3 with
#     OutOfMemoryError; timeout = exit 124, or 137 after at least T - 5 s (SIGKILL of timeout -k 30); killed =
#     exit 137 earlier (from outside, e.g. the OOM killer of the kernel); error otherwise. An error says nothing
#     about the heap (a crash, a failed start), so it never moves a bound: the step is repeated once at the same
#     -Xmx and the status of the repeat is the status of take(mb); a second error ends the search with status
#     error.
#   take(LO_MB): ok -> status le-lo (the minimum heap is at most LO_MB).
#   lo = LO_MB, hi = HI_MB; while hi - lo > GRAN_MB: mid = (lo + hi) // 2, take(mid): ok -> hi = mid, otherwise
#     (oom, timeout, killed, differs) lo = mid. So a run fails at lo and succeeds at hi.
#   confirmation: take(hi + 32) and take(lo - 32). A bisection never meets a step that contradicts another one,
#     so a single wrong step (noise, or a timeout of a run that would have finished: near the threshold the GC
#     runs almost all the time) would move the result silently; the two steps catch that.
#   success = status ok: take(hi + 32) is ok and take(lo - 32) is not ok; else status unconfirmed. In both cases
#     minheap_mb = hi, maxfail_mb = lo.
#   The search is what acceptance/E5/e5lib.py replay_minheap replays from the statuses of steps.tsv.
#
# Environment:
#   QILIN_JAR       fat jar of Qilin (default build/libs/Qilin-0.9.9-SNAPSHOT.jar of this repository)
#   JAVA_HOME       JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2); java is $JAVA_HOME/bin/java
#                   (it may be a launcher script that execs a java with the same arguments: E5_LAUNCHER of
#                   e5-lib.sh, which this script sets)
#   RUNS            the runs (default "insens ucfs-ANALYSIS ucfs-CALL_GRAPH"), as for e5-bench.sh
#   SKIP            <bench>:<run> pairs that are not searched (default as for e5-bench.sh: "antlr:ucfs-CALL_GRAPH
#                   bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH"; set and empty = nothing skipped)
#   TIMEOUT         seconds of the reference step (default 900)
#   HI_MB           -Xmx of the reference step, MB (default 16384)
#   LO_MB           the first -Xmx below it, MB (default 64); LO_MB < HI_MB and LO_MB > 32 (take(lo - 32))
#   GRAN_MB         the search stops when hi - lo <= GRAN_MB (default 16)
#   TIMEOUT_FACTOR  the factor of the step limit T (default 3)
#   E5_HOST_KIND    local (default) or vm, E5_FLAVOR (default "-"): for meta.tsv, as for e5-bench.sh
#   The numbers are positive integers. JAVA_TOOL_OPTIONS, _JAVA_OPTIONS, JDK_JAVA_OPTIONS must be empty: every
#   JVM of the steps would pick them up. Otherwise exit 2 before the first run.
#
# Files:
#   <out-dir>/<bench>/<run>/s<step>-x<mb>/  the step directory (the number in the name: a repeat and a
#                       confirmation can fall on an -Xmx that was taken before): cmd.txt other-java load1
#                       stat-before start out.txt time.txt end stat-after exit, as described in
#                       scripts/ucfs/e5-lib.sh (e5_run, timeout -k 30), sootOutput/ removed.
#                       <out-dir>/<bench>/<run>/ is emptied before its search.
#   <out-dir>/steps.tsv    bench run step xmx_mb status exit wall_s max_rss_mb other_java start_ns end_ns: one row
#                          per step of this call, in the order they ran (step from 0 in each search); status as
#                          above (step 0 with the limit TIMEOUT, no differs), the other columns as in runs.tsv of
#                          e5-bench.sh; a row is written right after its step
#   <out-dir>/minheap.tsv  bench run status minheap_mb maxfail_mb steps ref_wall_s ref_rss_mb step_timeout_s: one
#                          row per search; status ok, unconfirmed, error, le-lo or ref-<status of step 0>;
#                          minheap_mb = hi (le-lo: LO_MB), maxfail_mb = lo; steps = the steps of the search;
#                          ref_wall_s, ref_rss_mb = wall_s, max_rss_mb of step 0; step_timeout_s = T; "-" where
#                          a value does not apply (minheap/maxfail of error and ref-*, maxfail of le-lo, T of ref-*)
#   <out-dir>/meta.tsv     key value: command git-head tree-clean jar jar-sha256 benches runs skip timeout hi-mb
#                          lo-mb gran-mb timeout-factor jvm-flags java-tool-options java-options jdk-java-options
#                          host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version other-java
#                          load-start started finished, the values as in meta.tsv of e5-bench.sh (no
#                          compressed-oops: it depends on -Xmx, which changes from step to step); written before
#                          the first run with an empty finished and rewritten at the end
#   steps.tsv, minheap.tsv and meta.tsv describe this call only.
#
# Stdout: "e5-minheap: <bench> <run>" before each search, "e5-minheap: <bench> <run> s<step> x<mb> <status>"
# after each step, a warning or note of e5_run when the command line of the JVM was not the planned one or was
# not seen, and the last line "e5-minheap: <n> searches, <n> steps in <out-dir as realpath>".
# Requires bash, python3 (standard library only), GNU time at /usr/bin/time, timeout(1), pgrep, lscpu; no network.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E5_NAME=e5-minheap
# shellcheck source=scripts/ucfs/e5-lib.sh
source "$ROOT/scripts/ucfs/e5-lib.sh"
BENCH_PY="$ROOT/artifact/util/benchmark.py"
ALL_RUNS="insens ucfs-ANALYSIS ucfs-CALL_GRAPH"
DEFAULT_SKIP="antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH"
CONFIRM_MB=32
E5_KILL_AFTER=30
E5_LAUNCHER=yes

[ $# -ge 2 ] || e5_die "usage: bash scripts/ucfs/e5-minheap.sh <out-dir> <bench>..."
COMMAND="bash scripts/ucfs/e5-minheap.sh$(printf ' %q' "$@")"
OUT_ARG="$1"
shift
BENCHES=("$@")

QILIN_JAR="${QILIN_JAR:-$ROOT/build/libs/Qilin-0.9.9-SNAPSHOT.jar}"
JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
JAVA="$JAVA_HOME/bin/java"
read -r -a RUN_LIST <<< "${RUNS:-$ALL_RUNS}"
read -r -a SKIP_LIST <<< "${SKIP-$DEFAULT_SKIP}"
TIMEOUT="${TIMEOUT:-900}"
HI_MB="${HI_MB:-16384}"
LO_MB="${LO_MB:-64}"
GRAN_MB="${GRAN_MB:-16}"
TIMEOUT_FACTOR="${TIMEOUT_FACTOR:-3}"
JDK_BODIES=no
E5_HOST_KIND="${E5_HOST_KIND:-local}"
E5_FLAVOR="${E5_FLAVOR:--}"

e5_check_java_env
[ ${#RUN_LIST[@]} -gt 0 ] || e5_die "RUNS is empty"
for r in "${RUN_LIST[@]}"; do
    case " $ALL_RUNS " in
        *" $r "*) ;;
        *) e5_die "unknown run '$r' in RUNS (known: $ALL_RUNS)" ;;
    esac
done
[ -f "$BENCH_PY" ] || e5_die "$BENCH_PY not found (git submodule update --init --depth 1 artifact/benchmarks?)"
KNOWN_BENCHES="$(e5_known_benches)" || e5_die "cannot read $BENCH_PY"
for b in "${BENCHES[@]}"; do
    case " $KNOWN_BENCHES " in
        *" $b "*) ;;
        *) e5_die "unknown benchmark '$b' (known: $KNOWN_BENCHES)" ;;
    esac
done
for s in "${SKIP_LIST[@]}"; do
    case " $KNOWN_BENCHES " in
        *" ${s%%:*} "*) ;;
        *) e5_die "SKIP entry '$s' is not <bench>:<run> with a known benchmark" ;;
    esac
    case " $ALL_RUNS " in
        *" ${s#*:} "*) ;;
        *) e5_die "SKIP entry '$s' is not <bench>:<run> with a known run" ;;
    esac
done
for v in TIMEOUT HI_MB LO_MB GRAN_MB TIMEOUT_FACTOR; do
    [[ "${!v}" =~ ^[1-9][0-9]{0,8}$ ]] || e5_die "$v must be a positive integer, got '${!v}'"
done
[ "$LO_MB" -lt "$HI_MB" ] || e5_die "LO_MB ($LO_MB) must be below HI_MB ($HI_MB)"
[ "$LO_MB" -gt "$CONFIRM_MB" ] || e5_die "LO_MB ($LO_MB) must be above $CONFIRM_MB: the confirmation step is at maxfail - $CONFIRM_MB"
[[ "$E5_HOST_KIND" =~ ^(local|vm)$ ]] || e5_die "E5_HOST_KIND must be local or vm, got '$E5_HOST_KIND'"
[[ "$E5_FLAVOR" =~ ^[^[:space:]]+$ ]] || e5_die "E5_FLAVOR must be one word, got '$E5_FLAVOR'"
[ -x "$JAVA" ] || e5_die "no java at $JAVA (set JAVA_HOME to a JDK 21)"
[ -x /usr/bin/time ] || e5_die "GNU time /usr/bin/time is needed"
[ -f "$QILIN_JAR" ] || e5_die "QILIN_JAR $QILIN_JAR not found (build it: gradlew build -x test && gradlew fatJar -x test)"
JAR="$(realpath "$QILIN_JAR")"

mkdir -p "$OUT_ARG" || e5_die "cannot create $OUT_ARG"
OUTDIR="$(realpath "$OUT_ARG")"

# Taken before the first run: the code that the results come from, and the machine
GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
if [ -n "$GIT_HEAD" ] && [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    TREE_CLEAN=yes
else
    TREE_CLEAN=no
fi
JAR_SHA="$(sha256sum "$JAR" | cut -d' ' -f1)"
MACHINE="$(e5_host_meta)"
STARTED="$(date -Iseconds)"

# write_meta <finished>
write_meta() {
    printf 'key\tvalue\n'
    printf 'command\t%s\n' "$COMMAND"
    printf 'git-head\t%s\n' "$GIT_HEAD"
    printf 'tree-clean\t%s\n' "$TREE_CLEAN"
    printf 'jar\t%s\n' "$JAR"
    printf 'jar-sha256\t%s\n' "$JAR_SHA"
    printf 'benches\t%s\n' "${BENCHES[*]}"
    printf 'runs\t%s\n' "${RUN_LIST[*]}"
    printf 'skip\t%s\n' "${SKIP_LIST[*]}"
    printf 'timeout\t%s\n' "$TIMEOUT"
    printf 'hi-mb\t%s\n' "$HI_MB"
    printf 'lo-mb\t%s\n' "$LO_MB"
    printf 'gran-mb\t%s\n' "$GRAN_MB"
    printf 'timeout-factor\t%s\n' "$TIMEOUT_FACTOR"
    printf 'jvm-flags\t%s\n' "${JVM_FLAGS_E5[*]}"
    printf 'java-tool-options\t%s\n' "${JAVA_TOOL_OPTIONS:-}"
    printf 'java-options\t%s\n' "${_JAVA_OPTIONS:-}"
    printf 'jdk-java-options\t%s\n' "${JDK_JAVA_OPTIONS:-}"
    printf '%s\n' "$MACHINE"
    printf 'started\t%s\n' "$STARTED"
    printf 'finished\t%s\n' "$1"
}
write_meta "" > "$OUTDIR/meta.tsv"
printf 'bench\trun\tstep\txmx_mb\tstatus\texit\twall_s\tmax_rss_mb\tother_java\tstart_ns\tend_ns\n' > "$OUTDIR/steps.tsv"
printf 'bench\trun\tstatus\tminheap_mb\tmaxfail_mb\tsteps\tref_wall_s\tref_rss_mb\tstep_timeout_s\n' \
    > "$OUTDIR/minheap.tsv"

skipped() {
    case " ${SKIP_LIST[*]} " in
        *" $1:$2 "*) return 0 ;;
    esac
    return 1
}

# The facts of one step directory: argv = <dir> <timeout> <dir of step 0, or - for step 0> <TIMEOUT_FACTOR>;
# prints status exit wall_s max_rss_mb other_java start_ns end_ns and, last, T = max(60, ceil(factor * wall_s))
# of this step (used when it is step 0), one per line (a value may be empty)
STEP_PY='
import math, sys
d, timeout, ref, factor = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
MEASURE = re.compile(r"(-ms|-s|-mb)$")

def answer(p):
    return {k: v for k, v in parse_out(text(os.path.join(p, "out.txt"))) if not MEASURE.search(k)}

f = run_facts(d, timeout)
if f is None:
    sys.exit("no file exit in " + d)
st = f["status"]
if st == "ok" and ref != "-" and answer(d) != answer(ref):
    st = "differs"
t = max(60, math.ceil(factor * float(f["wall_s"]))) if f["wall_s"] else ""
print("\n".join([st] + [f[c] for c in ("exit", "wall_s", "max_rss_mb", "other_java", "start_ns", "end_ns")] + [str(t)]))
'

N_SEARCHES=0
N_STEPS=0
# Per search: BENCH RUN SDIR (its directory), K (number of the next step), REF ("-" or the directory of step 0),
# LIMIT (the limit of the next step); a step sets ST and ROW (its facts)
ST=""
ROW=()

# step <mb>: runs step K at -Xmx<mb>m with the limit LIMIT, appends its row to steps.tsv
step() {
    local mb="$1" d facts
    d="$SDIR/s$K-x$mb"
    XMX="${mb}m"
    e5_command "$RUN" "$BENCH"
    e5_run "$d" "$LIMIT"
    if facts="$(python3 -I -c "$E5_PY_RUN$STEP_PY" "$d" "$LIMIT" "$REF" "$TIMEOUT_FACTOR")"; then
        mapfile -t ROW <<< "$facts"
    else
        ROW=(error "" "" "" "" "" "" "")
    fi
    ST="${ROW[0]}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$BENCH" "$RUN" "$K" "$mb" "${ROW[@]:0:7}" \
        >> "$OUTDIR/steps.tsv"
    echo "e5-minheap: $BENCH $RUN s$K x$mb $ST"
    K=$((K + 1))
    N_STEPS=$((N_STEPS + 1))
}

# take <mb>: a step at -Xmx<mb>m, repeated once at the same -Xmx when its status is error; ST = the last status
take() {
    step "$1"
    [ "$ST" != error ] || step "$1"
}

# search: the search of BENCH RUN; sets RESULT = status minheap_mb maxfail_mb of its minheap.tsv row, REF_WALL,
# REF_RSS (wall_s, max_rss_mb of step 0) and STEP_TO (T, or - after a failed reference)
search() {
    local lo hi mid c1
    K=0
    REF="-"
    LIMIT="$TIMEOUT"
    step "$HI_MB"
    REF_WALL="${ROW[2]:--}"
    REF_RSS="${ROW[3]:--}"
    STEP_TO="-"
    if [ "$ST" != ok ]; then
        RESULT=("ref-$ST" - -)
        return
    fi
    REF="$SDIR/s0-x$HI_MB"
    STEP_TO="${ROW[7]}"
    LIMIT="$STEP_TO"
    take "$LO_MB"
    case "$ST" in
        error) RESULT=(error - -); return ;;
        ok) RESULT=(le-lo "$LO_MB" -); return ;;
    esac
    lo="$LO_MB"
    hi="$HI_MB"
    while [ $((hi - lo)) -gt "$GRAN_MB" ]; do
        mid=$(((lo + hi) / 2))
        take "$mid"
        case "$ST" in
            error) RESULT=(error - -); return ;;
            ok) hi="$mid" ;;
            *) lo="$mid" ;;
        esac
    done
    take $((hi + CONFIRM_MB))
    [ "$ST" != error ] || { RESULT=(error - -); return; }
    c1="$ST"
    take $((lo - CONFIRM_MB))
    [ "$ST" != error ] || { RESULT=(error - -); return; }
    if [ "$c1" = ok ] && [ "$ST" != ok ]; then
        RESULT=(ok "$hi" "$lo")
    else
        RESULT=(unconfirmed "$hi" "$lo")
    fi
}

for BENCH in "${BENCHES[@]}"; do
    for RUN in "${RUN_LIST[@]}"; do
        skipped "$BENCH" "$RUN" && continue
        echo "e5-minheap: $BENCH $RUN"
        SDIR="$OUTDIR/$BENCH/$RUN"
        rm -rf -- "$SDIR"
        mkdir -p "$SDIR"
        RESULT=()
        search
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$BENCH" "$RUN" "${RESULT[@]}" "$K" "$REF_WALL" "$REF_RSS" \
            "$STEP_TO" >> "$OUTDIR/minheap.tsv"
        N_SEARCHES=$((N_SEARCHES + 1))
    done
done

write_meta "$(date -Iseconds)" > "$OUTDIR/meta.tsv"
echo "e5-minheap: $N_SEARCHES searches, $N_STEPS steps in $OUTDIR"
