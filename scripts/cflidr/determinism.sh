#!/usr/bin/env bash
# Determinism of the cfl-idr export between runs of the JVM (E6-S4b, docs/ai/tickets/E6-S4b.md).
# Runs the Qilin CLI with -cflidr=parity -cflidrmode=CS (JunitTests options -singleentry -pae -pe -mh -lcs)
# in separate JVMs, each in a fresh directory:
#   - N_CS times (default 6) on acceptance/E6/prog/e6prog/CsFacts.java (javac -g --release 8),
#   - N_MB times (default 3) on the qilin.microben program MB_MAIN (default qilin.microben.core.exception.ExceptionChain:
#     two MergedNewExpr objects, ArithmeticException and ClassCastException),
#     whose export must have an object of a MergedNewExpr (-mh) in vertices.tsv,
# and checks, per program, that every run exits 0 and has, byte for byte, the graph.dot, sites.tsv,
# fields.tsv, counters.tsv, under.tsv, over.tsv of its dump and the #CFLIDR- lines except the *-ms
# times of the first run; vertices.tsv must be the same after dropping node numbers and identity hashes
# (its node column is toString() of Qilin's nodes, which print both). It prints the #CFLIDR- lines and
# the counter order-ties of the first run of each program.
# Heap of each run: XMX (default 4g; the RAM rule of the machine: above 4g only under the heavy-run lock,
# so a larger XMX re-runs this script under flock HEAVY_LOCK). Jar: JAR=<fat jar>, or the fat jar is
# built from the current tree (gradle build -x test, then fatJar -x test; the copy that fatJar writes
# over artifact/Qilin-0.9.9-SNAPSHOT.jar is reverted).
# Output: OUT (default scripts/cflidr/out/determinism, git-ignored), one directory per run.
# Needs: scripts/ucfs/bootstrap.sh, scripts/cflidr/bootstrap.sh, the submodules qilin.microben and
# artifact/benchmarks, JAVA_HOME with a JDK 21 (default the Gradle one).
# Usage: bash scripts/cflidr/determinism.sh      (exit 0 = deterministic, 1 = differs or a run failed,
#                                                 2 = environment)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${JAVA_HOME:=$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
export JAVA_HOME
JAVA="$JAVA_HOME/bin/java"
XMX="${XMX:-4g}"
N_CS="${N_CS:-6}"
N_MB="${N_MB:-3}"
MB_MAIN="${MB_MAIN:-qilin.microben.core.exception.ExceptionChain}"
OUT="${OUT:-$ROOT/scripts/cflidr/out/determinism}"
JRE_DIR="$ROOT/artifact/benchmarks/JREs/jre1.6.0_45"
MICROBEN_CLASSES="$ROOT/qilin.microben/build/classes/java/main"
COMMITTED_JAR="$ROOT/artifact/Qilin-0.9.9-SNAPSHOT.jar"
OPTS=(-pta=insens -singleentry -pae -pe -mh -lcs -cflidr=parity -cflidrmode=CS)

die_env() { echo "ENV: $*"; exit 2; }

heap_gb() {
    case "$1" in
        *g|*G) echo "${1%[gG]}" ;;
        *m|*M) echo $(( ${1%[mM]} / 1024 )) ;;
        *) echo 999 ;;
    esac
}
if [ "$(heap_gb "$XMX")" -gt 4 ] && [ "${HEAVY_LOCK_HELD:-}" != 1 ]; then
    HEAVY_LOCK="${HEAVY_LOCK:-/home/usatovpavel/edu/.heavy-run.lock}"
    echo "XMX=$XMX > 4g: waiting for the heavy-run lock $HEAVY_LOCK"
    exec flock "$HEAVY_LOCK" env HEAVY_LOCK_HELD=1 bash "$0" "$@"
fi

[ -x "$JAVA" ] || die_env "no java in JAVA_HOME=$JAVA_HOME"
[ -f "$JRE_DIR/lib/rt.jar" ] || die_env "needs: git submodule update --init --depth 1 artifact/benchmarks"
mkdir -p "$OUT/logs"

if [ -z "${JAR:-}" ]; then
    git diff --quiet -- "$COMMITTED_JAR" || die_env "$COMMITTED_JAR has local changes"
    rm -f build/libs/Qilin-*.jar
    bash ./gradlew --console=plain build -x test > "$OUT/logs/fatjar.log" 2>&1 \
        && bash ./gradlew --console=plain fatJar -x test >> "$OUT/logs/fatjar.log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -f build/libs/Qilin-0.9.9-SNAPSHOT.jar ] && cp build/libs/Qilin-0.9.9-SNAPSHOT.jar "$OUT/qilin-fat.jar"
    git checkout -q -- "$COMMITTED_JAR"
    [ $rc -eq 0 ] && [ -f "$OUT/qilin-fat.jar" ] || die_env "fat jar build failed (exit $rc, $OUT/logs/fatjar.log)"
    JAR="$OUT/qilin-fat.jar"
