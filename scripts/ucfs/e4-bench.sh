#!/usr/bin/env bash
# E4 benchmark runner: Spark and -pta=ucfs on the benchmarks of artifact/benchmarks, one run after another,
# with time and peak memory of each run, and the results collected into TSV files.
#
# Usage: bash scripts/ucfs/e4-bench.sh <out-dir> <bench>...
#   <bench> is a name of artifact/util/benchmark.py: antlr bloat chart eclipse fop luindex lusearch pmd xalan
#   checkstyle findbugs JPC. An unknown benchmark or run name (RUNS) exits 2 before the first run.
#   Exit 0 when every run was started and the TSV files are written; the outcome of a run is its status
#   in runs.tsv, not the exit code of this script.
#
# Environment:
#   QILIN_JAR  fat jar of Qilin (default build/libs/Qilin-0.9.9-SNAPSHOT.jar of this repository)
#   JAVA_HOME  JDK 21 (default ~/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2); java is $JAVA_HOME/bin/java
#   TIMEOUT    seconds per run (default 900); a run over it is stopped by timeout(1), exit 124
#   XMX        maximum heap of each run, -Xmx (default 16g)
#   RUNS       the runs of each benchmark, in this order (default "insens ucfs-ANALYSIS ucfs-CALL_GRAPH cov-D3 cov-JDK"):
#                insens          -pta=insens
#                ucfs-<B>        -pta=ucfs -ucfsbinding=<B> -ucfscompare -ucfspt   (B = ANALYSIS or CALL_GRAPH)
#                cov-D3          -pta=insens -stats
#                cov-JDK         -pta=insens -stats, without -exclude (the JDK with bodies)
#   Every run also has the arguments of the benchmark as artifact/util/benchmark.py gives them (-apppath,
#   -libpath, -mainclass, -reflectionlog, -jre=artifact/benchmarks/JREs/<JREVERSION>; paths from the root of
#   this repository), the options of artifact/run.py in the zipper style (-pae -pe -clinit=ONFLY -lcs -mh),
#   -ucfsseam and, except cov-JDK, -exclude=<JDK packages> (JDK bodies excluded, docs/ai/tickets/E4.md D3).
#
# Files:
#   <out-dir>/<bench>/<run>/  the run directory, also the working directory of the run (sootOutput/ is there):
#     cmd.txt   the java command line, arguments separated by spaces, shell characters escaped with '\'
#     out.txt   stdout and stderr of the run
#     time.txt  the report of /usr/bin/time -v
#     exit      the exit code of the run
#     The directory is removed before its run. After cov-D3 and cov-JDK the files sootOutput/**/*VarPointsTo.csv
#     of -stats are deleted (with JDK bodies up to gigabytes per run; nothing here reads them), one line
#     "e4-bench: removed ..." per file on stdout.
#   <out-dir>/runs.tsv      bench run status exit wall_s max_rss_mb; status ok (exit 0), timeout (exit 124) or
#                           error; wall_s = "Elapsed (wall clock)" of time.txt with one decimal; max_rss_mb =
#                           "Maximum resident set size" / 1024, rounded down
#   <out-dir>/values.tsv    bench run key value; one row per line "#<key>: <value>" of out.txt, and for ucfs runs
#                           one row per cell of sootOutput/ucfs-compare/metrics.tsv, key cmp/<VIEW>/<metric>
#                           (the metric without '#' and ':')
#   <out-dir>/examples.tsv  bench run class var object; for each ucfs run with status ok and each class other
#                           than SAME of sootOutput/ucfs-compare/pairs.tsv, the up to 3 smallest distinct pairs
#                           (var, object) in code point order; var and object are the node strings of
#                           sootOutput/ucfs/vertices.tsv without the leading "<NodeKind> <number> " and with
#                           every Java identity hash "@<hex>" written "@*"
#   <out-dir>/meta.tsv      key value: command, git-head and tree-clean (yes when `git status --porcelain
#                           --untracked-files=no` is empty) at the start, jar, jar-sha256, benches, runs, timeout,
#                           xmx, started, finished
#   The three result TSV files are collected from all run directories in <out-dir>, also from earlier calls.
#   meta.tsv describes this call only.
#
# Stdout: "e4-bench: <bench> <run>" before each run and the last line
# "e4-bench: <n> runs, <n> values, <n> examples in <out-dir>".
# Requires bash, python3 (standard library only), GNU time at /usr/bin/time, timeout(1); no network.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_PY="$ROOT/artifact/util/benchmark.py"
ALL_RUNS="insens ucfs-ANALYSIS ucfs-CALL_GRAPH cov-D3 cov-JDK"
# JDK packages without bodies (E4.md D3); the same list as JDK_EXCLUDE of acceptance/E4/lib.sh
JDK_EXCLUDE='java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*'
# Options of artifact/run.py in the zipper style (ZIPPEROPTIONS)
RUNPY_OPTS=(-pae -pe -clinit=ONFLY -lcs -mh)

