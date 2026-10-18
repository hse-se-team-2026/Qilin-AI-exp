# Common helpers for E3 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Reuses the E2 helpers (acceptance/E2/lib.sh, unchanged) and moves the output directory to
# acceptance/E3/out. Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E3.md (in the Diploma_work docs, not in this repository).

source "$(dirname "${BASH_SOURCE[0]}")/../E2/lib.sh"

OUT="$ROOT/acceptance/E3/out"          # git-ignored
LOGS="$OUT/logs"
mkdir -p "$LOGS"

MICROBEN_CLASSES="$ROOT/qilin.microben/build/classes/java/main"
JAVAP="$JAVA_HOME/bin/javap"

# xml_dir_of <module> -> directory with the JUnit XML results of <module>
xml_dir_of() {
    echo "$ROOT/$1/build/test-results/test"
}

# junit_stdout <dir> <classname> <prefix> -> the stdout lines of <classname> starting with <prefix>
junit_stdout() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
d, cls, prefix = sys.argv[1:4]
for p in sorted(glob.glob(os.path.join(d, "TEST-" + cls + ".xml"))):
    so = ET.parse(p).getroot().find("system-out")
    for line in (so.text or "").splitlines() if so is not None else []:
        if line.startswith(prefix):
            print(line)
PY
}

# expect_cases <module> <classname> <case>... : every case PASSED (MISSING/FAILED/SKIPPED = FAIL)
expect_cases() {
    local module="$1" cls="$2" c st
    shift 2
    for c in "$@"; do
        st="$(junit_case_status "$(xml_dir_of "$module")" "$cls" "$c")"
        [ "$st" = PASSED ] && pass "$cls.$c PASSED" || fail "$cls.$c: $st"
    done
}

# clean_build: remove old results and qilin.ucfs/build, run `gradle clean build` (log in $LOGS/build.log)
clean_build() {
    rm -rf qilin.ucfs/build qilin.pta/build/test-results
    gradle clean build > "$LOGS/build.log" 2>&1
}

# module_totals <module> -> "tests skipped failures errors"
module_totals() {
    junit_summary "$(xml_dir_of "$1")"
}

# check_totals: qilin.pta >= $1 tests, <= 11 skipped, 0 failed; qilin.ucfs >= $2 tests, 0 failed/skipped
check_totals() {
    local t s f e
    read -r t s f e <<< "$(module_totals qilin.pta)"
    echo "  qilin.pta: tests=$t skipped=$s failures=$f errors=$e"
    [ "$t" -ge "$1" ] && [ "$s" -le 11 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
        && pass "qilin.pta: >= $1 tests, <= 11 skipped, 0 failed" || fail "qilin.pta: need >= $1 tests, <= 11 skipped, 0 failed"
    read -r t s f e <<< "$(module_totals qilin.ucfs)"
    echo "  qilin.ucfs: tests=$t skipped=$s failures=$f errors=$e"
    [ "$t" -ge "$2" ] && [ "$s" -eq 0 ] && [ "$f" -eq 0 ] && [ "$e" -eq 0 ] \
        && pass "qilin.ucfs: >= $2 tests, 0 skipped, 0 failed" || fail "qilin.ucfs: need >= $2 tests, 0 skipped, 0 failed"
}

# ucfs_jar -> path of the qilin.ucfs jar built by `gradle build`
ucfs_jar() {
    ls qilin.ucfs/build/libs/qilin.ucfs-*.jar 2>/dev/null | head -n 1
}

# kotlin_class_in_ucfs_jar <class path in jar>... : each class is compiled Kotlin in the qilin.ucfs jar
kotlin_class_in_ucfs_jar() {
    local j c
    j="$(ucfs_jar)"
    for c in "$@"; do
        [ -n "$j" ] && kotlin_metadata_class "$j" "$c" && pass "$c is compiled Kotlin in qilin.ucfs" \
            || fail "$c is not a Kotlin class of the qilin.ucfs jar"
    done
}

# bytecode_check <jar> <class> <method name> <descriptor prefix> <mode> <callee regex>
#   Reads `javap -c -p -s` of <class> in <jar> and finds the method <method name> whose descriptor
#   starts with <descriptor prefix> (JVM form, e.g. "(Lqilin/core/PTA;)"). Modes:
#     invokes  - the method body has an invoke instruction whose javap comment matches <callee regex>;
#     returns  - in addition, every areturn of the method directly follows such an invoke (checkcast
#                in between allowed), i.e. the method returns the value of that call.
#   Prints one line "BYTECODE ..." and exits 0 when the property holds, 1 otherwise.
bytecode_check() {
    local jar="$1" cls="$2" dump rc
    shift 2
    dump="$(mktemp)"
    "$JAVAP" -c -p -s -classpath "$jar" "$cls" > "$dump" 2>&1
    python3 - "$dump" "$@" <<'PY'
import re, sys
dump, name, desc, mode, callee = sys.argv[1:6]
lines = open(dump).read().split("\n")
body, cur, start = None, None, None
for i, l in enumerate(lines):
    m = re.match(r"^  \S.*\b(\w+)\(.*\);$", l)
    if m:
        cur = m.group(1)
        continue
    if cur == name and l.strip().startswith("descriptor: " + desc):
        start = i
        break
if start is None:
    print("BYTECODE %s%s: method not found" % (name, desc)); sys.exit(1)
body = []
for l in lines[start + 1:]:
    if re.match(r"^  \S", l) or l.strip() == "}":
        break
    m = re.match(r"^\s+\d+: (\w+)\s*(.*)$", l)
    if m:
        body.append((m.group(1), m.group(2)))
calls = [i for i, (op, arg) in enumerate(body) if op.startswith("invoke") and re.search(callee, arg)]
if not calls:
    print("BYTECODE %s%s: no invoke matching /%s/" % (name, desc, callee)); sys.exit(1)
if mode == "returns":
    rets = [i for i, (op, _) in enumerate(body) if op == "areturn"]
    bad = []
    for r in rets:
        j = r - 1
        while j >= 0 and body[j][0] == "checkcast":
            j -= 1
        if j < 0 or j not in calls:
            bad.append(r)
    if not rets or bad:
        print("BYTECODE %s%s: %d areturn, %d not directly after /%s/" % (name, desc, len(rets), len(bad), callee)); sys.exit(1)
    print("BYTECODE %s%s: returns the value of /%s/ (%d areturn)" % (name, desc, callee, len(rets)))
else:
    print("BYTECODE %s%s: invokes /%s/ (%d site(s))" % (name, desc, callee, len(calls)))
PY
    rc=$?
    rm -f "$dump"
    return $rc
}

# class_loaded <class-load log written by -Xlog:class+load=info:file=...> <binary class name>
#   exit 0 if the JVM loaded the class during the run
class_loaded() {
    grep -qE "\] $(printf '%s' "$2" | sed 's/\./\\./g') source: " "$1"
}

tree_clean() {
    [ -z "$(git status --porcelain --untracked-files=no)" ] && pass "working tree clean after the check" \
        || fail "tracked files changed by the check: $(git status --porcelain --untracked-files=no | head -3)"
}

no_ignored_tests() {
    if grep -rlE '@(Ignore|Disabled)' "$@" 2>/dev/null | grep -q .; then
        fail "@Ignore/@Disabled in $*"
    else
        pass "no @Ignore/@Disabled in $*"
    fi
}
