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

# build_fatjar <dest.jar> [gradle tasks...]: build the fat jar from the current tree and copy it
# to <dest.jar>. Default: two Gradle runs, `build -x test` (every subproject jar) and then
# `fatJar -x test`. Reason (base 73db8b4): the fatJar task does not depend on the subproject
# jars, so alone it packs stale qilin.*/build/libs jars, `clean fatJar` fails ("Cannot expand
# ZIP ... does not exist") and `build fatJar` in one run fails Gradle's task validation
# ("uses this output of task ':qilin.pta:jar' without declaring ... dependency").
# With explicit tasks, one Gradle run with exactly those tasks. fatJar also copies its jar over
# the committed artifact/ jar; that copy is reverted here, so the working tree stays clean.
# Returns the Gradle exit code.
build_fatjar() {
    local dest="$1" rc
    shift
    git diff --quiet -- "$COMMITTED_JAR" \
        || die_env "$COMMITTED_JAR has local changes; it must equal the committed jar"
    rm -f build/libs/Qilin-*.jar "$dest"
    if [ $# -gt 0 ]; then
        gradle "$@" > "$LOGS/fatjar.log" 2>&1
        rc=$?
    else
        gradle build -x test > "$LOGS/fatjar.log" 2>&1 && gradle fatJar -x test >> "$LOGS/fatjar.log" 2>&1
        rc=$?
    fi
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

# ucfs_version -> ucfsVersion from gradle.properties
ucfs_version() {
    sed -n 's/^ucfsVersion=//p' "$ROOT/gradle.properties" | tail -n 1 | tr -d '\r'
}

# pom_stdlib_version -> version of org.jetbrains.kotlin:kotlin-stdlib in the published solver POM
pom_stdlib_version() {
    local v
    v="$(ucfs_version)"
    python3 - "$ROOT/.ucfs/m2/org/ucfs/solver/$v/solver-$v.pom" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"<artifactId>kotlin-stdlib</artifactId>\s*<version>([^<]+)</version>", t)
print(m.group(1) if m else "")
PY
}

# resolved_versions <gradle-dependencies-output> <group:artifact> -> sorted unique resolved
# versions of that module ("1.0 -> 2.0" counts as 2.0; "(c)" constraint lines are ignored)
resolved_versions() {
    python3 - "$1" "$2" <<'PY'
import re, sys
mod = re.escape(sys.argv[2])
vs = set()
for line in open(sys.argv[1], errors="replace"):
    if "(c)" in line:
        continue
    m = re.search(r"(?<![\w.-])" + mod + r":([^\s]+)(?:\s+->\s+([^\s]+))?", line)
    if m:
        vs.add(m.group(2) or m.group(1))
print(" ".join(sorted(vs)))
PY
}

# kotlin_metadata_class <jar> <entry> -> exit 0 if the class file carries kotlin.Metadata
kotlin_metadata_class() {
    unzip -p "$1" "$2" 2>/dev/null | grep -aq 'Lkotlin/Metadata;'
}

finish() {
    if [ "$FAILS" -eq 0 ]; then
        echo "RESULT: PASS ($1)"
        exit 0
    fi
    echo "RESULT: FAIL ($1): $FAILS check(s) failed"
    exit 1
}
