#!/usr/bin/env bash
# E5 benchmark runner: repeated measurements of Spark and -pta=ucfs on the benchmarks of artifact/benchmarks.
# Every run is its own JVM; the runs go one after another, repetition by repetition: inside a repetition the
# benchmarks in the given order, inside a benchmark the runs of RUNS rotated left by the repetition number
# (repetition k starts with RUNS[k mod |RUNS|]), so drift of the machine and the position inside a repetition
# fall on every configuration alike. Repetition 0 (WARMUP=1) warms the file cache of the OS; it is written like
# the others and left out of the statistics by the readers of the results. The runs are the plain analysis:
# no -ucfscompare / -ucfspt (reference fixed points and dumps are a check, not a cost of the analysis).
# Contract: docs/ai/tickets/E5-S2.md (in the Diploma_work docs, not in this repository).
#
# Usage: bash scripts/ucfs/e5-bench.sh <out-dir> <bench>...
#   <bench> is a name of artifact/util/benchmark.py: antlr bloat chart eclipse fop luindex lusearch pmd xalan
#   checkstyle JPC findbugs. Wrong arguments or environment (below) exit 2 before the first run.
#   Exit 0 when every run was started and the TSV files are written; the outcome of a run is its status in
#   runs.tsv, not the exit code of this script.
#
# Environment:
#   QILIN_JAR     fat jar of Qilin (default build/libs/Qilin-0.9.9-SNAPSHOT.jar of this repository)
#   JAVA_HOME     JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2); java is $JAVA_HOME/bin/java
#   RUNS          the runs (default "insens ucfs-ANALYSIS ucfs-CALL_GRAPH"):
#                   insens      -pta=insens
#                   ucfs-<B>    -pta=ucfs -ucfsbinding=<B>   (B = ANALYSIS or CALL_GRAPH)
#   REPS          measured repetitions, an integer >= 1 (default 10)
#   WARMUP        1: repetition 0 before them (default), 0: none
#   SKIP          <bench>:<run> pairs that are not run (default "antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH
#                 checkstyle:ucfs-CALL_GRAPH"; set and empty = nothing skipped)
#   TIMEOUT       seconds per run (default 900); a run over it gets SIGTERM from timeout(1), exit 124 (SIGKILL
#                 60 s later if it is still alive, then exit 137)
#   XMX           maximum heap of each run, -Xmx, such as 16g or 512m (default 16g)
#   JDK_BODIES    no: the JDK packages without bodies, -exclude=<E4.md D3 list> (default); yes: no -exclude
#   E5_HOST_KIND  local (default) or vm: where it runs, for meta.tsv
#   E5_FLAVOR     the kind of the machine, for meta.tsv (default "-")
#   JAVA_TOOL_OPTIONS, _JAVA_OPTIONS, JDK_JAVA_OPTIONS must be empty (exit 2 otherwise): every JVM of the runs
#                 would pick them up.
#   The command line of a run is that of scripts/ucfs/e5-lib.sh (e5_command): java -Xmx<XMX>
#   -XX:+ExitOnOutOfMemoryError -jar <jar> <options of artifact/run.py> <run options> <benchmark arguments>
#   -ucfsseam [-exclude=...], and nothing else.
#
# Files:
#   <out-dir>/<bench>/<run>/rep<k>/  the run directory (emptied before its run, the working directory of the run,
#                                    sootOutput/ removed after it): cmd.txt other-java load1 stat-before start
#                                    out.txt time.txt end stat-after exit, as described in scripts/ucfs/e5-lib.sh
#   <out-dir>/runs.tsv    bench run rep status exit wall_s user_s sys_s max_rss_mb load1 other_java procs_running
#                         steal_pct start_ns end_ns; status ok (exit 0), timeout (exit 124, or 137 after at least
#                         TIMEOUT - 5 s), killed (exit 137 earlier: killed from outside, e.g. by the OOM killer),
#                         oom (exit 3 with OutOfMemoryError in out.txt), error otherwise; wall_s, user_s, sys_s =
#                         "Elapsed (wall clock)", "User time", "System time" of time.txt with two decimals;
#                         max_rss_mb = "Maximum resident set size" / 1024, rounded down; load1, other_java,
#                         start_ns, end_ns = the files; procs_running of stat-before; steal_pct = 100 * steal
#                         ticks / all ticks (the 8 first numbers of the line "cpu ") from stat-before to
#                         stat-after, two decimals
#   <out-dir>/values.tsv  bench run rep key value; one row per line "#<key>: <value>" (one-word value) of out.txt,
#                         and the lines of Qilin "Time (sec): <x>" -> qilin-pta-s, "Main PTA (including
#                         pre-analysis) elapsed time: <x>s" -> qilin-main-pta-s, "Main PTA consumed memory: <x> MB"
#                         -> qilin-main-pta-rss-mb
#   <out-dir>/meta.tsv    key value: command (bash scripts/ucfs/e5-bench.sh and the arguments as given), git-head,
#                         tree-clean (yes when `git status --porcelain --untracked-files=no` is empty), jar,
#                         jar-sha256, benches, runs, reps, warmup, skip, timeout, xmx, jvm-flags, jdk-bodies,
#                         java-tool-options, java-options, jdk-java-options (the three variables, empty),
#                         compressed-oops (UseCompressedOops of `java -Xmx<XMX> -XX:+PrintFlagsFinal -version`),
#                         host-kind, flavor, cpu-model (lscpu "Model name"), cpu-count (nproc), mem-total-mb
#                         (MemTotal / 1024), kernel (uname -r), os (PRETTY_NAME), java-version (second line of
#                         java -version), other-java (pgrep -c -x java), load-start (/proc/loadavg), started,
#                         finished (date -Iseconds). Everything up to load-start and started is taken before the
#                         first run; meta.tsv is written then with an empty finished and rewritten at the end.
#   runs.tsv and values.tsv are collected from all run directories in <out-dir>, also from earlier calls, the
#   status with the TIMEOUT of this call; meta.tsv describes this call only.
#
# Stdout: "e5-bench: <bench> <run> rep<k>" before each run, a warning or note from e5_run when the command line of
# the java process was not the planned one or was not seen, and the last line
# "e5-bench: <n> runs, <n> values in <out-dir as realpath>".
# Requires bash, python3 (standard library only), GNU time at /usr/bin/time, timeout(1), pgrep, lscpu; no network.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E5_NAME=e5-bench
# shellcheck source=scripts/ucfs/e5-lib.sh
source "$ROOT/scripts/ucfs/e5-lib.sh"
BENCH_PY="$ROOT/artifact/util/benchmark.py"
ALL_RUNS="insens ucfs-ANALYSIS ucfs-CALL_GRAPH"
DEFAULT_SKIP="antlr:ucfs-CALL_GRAPH bloat:ucfs-CALL_GRAPH checkstyle:ucfs-CALL_GRAPH"