die() { echo "e4-bench: $*" >&2; exit 2; }

[ $# -ge 2 ] || die "usage: bash scripts/ucfs/e4-bench.sh <out-dir> <bench>..."
OUT_ARG="$1"
shift
BENCHES=("$@")

QILIN_JAR="${QILIN_JAR:-$ROOT/build/libs/Qilin-0.9.9-SNAPSHOT.jar}"
JAVA_HOME="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
JAVA="$JAVA_HOME/bin/java"
TIMEOUT="${TIMEOUT:-900}"
XMX="${XMX:-16g}"
read -r -a RUN_LIST <<< "${RUNS:-$ALL_RUNS}"

[ ${#RUN_LIST[@]} -gt 0 ] || die "RUNS is empty"
for r in "${RUN_LIST[@]}"; do
    case " $ALL_RUNS " in
        *" $r "*) ;;
        *) die "unknown run '$r' in RUNS (known: $ALL_RUNS)" ;;
    esac
done
[ -f "$BENCH_PY" ] || die "$BENCH_PY not found (git submodule update --init --depth 1 artifact/benchmarks?)"
KNOWN_BENCHES="$(python3 -I - "$BENCH_PY" <<'PY'
import runpy, sys
print(" ".join(runpy.run_path(sys.argv[1])["BENCHMARKS"]))
PY
)" || die "cannot read $BENCH_PY"
for b in "${BENCHES[@]}"; do
    case " $KNOWN_BENCHES " in
        *" $b "*) ;;
        *) die "unknown benchmark '$b' (known: $KNOWN_BENCHES)" ;;
    esac
done
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "TIMEOUT must be a positive number of seconds, got '$TIMEOUT'"
[[ "$XMX" =~ ^[1-9][0-9]*[kKmMgG]?$ ]] || die "XMX must be a heap size such as 16g, got '$XMX'"
[ -x "$JAVA" ] || die "no java at $JAVA (set JAVA_HOME to a JDK 21)"
[ -x /usr/bin/time ] || die "GNU time /usr/bin/time is needed"
[ -f "$QILIN_JAR" ] || die "QILIN_JAR $QILIN_JAR not found (build it: gradlew build -x test && gradlew fatJar -x test)"
JAR="$(realpath "$QILIN_JAR")"

mkdir -p "$OUT_ARG" || die "cannot create $OUT_ARG"
OUTDIR="$(realpath "$OUT_ARG")"

# Taken at the start: the code that the results come from (E4.md D19)
GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
if [ -n "$GIT_HEAD" ] && [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    TREE_CLEAN=yes
else
    TREE_CLEAN=no
fi
JAR_SHA="$(sha256sum "$JAR" | cut -d' ' -f1)"
STARTED="$(date -Iseconds)"
COMMAND="bash scripts/ucfs/e4-bench.sh$(printf ' %q' "$OUT_ARG" "${BENCHES[@]}")"

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
    printf 'timeout\t%s\n' "$TIMEOUT"
    printf 'xmx\t%s\n' "$XMX"
    printf 'started\t%s\n' "$STARTED"
    printf 'finished\t%s\n' "$1"
}
write_meta "" > "$OUTDIR/meta.tsv"

# bench_args <bench> -> one argument per line: -apppath, -libpath, -mainclass, -reflectionlog, -jre of
# artifact/util/benchmark.py (its paths are relative to artifact/)
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

# run_one <bench> <run>: one run in <out-dir>/<bench>/<run>
run_one() {
    local bench="$1" run="$2" dir rc f size
    local -a opts bargs cmd
    dir="$OUTDIR/$bench/$run"
    case "$run" in
        insens) opts=(-pta=insens) ;;
        ucfs-*) opts=(-pta=ucfs "-ucfsbinding=${run#ucfs-}" -ucfscompare -ucfspt) ;;
        cov-*) opts=(-pta=insens -stats) ;;
    esac
    mapfile -t bargs < <(bench_args "$bench")
    cmd=("$JAVA" "-Xmx$XMX" -jar "$JAR" "${RUNPY_OPTS[@]}" "${opts[@]}" "${bargs[@]}" -ucfsseam)
    [ "$run" = cov-JDK ] || cmd+=("-exclude=$JDK_EXCLUDE")

    rm -rf -- "$dir"
    mkdir -p "$dir"
    { printf '%q' "${cmd[0]}"; printf ' %q' "${cmd[@]:1}"; echo; } > "$dir/cmd.txt"
    (cd "$dir" && /usr/bin/time -v -o time.txt timeout -k 60 "$TIMEOUT" "${cmd[@]}" > out.txt 2>&1 < /dev/null)
    rc=$?
    echo "$rc" > "$dir/exit"

    if [[ "$run" == cov-* ]] && [ -d "$dir/sootOutput" ]; then
        while IFS= read -r -d '' f; do
            size="$(stat -c %s "$f")"
            rm -f -- "$f"
            echo "e4-bench: removed ${f#"$OUTDIR"/} ($size bytes)"
        done < <(find "$dir/sootOutput" -type f -name '*VarPointsTo.csv' -print0 | sort -z)
    fi
}

