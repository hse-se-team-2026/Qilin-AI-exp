# Common helpers for E5 acceptance checks in Qilin-AI-exp (sourced, not executed).
# Reuses the E4 helpers (acceptance/E4/lib.sh, unchanged; it sources the E3 and E2 helpers) and moves
# the output directory to acceptance/E5/out (git-ignored by the root .gitignore rule "out/").
# Exit codes of checks: 0 = PASS, 1 = FAIL, 2 = precondition/environment problem.
# Plan and rationale: docs/ai/tickets/E5.md (in the Diploma_work docs, not in this repository).

source "$(dirname "${BASH_SOURCE[0]}")/../E4/lib.sh"

OUT="$ROOT/acceptance/E5/out"
LOGS="$OUT/logs"
mkdir -p "$LOGS"

E5PY="$ROOT/acceptance/E5/e5lib.py"
# The committed results of the full E4 run (git-head 557de3d, E4-S6): the answer of the same analyses
# made by the code before E5; E5 compares every non-measurement key with them.
E4_RESULTS="$ROOT/docs/ucfs-integration/e4-results"
# The six benchmarks whose D3 slice covers >= 50 % of the application methods (E4.md D14, table T5)
COVERED="antlr bloat chart fop luindex lusearch"
ALL_BENCHES="antlr bloat chart eclipse fop luindex lusearch pmd xalan checkstyle findbugs JPC"

# tracked_clean <label>: the check left the tracked files of the repository unchanged
tracked_clean() {
    if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
        pass "$1: tracked files unchanged"
    else
        fail "$1: tracked files changed: $(git status --porcelain --untracked-files=no | head -n 5 | tr '\n' ' ')"
    fi
}

# py <args...>: python3 with acceptance/E5 on PYTHONPATH (module e5lib)
py() {
    PYTHONPATH="$ROOT/acceptance/E5" python3 "$@"
}
