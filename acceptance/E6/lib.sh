# Common helpers for E6 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Reuses the E5 helpers (acceptance/E5/lib.sh, unchanged; it sources the E4, E3 and E2 helpers) and
# moves the output directory to acceptance/E6/out (git-ignored by the root .gitignore rule "out/").
# Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E6.md (in the Diploma_work docs, not in this repository).

source "$(dirname "${BASH_SOURCE[0]}")/../E5/lib.sh"

OUT="$ROOT/acceptance/E6/out"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

CFLIDR_PROPS="$ROOT/scripts/cflidr/cflidr.properties"
# The E6-S1 acceptance check of cfl-idr-with-gll-AI-exp (branch ai/E6-acceptance, commit A1c): the
# pinned cfl-idr commit must carry this file unchanged (E6.md, criterion 2).
CFLIDR_S1_SHA=b835cf6cc26cca1bbbfda2eedde47991f054ced462749e062c2daf89438b9b3b

# cflidr_prop <key> -> value from scripts/cflidr/cflidr.properties (empty if absent)
cflidr_prop() {
    [ -f "$CFLIDR_PROPS" ] && sed -n "s/^$1=//p" "$CFLIDR_PROPS" | tail -n 1 | tr -d '\r'
}

# manifest_attr <jar> <name> -> value of a jar manifest attribute (empty if absent)
manifest_attr() {
    unzip -p "$1" META-INF/MANIFEST.MF 2>/dev/null | tr -d '\r' | sed -n "s/^$2: //p"
}

# cflidr_jar -> path of the published cfl-idr-with-gll jar in .cflidr/m2
cflidr_jar() {
    local v
    v="$(cflidr_prop cflidrVersion)"
    echo "$ROOT/.cflidr/m2/org/cfl_idr_with_gll/cfl-idr-with-gll/$v/cfl-idr-with-gll-$v.jar"
}

need_cflidr() {
    [ -f "$(cflidr_jar)" ] || die_env "cfl-idr-with-gll is not in .cflidr/m2: run 'bash scripts/cflidr/bootstrap.sh'"
}
