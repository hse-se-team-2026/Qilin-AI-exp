#!/usr/bin/env bash
# E6 probe: runs of Qilin -cflidr (Spark insens, then the IDR export and cfl-idr-with-gll in the JVM of Qilin) on
# the benchmarks of artifact/benchmarks in the configuration D3 of E4 (JDK bodies excluded, options of
# artifact/run.py), one run after another under the machine lock, with the raw files of every run packed and the
# tables derived from them (docs/ai/tickets/E6-S6a.md, E6.md D10, D13, D14).
#
# Usage: bash scripts/cflidr/e6-probe.sh <out-dir> [<bench>:<mode>:<grammar>[:<timeout_s>] ...]
#   Without run specs: the matrix of E6.md D10, in this order:
#     xalan:ERASED:parity xalan:BALANCED:parity xalan:BALANCED:se xalan:CS:parity:3600 pmd:ERASED:parity
#     pmd:BALANCED:parity pmd:CS:parity luindex:BALANCED:parity antlr:BALANCED:parity
#   <bench> is a name of artifact/util/benchmark.py, <mode> ERASED|BALANCED|CS (-cflidrmode), <grammar> a grammar
#   of -cflidr (parity, se, ...; Qilin checks it). A spec without <timeout_s> gets TIMEOUT. A malformed spec, an
#   unknown benchmark or mode exits 2 before the lock and before <out-dir> is created.
#   Exit 0 when every run was started and the files below are written; the outcome of a run is its status in
#   runs.tsv, not the exit code of this script. Exit 2: usage or environment.
#
# Environment:
#   JAR              fat jar of Qilin (default build/libs/Qilin-0.9.9-SNAPSHOT.jar of this repository)
#   JAVA_HOME        JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2); java is $JAVA_HOME/bin/java
#   TIMEOUT          seconds of a run whose spec has no timeout of its own (default 600); a run over it gets
#                    SIGTERM from timeout(1), exit 124 (SIGKILL 30 s later if it is still alive, exit 137)
#   XMX              maximum heap of each run, -Xmx (default 16g)
#   STACK            stack of the cfl-idr thread, -cflidrstack=$STACK; empty (default): no -cflidrstack, Qilin's
#                    default (1g)
#   EXTRA_OPTS       more Qilin options, split into words, after all others (e.g. -pts)
#   HEAVY_LOCK       the machine lock (default /home/usatovpavel/edu/.heavy-run.lock)
#   HEAVY_LOCK_HELD  1: the caller holds HEAVY_LOCK, the script does not take it (a nested flock on the same file
#                    would wait forever); otherwise the script re-runs itself under
#                    `flock "$HEAVY_LOCK" env HEAVY_LOCK_HELD=1` and waits for the lock (RAM rule: one run with a
#                    heap above 4 GB on the machine at a time)
#   DRY_RUN          1: print the runs as <bench>:<mode>:<grammar>:<timeout_s>, one per line, and exit 0 (before
#                    the lock; nothing is created)
#
# A run: <out-dir>/<bench>/<mode>-<grammar>/ (removed before the run) is its working directory (sootOutput/ with
# the dump sootOutput/cflidr is there). The command is
#   timeout -k 30 <timeout_s> $JAVA -Xmx$XMX -jar $JAR -pae -pe -clinit=ONFLY -lcs -mh -pta=insens <benchmark
#   arguments of artifact/util/benchmark.py> -exclude=<JDK packages> -cflidr=<grammar> -cflidrmode=<mode>
#   [-cflidrstack=$STACK] [$EXTRA_OPTS]
# under /usr/bin/time -v, stdin /dev/null. Files of the run (the raw files):
#   cmd.txt       the command above, `printf '%q '` of its words, and a line break
#   timeout       <timeout_s>
#   out.txt       stdout and stderr of the run (plus one line "e6-probe NOTE: ..." of this script when the run
#                 printed #CFLIDR-pt-over, i.e. reached the dump, and its export counter order-ties is not 0 or is
#                 missing, see counters.tsv)
#   time.txt      the report of /usr/bin/time -v
#   exit          the exit code of the run
#   counters.tsv  a copy of sootOutput/cflidr/counters.tsv (the export counters, key<TAB>value, order-ties among
#                 them; E6-S4b), if the run reached the dump; a run that stopped before has none
#
# Files of <out-dir> (rows in the order of the specs; the tables are those acceptance/E6/e6raw.py derives from
# the raw files):
#   runs.tsv      bench mode grammar timeout_s status exit wall_s max_rss_mb last_phase
#   values.tsv    bench mode grammar key value: one row per line "#CFLIDR-<k>: <v>" of out.txt except
#                 #CFLIDR-error*; key CFLIDR-<k>, value <v> up to the first tab
#   evidence.tsv  bench mode grammar exit status error_line wall_s out_sha256 cmd_sha256
#     status      ok (exit 0 and a line "#CFLIDR-pt-over:"), else sof (java.lang.StackOverflowError in out.txt),
#                 else oom (java.lang.OutOfMemoryError), else timeout (exit 124 or 137), else error
#     wall_s      "Elapsed (wall clock)" of time.txt in seconds, as awk prints it with %.6g; max_rss_mb: "Maximum
#                 resident set size" (KB) / 1024 rounded down; "0" if time.txt has no such line
#     last_phase  <p> of the last line "#CFLIDR-<p>-ms:" ("-" if none); the time of a phase is printed when it ends
#     error_line  the first line starting with "#CFLIDR-error:" (the report of CflIdrRun), else the first line with
#                 java.lang.StackOverflowError or java.lang.OutOfMemoryError (another thread, e.g. the timer of
#                 qilin.util.MemoryWatcher, may print it first), tabs as blanks, its first 200 bytes without a
#                 broken UTF-8 character at the end ("-" if none)
#   counters.tsv  bench mode grammar key value: the rows of the counters.tsv of each run that has one
#   notes.tsv     bench mode grammar note: one row per run with such a NOTE line (the same text); only the
#                 header if there is none
#   raw.tar.xz    the raw files of the runs at <bench>/<mode>-<grammar>/<file> (tar --sort=name --owner=0
#                 --group=0 --mtime=@0)
#   meta.tsv      key value: command, git-head, tree-clean (yes when `git status --porcelain --untracked-files=no`
#                 is empty), jar, jar-sha256, cflidr-commit (scripts/cflidr/cflidr.properties), ucfs-commit
#                 (gradle.properties), java-version, specs, timeout-s, xmx, stack ("default" if STACK is empty),
#                 extra-opts ("-" if empty), heavy-lock (the lock file), heavy-lock-busy-start (yes: the lock was
#                 held when the runs started, as it must be), cpu-model, cpus, mem-total-mb, load1-start,
#                 mem-available-mb-start, started, then after all runs load1-end, finished
#   runs.tsv, values.tsv, evidence.tsv, counters.tsv, notes.tsv describe this call only; rows are appended after
#   each run, raw.tar.xz and the last keys of meta.tsv are written after the last run.
#
# Stdout: "e6-probe: run <spec>" before each run, "e6-probe: <spec> <status> exit <n> wall_s <s> max_rss_mb <n>
# last_phase <p>" after it, and the last line "e6-probe: <n> runs in <out-dir>".
# Requires bash, flock(1), timeout(1), GNU time at /usr/bin/time, awk, sha256sum, tar with xz, python3 (to read
# artifact/util/benchmark.py), pkill; no network. Does not change scripts/ucfs/.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_PY="$ROOT/artifact/util/benchmark.py"
MATRIX=(xalan:ERASED:parity xalan:BALANCED:parity xalan:BALANCED:se xalan:CS:parity:3600 pmd:ERASED:parity
    pmd:BALANCED:parity pmd:CS:parity luindex:BALANCED:parity antlr:BALANCED:parity)
