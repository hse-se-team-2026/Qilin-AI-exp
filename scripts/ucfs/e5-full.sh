#!/usr/bin/env bash
# E5 full measurement: all parts of the final E5 run (E5.md D4, D3, D8) one after another into one new
# directory - the repetitions (e5-bench.sh), the minimum heap (e5-minheap.sh) and the two probes (e5-bench.sh) -
# and right after each part the files of its run directories packed into <out-dir>/<part>/raw.tar.xz, so the
# results can be taken part by part while the run goes on (E5-S5a). Nothing of this script runs in parallel with
# a part, and the parts never run in parallel with each other.
# Contract: docs/ai/tickets/E5-S4.md (in the Diploma_work docs, not in this repository).
#
# Usage: bash scripts/ucfs/e5-full.sh <out-dir>
#   <out-dir> must not exist or be an empty directory: one run, one directory (a second run into the same
#   directory would mix the runs of two calls). Otherwise, and for wrong arguments or environment (below),
#   exit 2 before anything is written. Exit 0 when every part exited 0, else 1; the outcome of a part is its
#   row in full.tsv.
#
# Parts, in this order (only those of E5_PARTS); the variables of the parts not named here are unset, so each
# part has the defaults of its script (an exported RUNS, TIMEOUT, HI_MB, ... changes nothing):
#   bench      e5-bench.sh <out>/bench $E5_BENCHES with REPS=$E5_REPS WARMUP=1 TIMEOUT=900 XMX=16g (RUNS, SKIP,
#              JDK_BODIES: defaults - the three runs, CALL_GRAPH of antlr bloat checkstyle skipped, no JDK bodies)
#   minheap    e5-minheap.sh <out>/minheap $E5_MINHEAP_BENCHES with all its defaults
#   probe-cg   e5-bench.sh <out>/probe-cg $E5_PROBE_CG_BENCHES with RUNS=ucfs-CALL_GRAPH SKIP="" REPS=1 WARMUP=0
#              TIMEOUT=$E5_PROBE_TIMEOUT XMX=$E5_PROBE_XMX
#   probe-jdk  e5-bench.sh <out>/probe-jdk $E5_PROBE_JDK_BENCHES with JDK_BODIES=yes RUNS="insens ucfs-ANALYSIS"
#              SKIP="" REPS=1 WARMUP=0 TIMEOUT=$E5_PROBE_TIMEOUT XMX=$E5_PROBE_XMX
#   Every part gets QILIN_JAR (as realpath), JAVA_HOME, E5_HOST_KIND and E5_FLAVOR of this script.
#
# Environment:
#   QILIN_JAR             fat jar of Qilin (default build/libs/Qilin-0.9.9-SNAPSHOT.jar of this repository)
#   JAVA_HOME             JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2)
#   E5_PARTS              the parts to run, a subset of "bench minheap probe-cg probe-jdk" (default all four);
#                         they run in the order above whatever the order of the list
#   E5_REPS               measured repetitions of bench (default 10)
#   E5_BENCHES            benchmarks of bench (default the 12 in the order of the E4 results: antlr bloat chart
#                         eclipse fop luindex lusearch pmd xalan checkstyle findbugs JPC)
#   E5_MINHEAP_BENCHES    benchmarks of minheap (default the six covered: antlr bloat chart fop luindex lusearch)
#   E5_PROBE_CG_BENCHES   benchmarks of probe-cg (default antlr bloat checkstyle)
#   E5_PROBE_JDK_BENCHES  benchmarks of probe-jdk (default luindex)
#   E5_PROBE_TIMEOUT      TIMEOUT of the probes, seconds (default 3600)
#   E5_PROBE_XMX          XMX of the probes (default 52g)
#   E5_HOST_KIND          local (default) or vm, E5_FLAVOR (default "-"): passed to the parts for meta.tsv
#   JAVA_TOOL_OPTIONS, _JAVA_OPTIONS, JDK_JAVA_OPTIONS must be empty. A benchmark must be a name of
#   artifact/util/benchmark.py.
#
# Files:
#   <out>/host.txt        before the parts: the output of lscpu, head -n 3 /proc/meminfo, uname -a,
#                         cat /etc/os-release, <JAVA_HOME>/bin/java -version, nproc, the CPU frequency governor
#                         (cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c, only when
#                         there is one), systemd-detect-virt, df -h <out>, each after a line "== <command>";
#                         after all parts the section "== kernel-oom": the kernel lines with "out of memory",
#                         "oom-kill", "oom_reaper" or "killed process" (case ignored) logged since the start of
#                         the first part - from journalctl -k --since @<start> when it can read the kernel journal
#                         without sudo, else from dmesg --time-format iso filtered by that time -, or exactly
#                         "none" when there is none, or "unavailable" when neither can be read
#   <out>/full.tsv        part started finished exit: one row per part, written when the part and its raw.tar.xz
#                         are done (started, finished: date -Iseconds before the part and after its archive;
#                         exit: the exit code of the part, 1 when it was 0 and the archive failed)
#   <out>/<part>/         the files of the part: run directories, runs.tsv values.tsv meta.tsv (bench and probes)
#                         or minheap.tsv steps.tsv meta.tsv (minheap); its stdout and stderr in bench.log
#                         (bench, probe-cg, probe-jdk) or minheap.log (minheap)
#   <out>/<part>/raw.tar.xz  the files cmd.txt out.txt time.txt exit load1 other-java start end stat-before
#                         stat-after (e5lib.RUN_FILES) of every run directory of the part (a directory with a file
#                         exit), paths relative to <out> (<part>/<bench>/<run>/rep<k>/... or
#                         minheap/<bench>/<run>/s<i>-x<mb>/...); written as raw.tar.xz.tmp and renamed. The run
#                         directories stay where they are.
#
# Stdout (its own; the parts write into their logs): "e5-full: <part> started" before a part,
# "e5-full: <part> finished exit <n>" after its row of full.tsv, and the last line "e5-full: done in <out as
# realpath>". Requires what the parts require (bash, python3, GNU time, timeout, pgrep, lscpu), tar and xz.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E5_NAME=e5-full
# shellcheck source=scripts/ucfs/e5-lib.sh
source "$ROOT/scripts/ucfs/e5-lib.sh"
BENCH_PY="$ROOT/artifact/util/benchmark.py"
ALL_PARTS="bench minheap probe-cg probe-jdk"
RUN_FILES="cmd.txt out.txt time.txt exit load1 other-java start end stat-before stat-after"
OOM_RX='out of memory|oom-kill|oom_reaper|killed process'
# the variables of e5-bench.sh and e5-minheap.sh: unset for every part, then set as in the list of parts above
PART_VARS="RUNS REPS WARMUP SKIP TIMEOUT XMX JDK_BODIES HI_MB LO_MB GRAN_MB TIMEOUT_FACTOR"

