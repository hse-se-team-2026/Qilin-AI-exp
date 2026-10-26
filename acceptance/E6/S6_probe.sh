#!/usr/bin/env bash
# E6-S6 acceptance: the feasibility probe of cfl-idr on DaCapo-2006 slices (configuration D3 of E4: JDK
# bodies excluded, options of artifact/run.py) - scripts/cflidr/e6-probe.sh and its committed results
# docs/ucfs-integration/e6-results/{meta,runs,values}.tsv (docs/ai/tickets/E6-S6.md; E6.md D10).
#  1. the script exists; the results exist; runs.tsv has the header
#     "bench mode grammar status exit wall_s max_rss_mb" and exactly the runs of MATRIX (the default
#     matrix of the script, fixed in E6.md D10 before the run); status in {ok, timeout, oom, sof, error};
#     ok <=> values.tsv has CFLIDR-pt-over for the run; wall_s, max_rss_mb are numbers;
#  2. meta.tsv: git-head is a commit of this repository, an ancestor of HEAD, and the code is that of HEAD
#     (git diff git-head HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/cflidr
#     is empty); tree-clean yes; cflidr-commit = cflidrCommit, ucfs-commit = ucfsCommit; timeout-s 600;
#     xmx 16g; java-version, cpu-model, mem-total-mb present;
#  3. floor of feasibility (measured by the planner before the run): xalan ERASED parity and xalan
#     BALANCED parity are ok;
#  4. every ok run: pt-under <= pt-over, vertices > 0, edges > 0; ERASED: pt-under = pt-over (exact);
#  5. reproduction with the fat jar of HEAD: `e6-probe.sh <tmp> xalan:ERASED:parity` is ok, every
#     #CFLIDR- key except *-ms equals the committed value, and the independent Dyck solver
#     acceptance/E6/IdrDyckCheck.java on its dump agrees with pts-under.tsv and pts-over.tsv;
#  6. status classification: TIMEOUT=5 on xalan:CS:parity gives timeout; XMX=64m on
#     xalan:ERASED:parity gives oom.
# Usage: bash acceptance/E6/S6_probe.sh          (exit 0 = PASS; ~10 min)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
need_cflidr
R="$ROOT/docs/ucfs-integration/e6-results"
P="$ROOT/scripts/cflidr/e6-probe.sh"
MATRIX="xalan:ERASED:parity xalan:BALANCED:parity xalan:BALANCED:se xalan:CS:parity pmd:ERASED:parity pmd:BALANCED:parity pmd:CS:parity luindex:BALANCED:parity antlr:BALANCED:parity"

[ -f "$P" ] && bash -n "$P" && pass "scripts/cflidr/e6-probe.sh exists" || { fail "no scripts/cflidr/e6-probe.sh"; finish S6_probe; }
for f in meta.tsv runs.tsv values.tsv; do
    [ -f "$R/$f" ] || { fail "no $R/$f"; finish S6_probe; }
done
pass "results exist"

# --- 1, 3, 4: runs and values ---------------------------------------------------------------------
python3 - "$R" "$MATRIX" <<'PY'
import os, sys
r, matrix = sys.argv[1], sys.argv[2].split()
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + msg)
    ok &= bool(c)
runs = [l.split("\t") for l in open(os.path.join(r, "runs.tsv")).read().strip().split("\n")]
check(runs[0] == ["bench", "mode", "grammar", "status", "exit", "wall_s", "max_rss_mb"], "runs.tsv header")
rows = {(x[0], x[1], x[2]): x for x in runs[1:]}
want = {tuple(m.split(":")) for m in matrix}
check(set(rows) == want and len(runs) - 1 == len(want), "runs.tsv = the matrix (%d runs)" % len(want))
vals = {}
for l in open(os.path.join(r, "values.tsv")).read().strip().split("\n")[1:]:
    b, m, g, k, v = l.split("\t")
    vals[(b, m, g, k)] = v
def num(s):
    try:
        float(s); return True
    except ValueError:
        return False
for key, x in sorted(rows.items()):
    name = ":".join(key)
    st = x[3]
    check(st in ("ok", "timeout", "oom", "sof", "error"), "%s status %s" % (name, st))
    check(num(x[5]) and num(x[6]), "%s wall_s/max_rss_mb are numbers" % name)
    check((st == "ok") == ((key + ("CFLIDR-pt-over",)) in vals), "%s ok <=> CFLIDR-pt-over printed" % name)
    if st == "ok":
        g = lambda k: int(vals.get(key + (k,), "-1"))
        check(g("CFLIDR-vertices") > 0 and g("CFLIDR-edges") > 0, "%s vertices, edges > 0" % name)
        check(0 <= g("CFLIDR-pt-under") <= g("CFLIDR-pt-over"), "%s pt-under <= pt-over" % name)
        if key[1] == "ERASED":
            check(g("CFLIDR-pt-under") == g("CFLIDR-pt-over"), "%s ERASED is exact: pt-under = pt-over" % name)
for need in [("xalan", "ERASED", "parity"), ("xalan", "BALANCED", "parity")]:
    check(rows.get(need, [""] * 4)[3] == "ok", "feasibility floor: %s ok" % ":".join(need))
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))