MODES="ERASED BALANCED CS"
# JDK packages without bodies (E4.md D3); the same list as JDK_EXCLUDE of scripts/ucfs/e4-bench.sh
JDK_EXCLUDE='java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*'
# Options of artifact/run.py in the zipper style (ZIPPEROPTIONS), as scripts/ucfs/e4-bench.sh
RUNPY_OPTS=(-pae -pe -clinit=ONFLY -lcs -mh)

die() { echo "e6-probe: $*" >&2; exit 2; }

ARGS=("$@")
[ $# -ge 1 ] || die "usage: bash scripts/cflidr/e6-probe.sh <out-dir> [<bench>:<mode>:<grammar>[:<timeout_s>] ...]"
OUT_ARG="$1"
shift
[ -n "$OUT_ARG" ] || die "empty <out-dir>"
TIMEOUT="${TIMEOUT:-600}"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "TIMEOUT must be a positive number of seconds, got '$TIMEOUT'"

# SPECS: <bench>:<mode>:<grammar>:<timeout_s> of each run
SPECS=()
[ $# -gt 0 ] || set -- "${MATRIX[@]}"
for s in "$@"; do
    [[ "$s" =~ ^([A-Za-z0-9_.-]+):([A-Za-z0-9_-]+):([A-Za-z0-9_-]+)(:([1-9][0-9]*))?$ ]] \
        || die "bad run spec '$s' (expected <bench>:<mode>:<grammar>[:<timeout_s>])"
    SPECS+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[5]:-$TIMEOUT}")
done

if [ "${DRY_RUN:-}" = 1 ]; then
    printf '%s\n' "${SPECS[@]}"
    exit 0
fi

JAR_ARG="${JAR:-$ROOT/build/libs/Qilin-0.9.9-SNAPSHOT.jar}"
JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
JAVA="$JAVA_HOME/bin/java"
XMX="${XMX:-16g}"
STACK="${STACK:-}"
read -r -a EXTRA <<< "${EXTRA_OPTS:-}"
HEAVY_LOCK="${HEAVY_LOCK:-/home/usatovpavel/edu/.heavy-run.lock}"

[[ "$XMX" =~ ^[1-9][0-9]*[kKmMgG]?$ ]] || die "XMX must be a heap size such as 16g, got '$XMX'"
[ -z "$STACK" ] || [[ "$STACK" =~ ^[1-9][0-9]*[kKmMgG]?$ ]] || die "STACK must be a size such as 64k or 1g, got '$STACK'"
[ -f "$BENCH_PY" ] || die "$BENCH_PY not found (git submodule update --init --depth 1 artifact/benchmarks?)"
KNOWN_BENCHES="$(python3 -I - "$BENCH_PY" <<'PY'
import runpy, sys
print(" ".join(runpy.run_path(sys.argv[1])["BENCHMARKS"]))
PY
)" || die "cannot read $BENCH_PY"
for s in "${SPECS[@]}"; do
    IFS=: read -r b m _ _ <<< "$s"
    case " $KNOWN_BENCHES " in *" $b "*) ;; *) die "unknown benchmark '$b' in '$s' (known: $KNOWN_BENCHES)" ;; esac
    case " $MODES " in *" $m "*) ;; *) die "unknown mode '$m' in '$s' (known: $MODES)" ;; esac