for b in "${BENCHES[@]}"; do
    for r in "${RUN_LIST[@]}"; do
        echo "e4-bench: $b $r"
        run_one "$b" "$r"
    done
done

# Collect runs.tsv, values.tsv, examples.tsv from all run directories of <out-dir>; prints the three row counts
counts="$(python3 -I - "$OUTDIR" "$KNOWN_BENCHES" "$ALL_RUNS" <<'PY'
import os, re, sys
out, benches, runs = sys.argv[1], sys.argv[2].split(), sys.argv[3].split()
LINE = re.compile(r"^#([^:]+):\s*(\S+)\s*$")
WALL = re.compile(r"^\s*Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (\S+)\s*$")
RSS = re.compile(r"^\s*Maximum resident set size \(kbytes\): (\d+)\s*$")

def lines(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return [l.rstrip("\n") for l in f]

def wall_rss(d):
    wall = rss = ""
    p = os.path.join(d, "time.txt")
    if os.path.isfile(p):
        for l in lines(p):
            m = WALL.match(l)
            if m:
                s = 0.0
                for part in m.group(1).split(":"):
                    s = s * 60 + float(part)
                wall = "%.1f" % s
            m = RSS.match(l)
            if m:
                rss = str(int(m.group(1)) // 1024)
    return wall, rss

def node_strings(p):
    node = {}
    for l in lines(p):
        f = l.split("\t", 2)
        if len(f) == 3:
            node[f[1]] = re.sub(r"@[0-9a-f]+\b", "@*", re.sub(r"^\w+ \d+ ", "", f[2]))
    return node

R, V, E = [], [], []
for b in benches:
    for r in runs:
        d = os.path.join(out, b, r)
        if not os.path.isfile(os.path.join(d, "exit")):
            continue
        code = open(os.path.join(d, "exit")).read().strip()
        status = "ok" if code == "0" else "timeout" if code == "124" else "error"
        R.append([b, r, status, code, *wall_rss(d)])
        if os.path.isfile(os.path.join(d, "out.txt")):
            for l in lines(os.path.join(d, "out.txt")):
                m = LINE.match(l)
                if m:
                    V.append([b, r, m.group(1).strip(), m.group(2)])
        so = os.path.join(d, "sootOutput")
        mt = os.path.join(so, "ucfs-compare", "metrics.tsv")
        if r.startswith("ucfs-") and os.path.isfile(mt):
            rows = [l.split("\t") for l in lines(mt) if l.strip()]
            for row in rows[1:]:
                name = row[0].lstrip("#").rstrip(":").strip()
                for view, x in zip(rows[0][1:], row[1:]):
                    V.append([b, r, "cmp/%s/%s" % (view, name), x])
        pt = os.path.join(so, "ucfs-compare", "pairs.tsv")
        vt = os.path.join(so, "ucfs", "vertices.tsv")
        if r.startswith("ucfs-") and status == "ok" and os.path.isfile(pt) and os.path.isfile(vt):
            node = node_strings(vt)
            by = {}
            for l in lines(pt):
                f = l.split("\t")
                if len(f) == 6 and f[5] != "SAME":
                    by.setdefault(f[5], set()).add((node.get(f[0], f[0]), node.get(f[1], f[1])))
            for c in sorted(by):
                for var, obj in sorted(by[c])[:3]:
                    E.append([b, r, c, var, obj])

def write(name, header, rows):
    with open(os.path.join(out, name), "w", encoding="utf-8") as f:
        f.write("\t".join(header) + "\n")
        for row in rows:
            f.write("\t".join(row) + "\n")

write("runs.tsv", ["bench", "run", "status", "exit", "wall_s", "max_rss_mb"], R)
write("values.tsv", ["bench", "run", "key", "value"], V)
write("examples.tsv", ["bench", "run", "class", "var", "object"], E)
print(len(R), len(V), len(E))
PY
)" || { echo "e4-bench: collecting the TSV files failed" >&2; exit 1; }
read -r n_runs n_values n_examples <<< "$counts"

write_meta "$(date -Iseconds)" > "$OUTDIR/meta.tsv"
echo "e4-bench: $n_runs runs, $n_values values, $n_examples examples in $OUT_ARG"
