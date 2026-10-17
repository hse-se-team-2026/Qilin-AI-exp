#!/usr/bin/env bash
# E1-S4 acceptance (B4): a FRESH clone of Qilin-AI-exp (committed HEAD only, no submodules,
# no .ucfs/) gets a working build with the commands documented in README.md, and nothing else.
#   1. Without bootstrap, the build either works or fails with a message that names
#      scripts/ucfs/bootstrap.sh (so nobody "fixes" it by deleting the UCFS dependency).
#   2. The README block between <!-- ucfs-bootstrap:begin --> and <!-- ucfs-bootstrap:end -->
#      is extracted and run verbatim (bash -e) in the clone. It must run scripts/ucfs/bootstrap.sh
#      and the UCFS smoke test.
#   3. bootstrap built UCFS at the pinned commit: the jar in .ucfs/m2 has
#      UCFS-Commit = ucfsCommit from gradle.properties and UCFS-Dirty: false.
#   4. The 3 smoke tests PASSED in the clone; a second bootstrap run also exits 0;
#      the clone stays clean (git status) and ~/.m2/repository/org/ucfs is not touched.
# UCFS sources come from ucfsGitUrl in gradle.properties (GitHub), or from $UCFS_SRC if set
# (a git URL or local path that contains the pinned commit; it is passed on to bootstrap.sh).
# Usage: [UCFS_SRC=<git url|path>] bash acceptance/E1/S4_fresh_clone.sh     (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

FRESH="$ROOT/acceptance/E1/out/fresh-clone"
LOGS="$ROOT/acceptance/E1/out/logs"; mkdir -p "$LOGS"
safe_reset_dir "$FRESH"
HEAD_SHA=$(git rev-parse HEAD)
git clone -q --no-local --no-checkout "$ROOT" "$FRESH" \
    && git -C "$FRESH" fetch -q "$ROOT" "$HEAD_SHA" \
    && git -C "$FRESH" checkout -q --detach "$HEAD_SHA" || die_env "cannot clone $ROOT@$HEAD_SHA"
echo "fresh clone of $HEAD_SHA in $FRESH (UCFS_SRC=${UCFS_SRC:-<ucfsGitUrl>})"
cd "$FRESH" || die_env "no $FRESH"
M2_BEFORE=$(m2_ucfs_snapshot)

# 1. no bootstrap yet
bash ./gradlew --console=plain :qilin.pta:compileTestJava > "$LOGS/fresh-no-bootstrap.log" 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    pass "fresh clone compiles tests without an explicit bootstrap"
elif grep -q 'scripts/ucfs/bootstrap.sh' "$LOGS/fresh-no-bootstrap.log"; then
    pass "fresh clone without bootstrap fails with a hint to scripts/ucfs/bootstrap.sh"
else
    fail "fresh clone without bootstrap fails (exit $rc) and the output does not mention scripts/ucfs/bootstrap.sh"
fi

# 2. the README block, verbatim
python3 - README.md > "$LOGS/fresh-readme-block.sh" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"<!--\s*ucfs-bootstrap:begin\s*-->(.*?)<!--\s*ucfs-bootstrap:end\s*-->", t, re.S)
if not m:
    sys.exit(1)
cmds, inside = [], False
for line in m.group(1).splitlines():
    if line.strip().startswith("```"):
        inside = not inside
        continue
    if inside and line.strip():
        cmds.append(re.sub(r"^\s*\$\s+", "", line))
print("\n".join(cmds))
sys.exit(0 if cmds else 1)
PY
if [ $? -ne 0 ]; then
    fail "README.md has no fenced command block between <!-- ucfs-bootstrap:begin --> and <!-- ucfs-bootstrap:end -->"
else
    echo "  README block:"; sed 's/^/    | /' "$LOGS/fresh-readme-block.sh"
    grep -q 'scripts/ucfs/bootstrap.sh' "$LOGS/fresh-readme-block.sh" && grep -q 'UcfsDependencySmokeTest' "$LOGS/fresh-readme-block.sh" \
        && pass "README block runs bootstrap.sh and the smoke test" || fail "README block must run scripts/ucfs/bootstrap.sh and UcfsDependencySmokeTest"
    bash -e "$LOGS/fresh-readme-block.sh" > "$LOGS/fresh-readme-run.log" 2>&1
    rc=$?
    tail -n 5 "$LOGS/fresh-readme-run.log"
    [ $rc -eq 0 ] && pass "README block exits 0 in the fresh clone" || fail "README block exit $rc (log: $LOGS/fresh-readme-run.log)"
fi

# 3. pinned commit
PIN=$(ucfs_prop ucfsCommit "$FRESH/gradle.properties")
JAR="$FRESH/.ucfs/m2/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.jar"
if [ -f "$JAR" ]; then
    mf=$(unzip -p "$JAR" META-INF/MANIFEST.MF | tr -d '\r')
    [ -n "$PIN" ] && echo "$mf" | grep -qx "UCFS-Commit: $PIN" && pass "bootstrapped solver has UCFS-Commit = ucfsCommit ($PIN)" \
        || fail "bootstrapped solver UCFS-Commit '$(echo "$mf" | sed -n 's/^UCFS-Commit: //p')' != ucfsCommit '$PIN'"
    echo "$mf" | grep -qx "UCFS-Dirty: false" && pass "bootstrapped solver UCFS-Dirty: false" \
        || fail "bootstrapped solver is not marked 'UCFS-Dirty: false'"
else
    fail "bootstrap did not publish $JAR"
fi

# 4. smoke tests, idempotence, cleanliness, ~/.m2
for t in solvesAnBnOnHandBuiltGraph solvesAnBnOnDotInput resolvedArtifactIsThePinnedVersion; do
    st=$(junit_case_status qilin.pta/build/test-results/test qilin.test.ucfs.UcfsDependencySmokeTest "$t")
    [ "$st" = PASSED ] && pass "fresh clone $t: $st" || fail "fresh clone $t: $st"
done
bash scripts/ucfs/bootstrap.sh > "$LOGS/fresh-bootstrap-again.log" 2>&1 && pass "second bootstrap run exits 0" \
    || fail "second bootstrap run fails (log: $LOGS/fresh-bootstrap-again.log)"
dirty=$(git status --porcelain)
[ -z "$dirty" ] && pass "fresh clone stays clean (bootstrap output is ignored)" || fail "fresh clone is dirty: $(echo $dirty)"
[ "$(m2_ucfs_snapshot)" = "$M2_BEFORE" ] && pass "~/.m2/repository/org/ucfs unchanged" \
    || fail "~/.m2/repository/org/ucfs changed (bootstrap must publish into .ucfs/m2 only, or another agent published concurrently)"

finish S4_fresh_clone