done
[ -x "$JAVA" ] || die "no java at $JAVA (set JAVA_HOME to a JDK 21)"
[ -x /usr/bin/time ] || die "GNU time /usr/bin/time is needed"
command -v flock > /dev/null || die "flock(1) is needed"
[ -f "$JAR_ARG" ] || die "JAR $JAR_ARG not found (build it: gradlew build -x test && gradlew fatJar -x test)"

# The machine lock (RAM rule, E6.md D13): wait for it here, before <out-dir> is created
if [ "${HEAVY_LOCK_HELD:-}" != 1 ]; then
    echo "e6-probe: waiting for the heavy-run lock $HEAVY_LOCK"
    exec flock "$HEAVY_LOCK" env HEAVY_LOCK_HELD=1 bash "$0" "${ARGS[@]}"
fi
# the lock is held by the caller (or by the flock above): a non-blocking flock on it must fail
if flock -n "$HEAVY_LOCK" true; then
    LOCK_BUSY=no
    echo "e6-probe: warning: HEAVY_LOCK_HELD=1, but nobody holds $HEAVY_LOCK" >&2
else
    LOCK_BUSY=yes
fi

JAR="$(realpath "$JAR_ARG")"
mkdir -p "$OUT_ARG" || die "cannot create $OUT_ARG"
OUTDIR="$(realpath "$OUT_ARG")"