[ $# -ge 2 ] || e5_die "usage: bash scripts/ucfs/e5-bench.sh <out-dir> <bench>..."
COMMAND="bash scripts/ucfs/e5-bench.sh$(printf ' %q' "$@")"
OUT_ARG="$1"
shift
BENCHES=("$@")

QILIN_JAR="${QILIN_JAR:-$ROOT/build/libs/Qilin-0.9.9-SNAPSHOT.jar}"
JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
JAVA="$JAVA_HOME/bin/java"
read -r -a RUN_LIST <<< "${RUNS:-$ALL_RUNS}"
REPS="${REPS:-10}"
WARMUP="${WARMUP:-1}"
read -r -a SKIP_LIST <<< "${SKIP-$DEFAULT_SKIP}"
TIMEOUT="${TIMEOUT:-900}"
XMX="${XMX:-16g}"
JDK_BODIES="${JDK_BODIES:-no}"
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
[[ "$REPS" =~ ^[1-9][0-9]*$ ]] || e5_die "REPS must be an integer >= 1, got '$REPS'"
[[ "$WARMUP" =~ ^[01]$ ]] || e5_die "WARMUP must be 0 or 1, got '$WARMUP'"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || e5_die "TIMEOUT must be a positive number of seconds, got '$TIMEOUT'"
[[ "$XMX" =~ ^[1-9][0-9]*[mMgG]$ ]] || e5_die "XMX must be a heap size such as 16g or 512m, got '$XMX'"
[[ "$JDK_BODIES" =~ ^(no|yes)$ ]] || e5_die "JDK_BODIES must be no or yes, got '$JDK_BODIES'"
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
MACHINE="$(e5_machine_meta)"
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
    printf 'reps\t%s\n' "$REPS"
    printf 'warmup\t%s\n' "$WARMUP"
    printf 'skip\t%s\n' "${SKIP_LIST[*]}"
    printf 'timeout\t%s\n' "$TIMEOUT"
    printf 'xmx\t%s\n' "$XMX"
    printf 'jvm-flags\t%s\n' "${JVM_FLAGS_E5[*]}"
    printf 'jdk-bodies\t%s\n' "$JDK_BODIES"
    printf 'java-tool-options\t%s\n' "${JAVA_TOOL_OPTIONS:-}"
    printf 'java-options\t%s\n' "${_JAVA_OPTIONS:-}"
    printf 'jdk-java-options\t%s\n' "${JDK_JAVA_OPTIONS:-}"
    printf '%s\n' "$MACHINE"
    printf 'started\t%s\n' "$STARTED"
    printf 'finished\t%s\n' "$1"
}
write_meta "" > "$OUTDIR/meta.tsv"