[ $# -eq 1 ] || e5_die "usage: bash scripts/ucfs/e5-full.sh <out-dir>"
OUT_ARG="$1"
if [ -e "$OUT_ARG" ]; then
    [ -d "$OUT_ARG" ] && [ -z "$(ls -A -- "$OUT_ARG")" ] || e5_die "$OUT_ARG exists and is not an empty directory: give a new one"
fi

QILIN_JAR="${QILIN_JAR:-$ROOT/build/libs/Qilin-0.9.9-SNAPSHOT.jar}"
JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
JAVA="$JAVA_HOME/bin/java"
read -r -a PARTS_ARG <<< "${E5_PARTS:-$ALL_PARTS}"
REPS_B="${E5_REPS:-10}"
read -r -a BENCH_LIST <<< "${E5_BENCHES:-antlr bloat chart eclipse fop luindex lusearch pmd xalan checkstyle findbugs JPC}"
read -r -a MINHEAP_LIST <<< "${E5_MINHEAP_BENCHES:-antlr bloat chart fop luindex lusearch}"
read -r -a PROBE_CG_LIST <<< "${E5_PROBE_CG_BENCHES:-antlr bloat checkstyle}"
read -r -a PROBE_JDK_LIST <<< "${E5_PROBE_JDK_BENCHES:-luindex}"
PROBE_TIMEOUT="${E5_PROBE_TIMEOUT:-3600}"
PROBE_XMX="${E5_PROBE_XMX:-52g}"
HOST_KIND="${E5_HOST_KIND:-local}"
FLAVOR="${E5_FLAVOR:--}"

e5_check_java_env
[ ${#PARTS_ARG[@]} -gt 0 ] || e5_die "E5_PARTS is empty"
for p in "${PARTS_ARG[@]}"; do
    case " $ALL_PARTS " in
        *" $p "*) ;;
        *) e5_die "unknown part '$p' in E5_PARTS (known: $ALL_PARTS)" ;;
    esac
done
PARTS=()
for p in $ALL_PARTS; do
    case " ${PARTS_ARG[*]} " in
        *" $p "*) PARTS+=("$p") ;;
    esac