# bench_args <bench> -> one argument per line: -apppath, -libpath, -mainclass, -reflectionlog, -jre of
# artifact/util/benchmark.py (its paths are relative to artifact/); as bench_args of scripts/ucfs/e4-bench.sh
bench_args() {
    python3 -I - "$BENCH_PY" "$ROOT/artifact" "$1" <<'PY'
import os, runpy, sys
bm, base, b = sys.argv[1], sys.argv[2], sys.argv[3]
m = runpy.run_path(bm)
print("-apppath"); print(os.path.join(base, m["APPPATH"][b]))
if b in m["LIBPATH"]:
    print("-libpath"); print(os.path.join(base, m["LIBPATH"][b]))
print("-mainclass"); print(m["MAINCLASSES"][b])
print("-reflectionlog"); print(os.path.join(base, m["TAMIFLEXLOG"][b]))
print("-jre=" + os.path.join(base, "benchmarks", "JREs", m["JREVERSION"][b]))
PY
}

meminfo_mb() { awk -v k="$1:" '$1 == k {print int($2 / 1024); exit}' /proc/meminfo; }
load1() { cut -d' ' -f1 /proc/loadavg; }

# Taken at the start: the code and the machine the results come from
GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
if [ -n "$GIT_HEAD" ] && [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    TREE_CLEAN=yes
else
    TREE_CLEAN=no
fi
META=(
    "command" "bash scripts/cflidr/e6-probe.sh$(printf ' %q' "${ARGS[@]}")"
    "git-head" "$GIT_HEAD"
    "tree-clean" "$TREE_CLEAN"
    "jar" "$JAR"
    "jar-sha256" "$(sha256sum "$JAR" | cut -d' ' -f1)"
    "cflidr-commit" "$(sed -n 's/^cflidrCommit=//p' "$ROOT/scripts/cflidr/cflidr.properties" | tail -n 1 | tr -d '\r')"
    "ucfs-commit" "$(sed -n 's/^ucfsCommit=//p' "$ROOT/gradle.properties" | tail -n 1 | tr -d '\r')"
    "java-version" "$("$JAVA" -version 2>&1 | head -n 1)"
    "specs" "${SPECS[*]}"
    "timeout-s" "$TIMEOUT"
    "xmx" "$XMX"
    "stack" "${STACK:-default}"
    "extra-opts" "${EXTRA_OPTS:--}"
    "heavy-lock" "$HEAVY_LOCK"
    "heavy-lock-busy-start" "$LOCK_BUSY"
    "cpu-model" "$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)"
    "cpus" "$(nproc)"
    "mem-total-mb" "$(meminfo_mb MemTotal)"
    "load1-start" "$(load1)"
    "mem-available-mb-start" "$(meminfo_mb MemAvailable)"
    "started" "$(date -Iseconds)"
)
# write_meta [<key> <value> ...]: meta.tsv with META and the given pairs
write_meta() {
    local i
    local -a kv=("${META[@]}" "$@")
    {
        printf 'key\tvalue\n'
        for ((i = 0; i < ${#kv[@]}; i += 2)); do
            printf '%s\t%s\n' "${kv[i]}" "${kv[i + 1]}"
        done
    } > "$OUTDIR/meta.tsv"
}
write_meta

printf 'bench\tmode\tgrammar\ttimeout_s\tstatus\texit\twall_s\tmax_rss_mb\tlast_phase\n' > "$OUTDIR/runs.tsv"
printf 'bench\tmode\tgrammar\tkey\tvalue\n' > "$OUTDIR/values.tsv"
printf 'bench\tmode\tgrammar\texit\tstatus\terror_line\twall_s\tout_sha256\tcmd_sha256\n' > "$OUTDIR/evidence.tsv"
printf 'bench\tmode\tgrammar\tkey\tvalue\n' > "$OUTDIR/counters.tsv"
printf 'bench\tmode\tgrammar\tnote\n' > "$OUTDIR/notes.tsv"

# A signal stops the current run too (its timeout(1) is in a process group of its own)
RUN_PID=""
on_signal() {
    [ -z "$RUN_PID" ] || pkill -TERM -P "$RUN_PID"
    echo "e6-probe: stopped by a signal" >&2
    exit 143
}
trap on_signal TERM INT HUP

# wall_rss <time.txt> -> "<wall_s>\t<max_rss_mb>"
wall_rss() {
    LC_ALL=C awk '
        function value(l, i) {   # the text after the first ": " up to the next ": "
            i = index(l, ": "); l = substr(l, i + 2)
            i = index(l, ": "); if (i) l = substr(l, 1, i - 1)
            return l
        }
        index($0, "Elapsed (wall clock)") {
            n = split(value($0), p, ":"); s = 0
            for (k = 1; k <= n; k++) s = s * 60 + p[k]
            wall = sprintf("%.6g", s)
        }
        index($0, "Maximum resident set size") { rss = sprintf("%d", int(value($0) / 1024)) }
        END { printf "%s\t%s\n", (wall == "" ? "0" : wall), (rss == "" ? "0" : rss) }' "$1"
}

# scan_out <out.txt> <rc> <prefix> <values file> -> "<status>\t<last_phase>\t<error_line>"; appends the rows of
# values.tsv (each "<prefix>\t<key>\t<value>") to <values file>
scan_out() {
    LC_ALL=C awk -v rc="$2" -v pre="$3" -v vals="$4" '
        BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
        # the first 200 bytes of s without an incomplete UTF-8 sequence at the end
        function cut200(s, n, i, b, need) {
            if (length(s) <= 200) return s
            s = substr(s, 1, 200); n = 200
            for (i = n; i > 0 && i > n - 4; i--) {
                b = ord[substr(s, i, 1)]
                if (b < 128) break
                if (b >= 192) {
                    need = b >= 240 ? 4 : (b >= 224 ? 3 : 2)
                    if (n - i + 1 < need) s = substr(s, 1, i - 1)
                    break
                }
            }
            return s
        }
        substr($0, 1, 16) == "#CFLIDR-pt-over:" { over = 1 }
        index($0, "java.lang.StackOverflowError") { sof = 1 }
        index($0, "java.lang.OutOfMemoryError") { oom = 1 }
        /^#CFLIDR-[a-z]+-ms:/ { p = substr($0, 9); last = substr(p, 1, index(p, "-ms:") - 1) }
        !e1 && substr($0, 1, 14) == "#CFLIDR-error:" { e1 = 1; err1 = $0 }
        !e2 && /java\.lang\.(StackOverflowError|OutOfMemoryError)/ { e2 = 1; err2 = $0 }
        substr($0, 1, 8) == "#CFLIDR-" && substr($0, 1, 13) != "#CFLIDR-error" && (c = index($0, ":")) {
            v = substr($0, c + 1); sub(/^ +/, "", v)
            if ((t = index(v, "\t"))) v = substr(v, 1, t - 1)
            print pre "\t" substr($0, 2, c - 2) "\t" v >> vals
        }
        END {
            if (rc == 0 && over) st = "ok"
            else if (sof) st = "sof"
            else if (oom) st = "oom"
            else if (rc == 124 || rc == 137) st = "timeout"
            else st = "error"
            err = e1 ? err1 : (e2 ? err2 : "")
            if (err == "") err = "-"
            else { gsub(/\t/, " ", err); err = cut200(err) }
            printf "%s\t%s\t%s\n", st, (last == "" ? "-" : last), err
        }' "$1"
}

# run_one <bench> <mode> <grammar> <timeout_s>: one run in <out-dir>/<bench>/<mode>-<grammar>, then its rows
run_one() {
    local bench="$1" mode="$2" grammar="$3" to="$4" prefix="$1"$'\t'"$2"$'\t'"$3" dir rc ties note wall rss st last err
    local -a bargs cmd
    dir="$OUTDIR/$bench/$mode-$grammar"
    mapfile -t bargs < <(bench_args "$bench")
    cmd=("$JAVA" "-Xmx$XMX" -jar "$JAR" "${RUNPY_OPTS[@]}" -pta=insens "${bargs[@]}" "-exclude=$JDK_EXCLUDE"
        "-cflidr=$grammar" "-cflidrmode=$mode")
    [ -z "$STACK" ] || cmd+=("-cflidrstack=$STACK")
    cmd+=("${EXTRA[@]}")
    cmd=(timeout -k 30 "$to" "${cmd[@]}")

    rm -rf -- "$dir"
    mkdir -p "$dir"
    { printf '%q ' "${cmd[@]}"; echo; } > "$dir/cmd.txt"
    echo "$to" > "$dir/timeout"
    (cd "$dir" && exec /usr/bin/time -v -o time.txt "${cmd[@]}") > "$dir/out.txt" 2>&1 < /dev/null &
    RUN_PID=$!
    wait "$RUN_PID"
    rc=$?
    RUN_PID=""
    echo "$rc" > "$dir/exit"

    # export counters (order-ties must be 0, E6-S4b): only a run that reached the dump has them
    if [ -f "$dir/sootOutput/cflidr/counters.tsv" ]; then
        cp "$dir/sootOutput/cflidr/counters.tsv" "$dir/counters.tsv"
        awk -v pre="$prefix" 'NF {print pre "\t" $0}' "$dir/counters.tsv" >> "$OUTDIR/counters.tsv"
    fi
    if grep -q '^#CFLIDR-pt-over:' "$dir/out.txt"; then
        ties="$(awk -F'\t' '$1 == "order-ties" {print $2}' "$dir/counters.tsv" 2>/dev/null)"
        note=""
        if [ -z "$ties" ]; then
            note="order-ties missing (no sootOutput/cflidr/counters.tsv or no key order-ties)"
        elif [ "$ties" != 0 ]; then
            note="order-ties $ties (sootOutput/cflidr/counters.tsv), expected 0: the export order may depend on the JVM"
        fi
        if [ -n "$note" ]; then
            echo "e6-probe NOTE: $note" >> "$dir/out.txt"
            printf '%s\t%s\t%s\t%s\n' "$bench" "$mode" "$grammar" "$note" >> "$OUTDIR/notes.tsv"
            echo "e6-probe: NOTE $bench:$mode:$grammar $note"
        fi
    fi

    rc="$(tr -d '[:space:]' < "$dir/exit")"
    IFS=$'\t' read -r wall rss < <(wall_rss "$dir/time.txt")
    IFS=$'\t' read -r st last err < <(scan_out "$dir/out.txt" "$rc" "$prefix" "$OUTDIR/values.tsv")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$bench" "$mode" "$grammar" "$(tr -d '[:space:]' < "$dir/timeout")" \
        "$st" "$rc" "$wall" "$rss" "$last" >> "$OUTDIR/runs.tsv"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$bench" "$mode" "$grammar" "$rc" "$st" "$err" "$wall" \
        "$(sha256sum < "$dir/out.txt" | cut -d' ' -f1)" "$(sha256sum < "$dir/cmd.txt" | cut -d' ' -f1)" >> "$OUTDIR/evidence.tsv"
    echo "e6-probe: $bench:$mode:$grammar:$to $st exit $rc wall_s $wall max_rss_mb $rss last_phase $last"
}

RAW_FILES=()
for s in "${SPECS[@]}"; do
    IFS=: read -r b m g t <<< "$s"
    echo "e6-probe: run $s"
    run_one "$b" "$m" "$g" "$t"
    for f in cmd.txt counters.tsv exit out.txt time.txt timeout; do
        [ -f "$OUTDIR/$b/$m-$g/$f" ] && RAW_FILES+=("$b/$m-$g/$f")
    done
done

# raw.tar.xz: the raw files of this call, in name order
rm -f "$OUTDIR/raw.tar.xz"
printf '%s\n' "${RAW_FILES[@]}" | LC_ALL=C sort -u \
    | tar -C "$OUTDIR" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 --no-recursion -T - -cJf "$OUTDIR/raw.tar.xz" \
    || { echo "e6-probe: packing raw.tar.xz failed" >&2; exit 1; }

write_meta "load1-end" "$(load1)" "finished" "$(date -Iseconds)"
echo "e6-probe: ${#SPECS[@]} runs in $OUT_ARG"