skipped() {
    case " ${SKIP_LIST[*]} " in
        *" $1:$2 "*) return 0 ;;
    esac
    return 1
}

n=${#RUN_LIST[@]}
for ((k = (WARMUP == 1 ? 0 : 1); k <= REPS; k++)); do
    rot=("${RUN_LIST[@]:k % n}" "${RUN_LIST[@]:0:k % n}")
    for b in "${BENCHES[@]}"; do
        for r in "${rot[@]}"; do
            skipped "$b" "$r" && continue
            echo "e5-bench: $b $r rep$k"
            e5_command "$r" "$b"
            e5_run "$OUTDIR/$b/$r/rep$k" "$TIMEOUT"
        done
    done
done

# Collect runs.tsv and values.tsv from all run directories of <out-dir>; prints the two row counts
COLLECT='
import sys
out, timeout, benches, runs = sys.argv[1], int(sys.argv[2]), sys.argv[3].split(), sys.argv[4].split()
COLS = ["status", "exit", "wall_s", "user_s", "sys_s", "max_rss_mb", "load1", "other_java", "procs_running",
        "steal_pct", "start_ns", "end_ns"]
R, V = [], []
for b in benches:
    for r in runs:
        d = os.path.join(out, b, r)
        reps = sorted((int(x[3:]), x) for x in os.listdir(d) if re.fullmatch(r"rep\d+", x)) if os.path.isdir(d) else []
        for k, name in reps:
            f = run_facts(os.path.join(d, name), timeout)
            if f is None:
                continue
            R.append([b, r, str(k)] + [f[c] for c in COLS])
            V += [[b, r, str(k), key, val] for key, val in parse_out(text(os.path.join(d, name, "out.txt")))]

def write(name, header, rows):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        fh.write("\t".join(header) + "\n")
        for row in rows:
            fh.write("\t".join(row) + "\n")

write("runs.tsv", ["bench", "run", "rep"] + COLS, R)
write("values.tsv", ["bench", "run", "rep", "key", "value"], V)
print(len(R), len(V))
'
counts="$(python3 -I -c "$E5_PY_RUN$COLLECT" "$OUTDIR" "$TIMEOUT" "$KNOWN_BENCHES" "$ALL_RUNS")" \
    || { echo "e5-bench: collecting the TSV files failed" >&2; exit 1; }
read -r n_runs n_values <<< "$counts"

write_meta "$(date -Iseconds)" > "$OUTDIR/meta.tsv"
echo "e5-bench: $n_runs runs, $n_values values in $OUTDIR"