done
[[ "$REPS_B" =~ ^[1-9][0-9]*$ ]] || e5_die "E5_REPS must be an integer >= 1, got '$REPS_B'"
[[ "$PROBE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || e5_die "E5_PROBE_TIMEOUT must be a positive number of seconds, got '$PROBE_TIMEOUT'"
[[ "$PROBE_XMX" =~ ^[1-9][0-9]*[mMgG]$ ]] || e5_die "E5_PROBE_XMX must be a heap size such as 52g, got '$PROBE_XMX'"
[[ "$HOST_KIND" =~ ^(local|vm)$ ]] || e5_die "E5_HOST_KIND must be local or vm, got '$HOST_KIND'"
[[ "$FLAVOR" =~ ^[^[:space:]]+$ ]] || e5_die "E5_FLAVOR must be one word, got '$FLAVOR'"
[ -f "$BENCH_PY" ] || e5_die "$BENCH_PY not found (git submodule update --init --depth 1 artifact/benchmarks?)"
KNOWN_BENCHES="$(e5_known_benches)" || e5_die "cannot read $BENCH_PY"
for v in BENCH_LIST MINHEAP_LIST PROBE_CG_LIST PROBE_JDK_LIST; do
    declare -n list="$v"
    [ ${#list[@]} -gt 0 ] || e5_die "a list of benchmarks is empty ($v)"
    for b in "${list[@]}"; do
        case " $KNOWN_BENCHES " in
            *" $b "*) ;;
            *) e5_die "unknown benchmark '$b' (known: $KNOWN_BENCHES)" ;;
        esac
    done
    unset -n list
done
[ -x "$JAVA" ] || e5_die "no java at $JAVA (set JAVA_HOME to a JDK 21)"
[ -x /usr/bin/time ] || e5_die "GNU time /usr/bin/time is needed"
for c in tar xz; do
    command -v "$c" > /dev/null || e5_die "command $c not found"
done
[ -f "$QILIN_JAR" ] || e5_die "QILIN_JAR $QILIN_JAR not found"
JAR="$(realpath "$QILIN_JAR")"

mkdir -p "$OUT_ARG" || e5_die "cannot create $OUT_ARG"
OUTDIR="$(realpath "$OUT_ARG")"

# host.txt: the machine before the parts
{
    echo "== lscpu"
    LC_ALL=C lscpu
    echo "== head -n 3 /proc/meminfo"
    head -n 3 /proc/meminfo
    echo "== uname -a"
    uname -a
    echo "== cat /etc/os-release"
    cat /etc/os-release
    echo "== $JAVA -version"
    "$JAVA" -version 2>&1
    echo "== nproc"
    nproc
    if compgen -G '/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor' > /dev/null; then
        echo "== cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c"
        cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c
    fi
    echo "== systemd-detect-virt"
    if command -v systemd-detect-virt > /dev/null; then
        systemd-detect-virt
    else
        echo unavailable
    fi
    echo "== df -h $OUTDIR"
    df -h "$OUTDIR"
} > "$OUTDIR/host.txt" 2>&1
printf 'part\tstarted\tfinished\texit\n' > "$OUTDIR/full.tsv"

# part_env <command...>: the command with the variables of the parts unset and those of this script set
part_env() {
    local -a u=()
    local v
    for v in $PART_VARS; do
        u+=(-u "$v")
    done
    env "${u[@]}" QILIN_JAR="$JAR" JAVA_HOME="$JAVA_HOME" E5_HOST_KIND="$HOST_KIND" E5_FLAVOR="$FLAVOR" "$@"
}

# pack <part>: <out>/<part>/raw.tar.xz with the files RUN_FILES of the run directories of the part
pack() {
    local part="$1" tmp="$OUTDIR/$1/raw.tar.xz.tmp"
    (cd "$OUTDIR" && find "$part" -type f -name exit -printf '%h\n' | LC_ALL=C sort | while read -r d; do
        for f in $RUN_FILES; do
            [ -f "$d/$f" ] && printf '%s\0' "$d/$f"
        done
    done) | tar -C "$OUTDIR" --null --no-recursion -T - -cJf "$tmp" && mv -- "$tmp" "$OUTDIR/$part/raw.tar.xz"
}

# run_part <part>
run_part() {
    local part="$1" dir="$OUTDIR/$1" started finished rc
    echo "e5-full: $part started"
    started="$(date -Iseconds)"
    mkdir -p "$dir"
    case "$part" in
        bench)
            part_env REPS="$REPS_B" WARMUP=1 TIMEOUT=900 XMX=16g \
                bash "$ROOT/scripts/ucfs/e5-bench.sh" "$dir" "${BENCH_LIST[@]}" > "$dir/bench.log" 2>&1 ;;
        minheap)
            part_env bash "$ROOT/scripts/ucfs/e5-minheap.sh" "$dir" "${MINHEAP_LIST[@]}" > "$dir/minheap.log" 2>&1 ;;
        probe-cg)
            part_env RUNS=ucfs-CALL_GRAPH SKIP= REPS=1 WARMUP=0 TIMEOUT="$PROBE_TIMEOUT" XMX="$PROBE_XMX" \
                bash "$ROOT/scripts/ucfs/e5-bench.sh" "$dir" "${PROBE_CG_LIST[@]}" > "$dir/bench.log" 2>&1 ;;
        probe-jdk)
            part_env JDK_BODIES=yes RUNS="insens ucfs-ANALYSIS" SKIP= REPS=1 WARMUP=0 TIMEOUT="$PROBE_TIMEOUT" \
                XMX="$PROBE_XMX" bash "$ROOT/scripts/ucfs/e5-bench.sh" "$dir" "${PROBE_JDK_LIST[@]}" \
                > "$dir/bench.log" 2>&1 ;;
    esac
    rc=$?
    if ! pack "$part" 2>> "$dir/raw.err"; then
        [ "$rc" -ne 0 ] || rc=1
    fi
    [ -s "$dir/raw.err" ] || rm -f -- "$dir/raw.err"
    finished="$(date -Iseconds)"
    printf '%s\t%s\t%s\t%s\n' "$part" "$started" "$finished" "$rc" >> "$OUTDIR/full.tsv"
    echo "e5-full: $part finished exit $rc"
    [ "$rc" -eq 0 ] || FAILED=1
}