fi
[ -f "$JAR" ] || die_env "no jar $JAR"
[ -d "$MICROBEN_CLASSES" ] || die_env "no $MICROBEN_CLASSES: git submodule update --init qilin.microben and gradle build"

PROG="$OUT/prog-classes"
rm -rf "${PROG:?}" && mkdir -p "$PROG"
"$JAVA_HOME/bin/javac" -g --release 8 -d "$PROG" acceptance/E6/prog/e6prog/CsFacts.java \
    > "$OUT/logs/javac.log" 2>&1 || die_env "javac CsFacts failed ($OUT/logs/javac.log)"

FAILS=0

# run_one <dir> <apppath> <mainclass>
run_one() {
    local dir="$1" app="$2" main="$3" rc
    rm -rf "${dir:?}" && mkdir -p "$dir"
    (cd "$dir" && timeout 900 "$JAVA" -Xmx"$XMX" -jar "$JAR" -apppath "$app" -mainclass "$main" -jre="$JRE_DIR" \
        "${OPTS[@]}" > out.txt 2>&1)
    rc=$?
    echo "$rc" > "$dir/rc"
    grep '^#CFLIDR-' "$dir/out.txt" | grep -v -- '-ms: ' > "$dir/cflidr-lines.txt"
    if [ -f "$dir/sootOutput/cflidr/vertices.tsv" ]; then
        sed -E 's/([A-Za-z]*Node) [0-9]+/\1 #/g; s/^([0-9]+\t[A-Z_]+\t)[A-Za-z]+[0-9]+/\1#/; s/@[0-9a-f]{4,8}\b/@/g' \
            "$dir/sootOutput/cflidr/vertices.tsv" > "$dir/vertices-stable.tsv"
    fi
    return $rc
}

# check_program <name> <n> <apppath> <mainclass> [must-match regex in vertices.tsv]
check_program() {
    local name="$1" n="$2" app="$3" main="$4" need="${5:-}" i d first ok f
    first="$OUT/$name-1"
    for i in $(seq 1 "$n"); do
        d="$OUT/$name-$i"
        run_one "$d" "$app" "$main"
        echo "$name run $i: exit $(cat "$d/rc")"
    done
    ok=1
    for i in $(seq 1 "$n"); do
        d="$OUT/$name-$i"
        if [ "$(cat "$d/rc")" != 0 ] || ! grep -q '^#CFLIDR-pt-over: ' "$d/cflidr-lines.txt"; then
            echo "FAIL: $name run $i did not finish (exit $(cat "$d/rc"), $d/out.txt)"
            ok=0
            continue
        fi
        [ "$i" = 1 ] && continue
        for f in sootOutput/cflidr/graph.dot sootOutput/cflidr/sites.tsv sootOutput/cflidr/fields.tsv \
            sootOutput/cflidr/counters.tsv sootOutput/cflidr/under.tsv sootOutput/cflidr/over.tsv \
            cflidr-lines.txt vertices-stable.tsv; do
            if ! cmp -s "$first/$f" "$d/$f"; then
                echo "FAIL: $name run $i: $f differs from run 1"
                ok=0
            fi
        done
    done
    if [ -n "$need" ] && ! grep -qE "$need" "$first/sootOutput/cflidr/vertices.tsv" 2>/dev/null; then
        echo "FAIL: $name: no vertex matching '$need' in vertices.tsv"
        ok=0
    fi
    sed 's/^/  /' "$first/cflidr-lines.txt"
    echo "  order-ties: $(sed -n 's/^order-ties\t//p' "$first/sootOutput/cflidr/counters.tsv" 2>/dev/null)"
    echo "  graph.dot sha256: $(sha256sum "$first/sootOutput/cflidr/graph.dot" 2>/dev/null | cut -d' ' -f1)"
    if [ $ok = 1 ]; then
        echo "PASS: $name: $n JVM runs, the same graph.dot, dump files and #CFLIDR- lines (without -ms)"
    else
        FAILS=$((FAILS + 1))
    fi
}

check_program csfacts "$N_CS" "$PROG" e6prog.CsFacts 'MergedNewExpr'
check_program microben "$N_MB" "$MICROBEN_CLASSES" "$MB_MAIN" 'MergedNewExpr'

if [ $FAILS -eq 0 ]; then
    echo "determinism: PASS"
    exit 0
fi
echo "determinism: FAIL ($FAILS programs)"
exit 1