# --- 2: meta --------------------------------------------------------------------------------------
meta() { awk -F'\t' -v k="$1" '$1 == k {print $2}' "$R/meta.tsv"; }
GH="$(meta git-head)"
if git cat-file -e "$GH^{commit}" 2>/dev/null; then
    git merge-base --is-ancestor "$GH" HEAD && pass "git-head $GH is an ancestor of HEAD" || fail "git-head $GH is not an ancestor of HEAD"
    git diff --quiet "$GH" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/cflidr \
        && pass "code at git-head = code at HEAD" \
        || fail "code changed since the probe: $(git diff --name-only "$GH" HEAD -- qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/cflidr | head -n 5 | tr '\n' ' ')"
else
    fail "git-head '$GH' is not a commit of this repository"
fi
[ "$(meta tree-clean)" = yes ] && pass "tree-clean yes" || fail "tree-clean '$(meta tree-clean)'"
[ "$(meta cflidr-commit)" = "$(cflidr_prop cflidrCommit)" ] && pass "cflidr-commit = cflidrCommit" || fail "cflidr-commit '$(meta cflidr-commit)'"
[ "$(meta ucfs-commit)" = "$(sed -n 's/^ucfsCommit=//p' gradle.properties | tr -d '\r')" ] && pass "ucfs-commit = ucfsCommit" || fail "ucfs-commit '$(meta ucfs-commit)'"
[ "$(meta timeout-s)" = 600 ] && [ "$(meta xmx)" = 16g ] && pass "timeout-s 600, xmx 16g" || fail "timeout-s '$(meta timeout-s)' xmx '$(meta xmx)'"
for k in java-version cpu-model mem-total-mb command; do
    [ -n "$(meta $k)" ] && pass "meta $k" || fail "meta.tsv has no $k"
done

# --- 5: reproduction on xalan ---------------------------------------------------------------------
FRESH="$OUT/qilin-fat.jar"
if fresh_fatjar "$FRESH"; then
    T="$OUT/repro"
    rm -rf "$T"
    JAR="$FRESH" bash "$P" "$T" xalan:ERASED:parity > "$LOGS/repro.log" 2>&1
    python3 - "$T" "$R" <<'PY'
import os, sys
t, r = sys.argv[1:3]
def load(d):
    out = {}
    for l in open(os.path.join(d, "values.tsv")).read().strip().split("\n")[1:]:
        b, m, g, k, v = l.split("\t")
        if (b, m, g) == ("xalan", "ERASED", "parity") and not k.endswith("-ms"):
            out[k] = v
    return out
st = [l.split("\t") for l in open(os.path.join(t, "runs.tsv")).read().strip().split("\n")[1:]]
ok = st and st[0][3] == "ok"
print(("PASS: " if ok else "FAIL: ") + "repro xalan:ERASED:parity status %s" % (st[0][3] if st else "none"))
a, b = load(t), load(r)
same = ok and a == b and len(a) > 0
print(("PASS: " if same else "FAIL: ") + "repro: %d non-time keys equal to the committed ones %s"
      % (len(a), sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))[:5]))
sys.exit(0 if ok and same else 1)
PY
    [ $? -eq 0 ] || FAILS=$((FAILS + 1))
    DUMP="$(find "$T" -type d -path '*cflidr' | head -n 1)"
    if [ -n "$DUMP" ]; then
        "$JAVA" -Xmx8g acceptance/E6/IdrDyckCheck.java "$DUMP" > "$LOGS/dyck.log" 2>&1
        rc=$?
        sed 's/^/  /' "$LOGS/dyck.log"
        [ $rc -eq 0 ] && pass "IdrDyckCheck: the FIELDS answer of xalan = independent Dyck reachability" || fail "IdrDyckCheck exit $rc"
    else
        fail "no cflidr dump in $T"
    fi
    # --- 6: classification ------------------------------------------------------------------------
    rm -rf "$OUT/to" "$OUT/oom"
    TIMEOUT=5 JAR="$FRESH" bash "$P" "$OUT/to" xalan:CS:parity > "$LOGS/to.log" 2>&1
    [ "$(awk -F'\t' 'NR == 2 {print $4}' "$OUT/to/runs.tsv" 2>/dev/null)" = timeout ] && pass "TIMEOUT=5 gives status timeout" \
        || fail "TIMEOUT=5: status '$(awk -F'\t' 'NR == 2 {print $4}' "$OUT/to/runs.tsv" 2>/dev/null)'"
    XMX=64m JAR="$FRESH" bash "$P" "$OUT/oom" xalan:ERASED:parity > "$LOGS/oom.log" 2>&1
    [ "$(awk -F'\t' 'NR == 2 {print $4}' "$OUT/oom/runs.tsv" 2>/dev/null)" = oom ] && pass "XMX=64m gives status oom" \
        || fail "XMX=64m: status '$(awk -F'\t' 'NR == 2 {print $4}' "$OUT/oom/runs.tsv" 2>/dev/null)'"
else
    fail "fat jar build"
fi
tree_clean
finish S6_probe