# kernel_oom <epoch seconds>: the body of the section kernel-oom
kernel_oom() {
    local since="$1" lines
    if journalctl -k -b --no-pager -q -n 1 2> /dev/null | grep -q .; then
        lines="$(journalctl -k --no-pager -q -o short-iso --since "@$since" 2> /dev/null | grep -iE "$OOM_RX")"
    elif dmesg > /dev/null 2>&1 && [ -n "$(dmesg 2> /dev/null | head -n 1)" ]; then
        lines="$(dmesg --time-format iso 2> /dev/null | python3 -I -c '
import datetime, re, sys
since, rx = float(sys.argv[1]), re.compile(sys.argv[2], re.I)
for line in sys.stdin:
    ts = line.split(" ", 1)[0].replace(",", ".")
    try:
        t = datetime.datetime.fromisoformat(ts).timestamp()
    except ValueError:
        continue
    if t >= since and rx.search(line):
        sys.stdout.write(line)
' "$since" "$OOM_RX")"
    else
        echo unavailable
        return
    fi
    if [ -n "$lines" ]; then
        printf '%s\n' "$lines"
    else
        echo none
    fi
}

FAILED=0
SINCE="$(date +%s)"
for p in "${PARTS[@]}"; do
    run_part "$p"
done
{
    echo "== kernel-oom"
    kernel_oom "$SINCE"
} >> "$OUTDIR/host.txt"
echo "e5-full: done in $OUTDIR"
exit "$FAILED"
