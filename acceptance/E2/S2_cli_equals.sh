#!/usr/bin/env bash
# E2-S2 acceptance: the Qilin CLI built from this tree accepts `-<opt>=<value>` again, as
# artifact/run.py and artifact/qilin.py pass it (`-pta=E-2o`, `-cga=QILIN`, `-cda=CONCH`, ...).
# Since 91d6d97 (commons-cli DefaultParser) `-pta=insens` exits 1 with
# "UnrecognizedOptionException: Unrecognized option: -pta=insens"; the space form `-pta insens`
# still works.
#
# "As before" means "as the committed prebuilt jar artifact/Qilin-0.9.9-SNAPSHOT.jar" (built
# before 91d6d97 with GnuParser): it is the oracle, run with the `=` form. That jar also accepts
# the short name with two dashes (`--pta=insens`, `--pta insens`), so the fresh jar must as well.
# On base 73db8b4 the fresh fatJar with the space form `-pta insens` prints exactly the same '#'
# statistics as that jar for the single-dash configurations below (checked by the planner,
# docs/ai/tickets/E2.md). Here the fresh fatJar must print the same statistics with BOTH forms.
# The run.py path is checked through artifact/qilin.py (runPointsToAnalysis) on a copy of
# artifact/{qilin.py,util} next to the fresh jar, so no tracked file is touched.
#
# Needs submodule artifact/benchmarks (JRE model) and `bash scripts/ucfs/bootstrap.sh`.
# Usage: bash acceptance/E2/S2_cli_equals.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

FRESH="$OUT/qilin-fat.jar"
build_fatjar "$FRESH"
rc=$?
echo "gradle build -x test; gradle fatJar -x test: exit code $rc (log: $LOGS/fatjar.log)"
[ $rc -eq 0 ] && [ -f "$FRESH" ] && pass "fatJar builds" || { fail "fatJar build (exit $rc)"; finish S2_cli_equals; }
git diff --quiet HEAD -- "$COMMITTED_JAR" && pass "committed artifact jar unchanged" || fail "committed artifact jar was modified"

# name | arguments in the `=` form (the space form is derived by replacing the first '=')
CONFIGS=(
    "insens|-pta=insens -se"
    "2o|-pta=2o -se -clinit=APP"
    "E-2o|-pta=E-2o -se -clinit=ONFLY -cga=QILIN"
    "T-2o-p1|-pta=T-2o -se -tc=PHASE_ONE"
    "s-1c|-pta=s-1c -se"
    "2o-conch|-pta=2o -se -cd -cda=CONCH"
    "insens-dd|--pta=insens -se"
)

for c in "${CONFIGS[@]}"; do
    name="${c%%|*}"
    read -r -a eq_args <<<"${c#*|}"
    sp_args=()
    for a in "${eq_args[@]}"; do
        if [[ "$a" =~ ^(--?[a-z]+)=(.*)$ ]]; then sp_args+=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"); else sp_args+=("$a"); fi
    done
    run_qilin "$COMMITTED_JAR" "$name-ref" "${eq_args[@]}"; rrc=$?
    run_qilin "$FRESH" "$name-eq" "${eq_args[@]}"; erc=$?
    run_qilin "$FRESH" "$name-space" "${sp_args[@]}"; src=$?
    ref="$OUT/run-$name-ref/metrics.txt"
    if [ $rrc -ne 0 ] || [ ! -s "$ref" ]; then
        die_env "reference run of the committed jar failed for '${eq_args[*]}' (exit $rrc, $OUT/run-$name-ref/out.txt)"
    fi
    if [ $erc -eq 0 ] && cmp -s "$ref" "$OUT/run-$name-eq/metrics.txt"; then
        pass "$name: '${eq_args[*]}' exit 0, statistics = reference ($(wc -l < "$ref") lines)"
    else
        fail "$name: '${eq_args[*]}' exit $erc; statistics differ from reference (see $OUT/run-$name-eq/out.txt)"
        grep -m2 -E 'Exception|Unrecognized' "$OUT/run-$name-eq/out.txt"
    fi
    if [ $src -eq 0 ] && cmp -s "$ref" "$OUT/run-$name-space/metrics.txt"; then
        pass "$name: space form '${sp_args[*]}' still works"
    else
        fail "$name: space form '${sp_args[*]}' exit $src or statistics differ from reference"
    fi
done

# run.py path: artifact/qilin.py next to the fresh jar (copy), JRE through a symlink.
PYHOME="$OUT/pyhome"
safe_reset_dir "$PYHOME"
cp artifact/qilin.py "$PYHOME/" && cp -r artifact/util "$PYHOME/" && cp "$FRESH" "$PYHOME/Qilin-0.9.9-SNAPSHOT.jar" \
    && ln -s "$ROOT/artifact/benchmarks" "$PYHOME/benchmarks" || die_env "cannot prepare $PYHOME"
RUN="$OUT/run-qilinpy"
safe_reset_dir "$RUN"
(cd "$RUN" && PATH="$JAVA_HOME/bin:$PATH" PYTHONPATH="$PYHOME" timeout 300 python3 -c \
    'import qilin, sys; qilin.runPointsToAnalysis(sys.argv[1:])' \
    -Xmx2g -timeout=300 -apppath "$EXAMPLE_JAR" -mainclass Main -pta=E-2o -se -clinit=ONFLY -cga=QILIN \
    -jre=jre1.6.0_45 > out.txt 2>&1)
prc=$?
grep '^#' "$RUN/out.txt" > "$RUN/metrics.txt"
if [ $prc -eq 0 ] && cmp -s "$OUT/run-E-2o-ref/metrics.txt" "$RUN/metrics.txt"; then
    pass "artifact/qilin.py runPointsToAnalysis with the fresh jar: statistics = reference"
else
    fail "artifact/qilin.py runPointsToAnalysis with the fresh jar: exit $prc, statistics differ (see $RUN/out.txt)"
fi

git diff --quiet HEAD -- "$COMMITTED_JAR" && [ -z "$(git status --porcelain --untracked-files=no)" ] \
    && pass "working tree clean after the check" || fail "tracked files changed by the check: $(git status --porcelain --untracked-files=no | head -3)"

finish S2_cli_equals
