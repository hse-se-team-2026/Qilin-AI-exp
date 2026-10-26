# Common code of the E5 measurement scripts (sourced, not executed): scripts/ucfs/e5-bench.sh (E5-S2) and the
# minimum-heap search of E5-S3. The contract is docs/ai/tickets/E5-S2.md (in the Diploma_work docs, not in this
# repository).
#
# What it gives:
#   e5_die <msg>                  message on stderr, exit 2 (wrong arguments or environment, before any run)
#   e5_check_java_env             exit 2 when JAVA_TOOL_OPTIONS, _JAVA_OPTIONS or JDK_JAVA_OPTIONS is not empty:
#                                 every JVM of the runs would pick them up
#   e5_known_benches              the names of artifact/util/benchmark.py on one line
#   e5_command <run> <bench>      fills the array E5_CMD with the command line of one run (below)
#   e5_run <dir> <timeout>        one run of E5_CMD in <dir>, which it empties first and which is the working
#                                 directory of the run; writes the files of a run directory (below)
#   e5_machine_meta               "key<TAB>value" lines that describe the machine and the JVM: compressed-oops
#                                 host-kind flavor cpu-model cpu-count mem-total-mb kernel os java-version
#                                 other-java load-start
#   E5_PY_RUN                     python3 source (standard library) of run_facts(<dir>, <timeout>) and
#                                 parse_out(<text>), for the collectors of the scripts (python3 -I -c)
#
# Variables it reads (set and checked by the script that sources it): ROOT (the clone), JAVA (java of JDK 21),
# JAR (realpath of the fat jar), XMX, JDK_BODIES (yes: the JDK with bodies, no -exclude), E5_HOST_KIND, E5_FLAVOR.
#
# Command line of a run (e5_command; nothing else, so that the runs differ only in -pta, -ucfsbinding and -Xmx):
#   <JAVA> -Xmx<XMX> -XX:+ExitOnOutOfMemoryError -jar <JAR> -pae -pe -clinit=ONFLY -lcs -mh <run options>
#   -apppath <A> [-libpath <L>] -mainclass <M> -reflectionlog <T> -jre=<J> -ucfsseam [-exclude=<JDK packages>]
#   <run options>: insens = -pta=insens; ucfs-<B> = -pta=ucfs -ucfsbinding=<B>. <A> <L> <T> <M> are APPPATH,
#   LIBPATH (when the benchmark has one), TAMIFLEXLOG, MAINCLASSES of artifact/util/benchmark.py, the paths
#   under <ROOT>/artifact/; <J> = <ROOT>/artifact/benchmarks/JREs/<JREVERSION>. -exclude unless JDK_BODIES=yes.
#   -XX:+ExitOnOutOfMemoryError: without it Qilin does not end on OutOfMemoryError (its MemoryWatcher timer thread
#   keeps the JVM alive; skill qilin, gotcha 1), so a run with a too small heap would wait for the timeout.
#
# Files of a run directory (e5_run), in the order they are taken:
#   cmd.txt      the command line, arguments separated by spaces, quoted with bash printf %q (shlex.split reads it);
#                written before the run, then rewritten with the command line of the java process as
#                /proc/<pid>/cmdline shows it while the run is going (a warning on stdout when the two differ, a
#                note when the JVM ended before it was seen; then cmd.txt stays the planned one)
#   other-java   pgrep -c -x java: the java processes on the machine just before the run
#   load1        the first number of /proc/loadavg just before the run
#   stat-before  the lines "cpu ", procs_running, procs_blocked of /proc/stat just before the run
#   start        date +%s%N just before the run
#   out.txt      stdout and stderr of the run
#   time.txt     the report of /usr/bin/time -v
#   end          date +%s%N just after the run
#   stat-after   as stat-before, just after the run
#   exit         the exit code of /usr/bin/time -v -o time.txt timeout -k 60 <timeout> <command>
#   The directory sootOutput/ that Qilin writes into the working directory is removed after the run.
# While the run goes, this shell only looks for the java process (it reads /proc every 20 ms until the JVM is
# there, at most 10 s) and then waits for the run; nothing else of the script runs in parallel with it.

JDK_EXCLUDE_E5='java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*'
RUNPY_OPTS_E5=(-pae -pe -clinit=ONFLY -lcs -mh)
JVM_FLAGS_E5=(-XX:+ExitOnOutOfMemoryError)

e5_die() { echo "${E5_NAME:-e5}: $*" >&2; exit 2; }

e5_check_java_env() {
    local v
    for v in JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS; do
        [ -z "${!v:-}" ] || e5_die "$v is set ('${!v}'); every JVM of the runs would pick it up: unset it"
    done
}

e5_known_benches() {
    python3 -I - "$ROOT/artifact/util/benchmark.py" <<'PY'
import runpy, sys
print(" ".join(runpy.run_path(sys.argv[1])["BENCHMARKS"]))
PY
}

