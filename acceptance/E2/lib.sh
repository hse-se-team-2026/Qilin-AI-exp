# Common helpers for E2 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E2.md (in the Diploma_work docs, not in this repository).

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${JAVA_HOME:=$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
export JAVA_HOME
JAVA="$JAVA_HOME/bin/java"

OUT="$ROOT/acceptance/E2/out"          # git-ignored; not under build/ because `clean` wipes build/
LOGS="$OUT/logs"
mkdir -p "$LOGS"

# Small program shipped with Qilin and the JRE model from the benchmarks submodule.
EXAMPLE_JAR="$ROOT/docs/example/example01/example.jar"
JRE_DIR="$ROOT/artifact/benchmarks/JREs/jre1.6.0_45"
# Prebuilt jar committed in the repository (built by upstream before 91d6d97). It is the
# reference for CLI behaviour and metrics; it must stay unchanged.
COMMITTED_JAR="$ROOT/artifact/Qilin-0.9.9-SNAPSHOT.jar"

FAILS=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }
die_env() { echo "ENV: $*"; exit 2; }

gradle() {
    bash ./gradlew --console=plain "$@"
}

need_submodules() {
    [ -f "$JRE_DIR/lib/rt.jar" ] && [ -d qilin.microben/build/classes/java/main ] \
        || die_env "needs: git submodule update --init qilin.microben && git submodule update --init --depth 1 artifact/benchmarks"
}

need_ucfs() {
    local v
    v="$(sed -n 's/^ucfsVersion=//p' gradle.properties | tail -n 1 | tr -d '\r')"
    [ -f ".ucfs/m2/org/ucfs/solver/$v/solver-$v.pom" ] \
        || die_env "UCFS org.ucfs:solver:$v is not in .ucfs/m2: run 'bash scripts/ucfs/bootstrap.sh'"
}

# junit_summary <dir-with-TEST-*.xml>  -> prints "tests skipped failures errors"
junit_summary() {
    python3 - "$1" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
t = s = f = e = 0
for p in glob.glob(os.path.join(sys.argv[1], "TEST-*.xml")):
    r = ET.parse(p).getroot()
    t += int(r.get("tests", 0)); s += int(r.get("skipped", 0))
    f += int(r.get("failures", 0)); e += int(r.get("errors", 0))
print(t, s, f, e)
PY
}

# junit_case_status <dir> <classname> <testname> -> PASSED | SKIPPED | FAILED | MISSING
junit_case_status() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
d, cls, name = sys.argv[1:4]
status = "MISSING"
for p in glob.glob(os.path.join(d, "TEST-*.xml")):
    for tc in ET.parse(p).getroot().iter("testcase"):
        if tc.get("classname") == cls and tc.get("name", "") == name:
            if tc.find("failure") is not None or tc.find("error") is not None:
                status = "FAILED"
            elif tc.find("skipped") is not None:
                status = "SKIPPED"
            else:
                status = "PASSED"
print(status)
PY
}

# safe_reset_dir <dir>: rm -rf + mkdir, only under acceptance/E2/out/ of this repository.
safe_reset_dir() {
    local d
    d="$(realpath -m "$1")"
    case "$d" in
        "$OUT"/?*) ;;
        *) die_env "refusing to delete '$d': allowed only under $OUT/" ;;
    esac
    rm -rf "$d" && mkdir -p "$d"
}

# build_fatjar <dest.jar>: `gradle fatJar -x test` from the current tree, copy the fresh jar to
# <dest.jar>. The fatJar task also copies its jar over the committed artifact/ jar; that copy is
# reverted here, so the working tree stays clean. Returns the Gradle exit code.
build_fatjar() {
    local dest="$1" rc
    git diff --quiet -- "$COMMITTED_JAR" \
        || die_env "$COMMITTED_JAR has local changes; it must equal the committed jar"
    rm -f build/libs/Qilin-*.jar "$dest"
    gradle fatJar -x test > "$LOGS/fatjar.log" 2>&1
    rc=$?
    [ $rc -eq 0 ] && [ -f build/libs/Qilin-0.9.9-SNAPSHOT.jar ] && cp build/libs/Qilin-0.9.9-SNAPSHOT.jar "$dest"
    git checkout -q -- "$COMMITTED_JAR"
    return $rc
}

# run_qilin <jar> <name> <qilin args...>: runs driver.Main of <jar> on example01 in a fresh
# directory (sootOutput goes to the CWD). Writes $OUT/run-<name>/{out.txt,metrics.txt,rc}.
# metrics.txt = the lines starting with '#' (the printed statistics). Returns the exit code.
run_qilin() {
    local jar="$1" name="$2" dir rc
    shift 2
    dir="$OUT/run-$name"
    safe_reset_dir "$dir"
    (cd "$dir" && timeout 300 "$JAVA" -Xmx2g -jar "$jar" -apppath "$EXAMPLE_JAR" -mainclass Main \
        -jre="$JRE_DIR" "$@" > out.txt 2>&1)
    rc=$?
    echo "$rc" > "$dir/rc"
    grep '^#' "$dir/out.txt" > "$dir/metrics.txt"
    return $rc
}

finish() {
    if [ "$FAILS" -eq 0 ]; then
        echo "RESULT: PASS ($1)"
        exit 0
    fi
    echo "RESULT: FAIL ($1): $FAILS check(s) failed"
    exit 1
}
