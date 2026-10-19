# Common helpers for E4 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Reuses the E3 helpers (acceptance/E3/lib.sh, unchanged; it sources acceptance/E2/lib.sh) and moves
# the output directory to acceptance/E4/out (git-ignored by the root .gitignore rule "out/").
# Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E4.md (in the Diploma_work docs, not in this repository).

source "$(dirname "${BASH_SOURCE[0]}")/../E3/lib.sh"

OUT="$ROOT/acceptance/E4/out"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

BENCH="$ROOT/artifact/benchmarks"
# JDK packages without bodies in the E4 benchmark runs (E4.md D3); the same list as scripts/ucfs/e4-bench.sh
JDK_EXCLUDE='java.*;javax.*;sun.*;com.sun.*;sunw.*;org.omg.*;org.w3c.*;org.xml.*;org.ietf.*;jdk.*'
# Options of artifact/run.py (zipper style) used in E4 for the benchmarks
RUNPY_OPTS="-pae -pe -clinit=ONFLY -lcs -mh"
# Options of JunitTests for the qilin.microben programs
JUNIT_OPTS="-singleentry -pae -pe -mh -lcs"

# dacapo_args <bench> -> -apppath/-libpath/-mainclass/-reflectionlog of a DaCapo-2006 benchmark
dacapo_args() {
    echo "-apppath $BENCH/dacapo2006/$1.jar -libpath $BENCH/dacapo2006/$1-deps.jar -mainclass dacapo.$1.Main -reflectionlog $BENCH/dacapo2006/$1-refl.log"
}

# fresh_fatjar <dest>: build the fat jar of the current tree (build -x test, then fatJar -x test)
fresh_fatjar() {
    build_fatjar "$1"
    local rc=$?
    echo "fat jar build exit code: $rc (log: $LOGS/fatjar.log)"
    [ $rc -eq 0 ] && [ -f "$1" ]
}

# run_cli <jar> <name> <qilin args...> -> $OUT/run-<name>/{out.txt,metrics.txt,rc,classload.txt}
# runs driver.Main in a fresh directory (sootOutput goes to the CWD), -Xmx8g, timeout 900 s
run_cli() {
    local jar="$1" name="$2" dir rc
    shift 2
    dir="$OUT/run-$name"
    safe_reset_dir "$dir"
    # shellcheck disable=SC2068
    (cd "$dir" && timeout 900 "$JAVA" -Xmx8g -Xlog:class+load=info:file=classload.txt -jar "$jar" -jre="$JRE_DIR" $@ \
        > out.txt 2>&1)
    rc=$?
    echo "$rc" > "$dir/rc"
    grep '^#' "$dir/out.txt" > "$dir/metrics.txt"
    return $rc
}

# andersen_check <dump dir with graph.dot, vertices.tsv, pts.tsv> -> 0 when the independent
# Andersen fixpoint of graph.dot equals pts.tsv (acceptance/E4/AndersenCheck.java)
andersen_check() {
    "$JAVA" -Xmx8g acceptance/E4/AndersenCheck.java "$1"
}
