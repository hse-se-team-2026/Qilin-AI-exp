# Common helpers for E3 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Reuses the E2 helpers (acceptance/E2/lib.sh, unchanged) and moves the output directory to
# acceptance/E3/out. Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E3.md (in the Diploma_work docs, not in this repository).

source "$(dirname "${BASH_SOURCE[0]}")/../E2/lib.sh"

OUT="$ROOT/acceptance/E3/out"          # git-ignored
LOGS="$OUT/logs"
mkdir -p "$LOGS"

MICROBEN_CLASSES="$ROOT/qilin.microben/build/classes/java/main"

# xml_dir_of <module> -> directory with the JUnit XML results of <module>
xml_dir_of() {
    echo "$ROOT/$1/build/test-results/test"
}

# junit_cases <dir> <classname> -> "name status" per test case of <classname>
junit_cases() {
    python3 - "$1" "$2" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
d, cls = sys.argv[1:3]
for p in sorted(glob.glob(os.path.join(d, "TEST-*.xml"))):
    for tc in ET.parse(p).getroot().iter("testcase"):
        if tc.get("classname") == cls:
            st = "PASSED"
            if tc.find("failure") is not None or tc.find("error") is not None:
                st = "FAILED"
            elif tc.find("skipped") is not None:
                st = "SKIPPED"
            print(tc.get("name"), st)
PY
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

# kotlin_class_in_ucfs_jar <class path in jar>... : each class is compiled Kotlin in the qilin.ucfs jar
kotlin_class_in_ucfs_jar() {
    local j c
    j="$(ls qilin.ucfs/build/libs/qilin.ucfs-*.jar 2>/dev/null | head -n 1)"
    for c in "$@"; do
        [ -n "$j" ] && kotlin_metadata_class "$j" "$c" && pass "$c is compiled Kotlin in qilin.ucfs" \
            || fail "$c is not a Kotlin class of the qilin.ucfs jar"
    done
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