# e5_bench_args <bench> -> one argument per line: -apppath, -libpath, -mainclass, -reflectionlog, -jre of
# artifact/util/benchmark.py (its paths are relative to artifact/)
e5_bench_args() {
    python3 -I - "$ROOT/artifact/util/benchmark.py" "$ROOT/artifact" "$1" <<'PY'
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

E5_CMD=()
e5_command() {
    local run="$1" bench="$2"
    local -a opts bargs
    case "$run" in
        insens) opts=(-pta=insens) ;;
        ucfs-*) opts=(-pta=ucfs "-ucfsbinding=${run#ucfs-}") ;;
        *) e5_die "unknown run '$run'" ;;
    esac
    mapfile -t bargs < <(e5_bench_args "$bench")
    E5_CMD=("$JAVA" "-Xmx$XMX" "${JVM_FLAGS_E5[@]}" -jar "$JAR" "${RUNPY_OPTS_E5[@]}" "${opts[@]}" "${bargs[@]}" -ucfsseam)
    [ "$JDK_BODIES" = yes ] || E5_CMD+=("-exclude=$JDK_EXCLUDE_E5")
}

# e5_quoted <args...> -> the arguments quoted with printf %q, separated by spaces, one line
e5_quoted() {
    printf '%q' "$1"
    shift
    [ $# -eq 0 ] || printf ' %q' "$@"
    echo
}

# e5_proc_stat -> the lines "cpu ", procs_running, procs_blocked of /proc/stat (bash builtins only)
e5_proc_stat() {
    local line
    while IFS= read -r line; do
        case "$line" in
            "cpu "* | procs_running* | procs_blocked*) printf '%s\n' "$line" ;;
        esac
    done < /proc/stat
}

# e5_child <pid> -> the first child process of <pid>, or nothing
e5_child() {
    local c=""
    [ -r "/proc/$1/task/$1/children" ] && read -r c _ < "/proc/$1/task/$1/children"
    printf '%s' "$c"
}

# e5_watch_java <pid of /usr/bin/time> -> the NUL-separated /proc/<pid>/cmdline of the java process under
# time -> timeout -> java, or nothing when it was not seen (ended, or not there within 10 s)
e5_watch_java() {
    local tpid="$1" t j comm state i
    for ((i = 0; i < 500; i++)); do
        state=""
        [ -r "/proc/$tpid/stat" ] && read -r _ _ state _ < "/proc/$tpid/stat"
        [ -n "$state" ] && [ "$state" != Z ] || return 0
        t="$(e5_child "$tpid")"
        j=""
        [ -z "$t" ] || j="$(e5_child "$t")"
        if [ -n "$j" ]; then
            comm=""
            read -r comm < "/proc/$j/comm" 2>/dev/null
            if [ "$comm" = java ]; then
                cat "/proc/$j/cmdline" 2>/dev/null
                return 0
            fi
        fi
        sleep 0.02
    done
}

