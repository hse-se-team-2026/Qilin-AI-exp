# Common helpers for E1 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

: "${JAVA_HOME:=$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}"
export JAVA_HOME

# Coordinates fixed by the E1 plan (docs/ai/tickets/E1.md, "Решения").
UCFS_GROUP="org.ucfs"
UCFS_VERSION="0.1.0-ai-SNAPSHOT"

FAILS=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }
die_env() { echo "ENV: $*"; exit 2; }

gradle() {
    bash ./gradlew --console=plain "$@"
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

# junit_case_status <dir> <classname> <testname-prefix> -> PASSED | SKIPPED | FAILED | MISSING
junit_case_status() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys, glob, os
import xml.etree.ElementTree as ET
d, cls, name = sys.argv[1:4]
status = "MISSING"
for p in glob.glob(os.path.join(d, "TEST-*.xml")):
    for tc in ET.parse(p).getroot().iter("testcase"):
        if tc.get("classname") == cls and tc.get("name", "").startswith(name):
            if tc.find("failure") is not None or tc.find("error") is not None:
                status = "FAILED"
            elif tc.find("skipped") is not None:
                status = "SKIPPED"
            else:
                status = "PASSED"
print(status)
PY
}

finish() {
    if [ "$FAILS" -eq 0 ]; then
        echo "RESULT: PASS ($1)"
        exit 0
    fi
    echo "RESULT: FAIL ($1): $FAILS check(s) failed"
    exit 1
}