# e5_run <dir> <timeout>: one run of E5_CMD (files above); prints a warning or a note on stdout when the
# command line of the java process differs from E5_CMD or was not seen
e5_run() {
    local dir="$1" timeout="$2" tpid rc load
    local -a seen
    rm -rf -- "$dir"
    mkdir -p "$dir"
    e5_quoted "${E5_CMD[@]}" > "$dir/cmd.txt"
    { pgrep -c -x java || true; } > "$dir/other-java"
    read -r load _ < /proc/loadavg
    echo "$load" > "$dir/load1"
    e5_proc_stat > "$dir/stat-before"
    date +%s%N > "$dir/start"
    (cd "$dir" && exec /usr/bin/time -v -o time.txt timeout -k 60 "$timeout" "${E5_CMD[@]}" > out.txt 2>&1 < /dev/null) &
    tpid=$!
    mapfile -d '' -t seen < <(e5_watch_java "$tpid")
    wait "$tpid"
    rc=$?
    date +%s%N > "$dir/end"
    e5_proc_stat > "$dir/stat-after"
    echo "$rc" > "$dir/exit"
    rm -rf -- "$dir/sootOutput"
    if [ ${#seen[@]} -eq 0 ]; then
        echo "${E5_NAME:-e5}: note: the java process of $dir was not seen; cmd.txt is the planned command line"
    elif [ "$(e5_quoted "${seen[@]}")" != "$(e5_quoted "${E5_CMD[@]}")" ]; then
        echo "${E5_NAME:-e5}: warning: the java process of $dir ran another command line; cmd.txt is that one"
        e5_quoted "${seen[@]}" > "$dir/cmd.txt"
    fi
}

e5_machine_meta() {
    local coops cpu mem os jver ojava load
    coops="$("$JAVA" "-Xmx$XMX" -XX:+PrintFlagsFinal -version 2>/dev/null | awk '$2 == "UseCompressedOops" {print $4}')"
    cpu="$(LC_ALL=C lscpu | sed -n 's/^Model name: *//p' | head -n 1)"
    mem="$(awk '$1 == "MemTotal:" {print int($2 / 1024)}' /proc/meminfo)"
    os="$(. /etc/os-release && echo "$PRETTY_NAME")"
    jver="$("$JAVA" -version 2>&1 | sed -n 2p)"
    ojava="$(pgrep -c -x java || true)"
    read -r load < /proc/loadavg
    printf 'compressed-oops\t%s\n' "$coops"
    printf 'host-kind\t%s\n' "$E5_HOST_KIND"
    printf 'flavor\t%s\n' "$E5_FLAVOR"
    printf 'cpu-model\t%s\n' "$cpu"
    printf 'cpu-count\t%s\n' "$(nproc)"
    printf 'mem-total-mb\t%s\n' "$mem"
    printf 'kernel\t%s\n' "$(uname -r)"
    printf 'os\t%s\n' "$os"
    printf 'java-version\t%s\n' "$jver"
    printf 'other-java\t%s\n' "$ojava"
    printf 'load-start\t%s\n' "$(echo "$load" | cut -d' ' -f1-3)"
}

# shellcheck disable=SC2016
E5_PY_RUN='
import os, re

HASH_LINE = re.compile(r"^#([^:]+):\s*(\S+)\s*$")
QILIN_LINES = [(re.compile(r"^Time \(sec\):\s*(\S+)$"), "qilin-pta-s"),
               (re.compile(r"^Main PTA \(including pre-analysis\) elapsed time: (\S+)s$"), "qilin-main-pta-s"),
               (re.compile(r"^Main PTA consumed memory: (\S+) MB$"), "qilin-main-pta-rss-mb")]

def text(p, default=""):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return default

def parse_out(t):
    """[(key, value)]: the lines "#<key>: <value>" (one-word value) and three result lines of Qilin"""
    res = []
    for line in t.splitlines():
        m = HASH_LINE.match(line)
        if m:
            res.append((m.group(1).strip(), m.group(2)))
            continue
        for rx, key in QILIN_LINES:
            m = rx.match(line.strip())
            if m:
                res.append((key, m.group(1)))
    return res

def gnu_time(p):
    """(wall_s, user_s, sys_s, max_rss_mb) of a report of /usr/bin/time -v; None for a missing value"""
    v = {}
    for line in text(p).splitlines():
        if ": " in line:
            k, x = line.strip().rsplit(": ", 1)
            v[k] = x
    wall = None
    if "Elapsed (wall clock) time (h:mm:ss or m:ss)" in v:
        wall = 0.0
        for part in v["Elapsed (wall clock) time (h:mm:ss or m:ss)"].split(":"):
            wall = wall * 60 + float(part)
    f = lambda k: float(v[k]) if k in v else None
    rss = v.get("Maximum resident set size (kbytes)")
    return wall, f("User time (seconds)"), f("System time (seconds)"), int(rss) // 1024 if rss else None

def proc_stat(t):
    """(the 8 first numbers of the line "cpu ", procs_running) of a /proc/stat snapshot, or None"""
    cpu = re.search(r"^cpu\s+(.*)$", t, re.M)
    pr = re.search(r"^procs_running\s+(\d+)", t, re.M)
    if not cpu or not pr:
        return None
    nums = [int(x) for x in cpu.group(1).split()][:8]
    return nums + [0] * (8 - len(nums)), int(pr.group(1))

def status(rc, out, wall, timeout):
    """ok (exit 0), timeout (exit 124 or, after timeout - 5 s, 137: SIGKILL of timeout -k), killed (137 earlier:
    killed from outside, e.g. by the OOM killer of the kernel), oom (exit 3 of -XX:+ExitOnOutOfMemoryError with
    OutOfMemoryError in the output), error otherwise"""
    if rc == 0:
        return "ok"
    if rc == 124 or (rc == 137 and wall is not None and wall >= timeout - 5):
        return "timeout"
    if rc == 137:
        return "killed"
    if rc == 3 and "OutOfMemoryError" in out:
        return "oom"
    return "error"

def run_facts(d, timeout):
    """{status exit wall_s user_s sys_s max_rss_mb load1 other_java procs_running steal_pct start_ns end_ns} of a
    run directory, the numbers as strings (two decimals for seconds and steal_pct); None without the file exit"""
    if not os.path.isfile(os.path.join(d, "exit")):
        return None
    rd = lambda f: text(os.path.join(d, f)).strip()
    code = rd("exit")
    wall, user, sys_, rss = gnu_time(os.path.join(d, "time.txt"))
    out = text(os.path.join(d, "out.txt"))
    s0, s1 = proc_stat(text(os.path.join(d, "stat-before"))), proc_stat(text(os.path.join(d, "stat-after")))
    steal = ""
    if s0 and s1:
        dall = sum(s1[0]) - sum(s0[0])
        steal = "%.2f" % (100.0 * (s1[0][7] - s0[0][7]) / dall if dall > 0 else 0.0)
    two = lambda x: "" if x is None else "%.2f" % x
    return {"status": status(int(code), out, wall, timeout) if re.fullmatch(r"\d+", code) else "error",
            "exit": code, "wall_s": two(wall), "user_s": two(user), "sys_s": two(sys_),
            "max_rss_mb": "" if rss is None else str(rss), "load1": rd("load1"), "other_java": rd("other-java"),
            "procs_running": str(s0[1]) if s0 else "", "steal_pct": steal, "start_ns": rd("start"),
            "end_ns": rd("end")}
'
