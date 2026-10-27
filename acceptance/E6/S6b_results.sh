#!/usr/bin/env bash
# E6-S6b acceptance: the committed run of the matrix of E6.md D10 with scripts/cflidr/e6-probe.sh (E6-S6a) -
# docs/ucfs-integration/e6-results/{meta,runs,values,evidence}.tsv and raw.tar.xz (docs/ai/tickets/E6-S6b.md;
# decision of the lead 5, 6 after critic-E6 and Codex). Heavy (xalan with -Xmx16g): under the machine lock
# (heavy_lock of lib.sh) unless HEAVY_LOCK_HELD=1.
#  1. the five result files exist; runs.tsv has the header "bench mode grammar timeout_s status exit wall_s
#     max_rss_mb last_phase" and exactly the runs of MATRIX in this order with their timeouts; status in
#     {ok, timeout, oom, sof, error}; ok <=> values.tsv has CFLIDR-pt-over for the run; numbers are numbers;
#  2. the rows come from the raw files: raw.tar.xz holds <bench>/<mode>-<grammar>/{cmd.txt,out.txt,time.txt,
#     exit,timeout} of every run, and runs.tsv, values.tsv, evidence.tsv are byte-equal to the ones
#     acceptance/E6/e6raw.py derives from them (sha256 of out.txt and cmd.txt included); every cmd.txt runs
#     the fat jar with -Xmx16g, -pta=insens, -cflidr=<grammar> -cflidrmode=<mode> and no -cflidrstack;
#  3. meta.tsv: git-head is a commit of this repository, an ancestor of HEAD, and the code is that of HEAD
#     (qilin.pta/src qilin.core/src qilin.ucfs/src qilin.util/src scripts/cflidr); tree-clean yes;
#     cflidr-commit = cflidrCommit, ucfs-commit = ucfsCommit; timeout-s 600; xmx 16g; stack default;
#     extra-opts -; heavy-lock, java-version, cpu-model, mem-total-mb, load1-start, load1-end present;
#  4. floor of feasibility (measured before the run): xalan ERASED parity and xalan BALANCED parity are ok;
#  5. every ok run: pt-under <= pt-over, vertices > 0, edges > 0; ERASED: pt-under = pt-over; per benchmark
#     with both ok, pt-over of BALANCED <= pt-over of ERASED;
#  6. every run that is not ok: the error_line of evidence.tsv fits the status (sof: StackOverflowError,
#     oom: OutOfMemoryError, timeout: exit 124 or 137), and the run printed its graph size (#CFLIDR-vertices,
#     -edges, -sites, -fields: printed before the solve);
#  7. reproduction with the fat jar of HEAD: `e6-probe.sh <tmp> xalan:ERASED:parity` is ok and every #CFLIDR-
#     key except *-ms and CFLIDR-stack equals the committed value.
# Usage: bash acceptance/E6/S6b_results.sh          (exit 0 = PASS; ~6 min)
source "$(dirname "$0")/lib.sh"
# missing results fail at once, without waiting for the lock
for f in meta.tsv runs.tsv values.tsv evidence.tsv raw.tar.xz; do
    [ -f "$ROOT/docs/ucfs-integration/e6-results/$f" ] || { fail "no $ROOT/docs/ucfs-integration/e6-results/$f"; finish S6b_results; }
done
heavy_lock "$@"
need_submodules
need_ucfs
need_cflidr
R="$ROOT/docs/ucfs-integration/e6-results"
P="$ROOT/scripts/cflidr/e6-probe.sh"
MATRIX="xalan:ERASED:parity:600 xalan:BALANCED:parity:600 xalan:BALANCED:se:600 xalan:CS:parity:3600 pmd:ERASED:parity:600 pmd:BALANCED:parity:600 pmd:CS:parity:600 luindex:BALANCED:parity:600 antlr:BALANCED:parity:600"

for f in meta.tsv runs.tsv values.tsv evidence.tsv raw.tar.xz; do
    [ -f "$R/$f" ] || { fail "no $R/$f"; finish S6b_results; }
done
pass "result files exist"
[ -f "$P" ] || { fail "no scripts/cflidr/e6-probe.sh"; finish S6b_results; }

# --- 2. derived from the raw files ------------------------------------------------------------------
RAW="$OUT/results-raw"
rm -rf "$RAW" "$OUT/results-derived"
mkdir -p "$RAW" && tar -xJf "$R/raw.tar.xz" -C "$RAW" 2> "$LOGS/raw.log" && pass "raw.tar.xz unpacks" || fail "raw.tar.xz (log: $LOGS/raw.log)"
# shellcheck disable=SC2086
python3 acceptance/E6/e6raw.py "$RAW" "$OUT/results-derived" $MATRIX > "$LOGS/e6raw.log" 2>&1 || fail "e6raw.py on raw.tar.xz (log: $LOGS/e6raw.log)"
for f in runs.tsv values.tsv evidence.tsv; do
    cmp -s "$R/$f" "$OUT/results-derived/$f" && pass "$f = derived from raw.tar.xz" || fail "$f differs from the one derived from raw.tar.xz"
done

# --- 1, 2, 4, 5, 6: rows ------------------------------------------------------------------------------
python3 - "$R" "$RAW" "$MATRIX" <<'PY'
import os, re, sys
r, raw, matrix = sys.argv[1], sys.argv[2], sys.argv[3].split()
ok = True
def check(c, msg):
    global ok
    print(("PASS: " if c else "FAIL: ") + msg)
    ok &= bool(c)
runs = [l.split("\t") for l in open(os.path.join(r, "runs.tsv")).read().strip().split("\n")]
check(runs[0] == ["bench", "mode", "grammar", "timeout_s", "status", "exit", "wall_s", "max_rss_mb", "last_phase"], "runs.tsv header")
check([":".join(x[:4]) for x in runs[1:]] == matrix, "runs.tsv = the matrix with its timeouts, in order (%d runs)" % len(matrix))
vals = {}
for l in open(os.path.join(r, "values.tsv")).read().strip().split("\n")[1:]:
    b, m, g, k, v = l.split("\t")
    vals[(b, m, g, k)] = v
ev = {(x[0], x[1], x[2]): x for x in (l.split("\t") for l in open(os.path.join(r, "evidence.tsv")).read().strip().split("\n")[1:])}
def num(s):
    try:
        float(s); return True
    except ValueError:
        return False
okrows = {}
for x in runs[1:]:
    key, name, st = tuple(x[:3]), ":".join(x[:3]), x[4]
    check(st in ("ok", "timeout", "oom", "sof", "error"), "%s status %s" % (name, st))
    check(num(x[6]) and num(x[7]), "%s wall_s/max_rss_mb are numbers" % name)
    check((st == "ok") == ((key + ("CFLIDR-pt-over",)) in vals), "%s ok <=> CFLIDR-pt-over printed" % name)
    cmd = open(os.path.join(raw, x[0], "%s-%s" % (x[1], x[2]), "cmd.txt")).read().split()
    check("-Xmx16g" in cmd and "-pta=insens" in cmd and "-cflidr=" + x[2] in cmd and "-cflidrmode=" + x[1] in cmd
          and not any(c.startswith("-cflidrstack") for c in cmd), "%s cmd.txt: -Xmx16g -pta=insens -cflidr -cflidrmode, default stack" % name)
    g = lambda k: int(vals.get(key + (k,), "-1"))
    if st == "ok":
        okrows[key] = g("CFLIDR-pt-over")
        check(g("CFLIDR-vertices") > 0 and g("CFLIDR-edges") > 0, "%s vertices, edges > 0" % name)
        check(0 <= g("CFLIDR-pt-under") <= g("CFLIDR-pt-over"), "%s pt-under <= pt-over" % name)
        if key[1] == "ERASED":
            check(g("CFLIDR-pt-under") == g("CFLIDR-pt-over"), "%s ERASED is exact: pt-under = pt-over" % name)
    else:
        e = ev.get(key, [""] * 9)
        fit = {"sof": "StackOverflowError" in e[5], "oom": "OutOfMemoryError" in e[5],
               "timeout": x[5] in ("124", "137"), "error": True}[st] if st in ("sof", "oom", "timeout", "error") else False
        check(fit, "%s %s: evidence error_line '%s', exit %s" % (name, st, e[5], x[5]))
        check(all(g(k) >= 0 for k in ("CFLIDR-vertices", "CFLIDR-edges", "CFLIDR-sites", "CFLIDR-fields")) or st == "timeout" and g("CFLIDR-vertices") < 0,
              "%s: graph size printed before the solve (or a timeout before the export)" % name)
for b in sorted({k[0] for k in okrows}):
    e, bl = okrows.get((b, "ERASED", "parity")), okrows.get((b, "BALANCED", "parity"))
    if e is not None and bl is not None:
        check(bl <= e, "%s: pt-over BALANCED %d <= ERASED %d" % (b, bl, e))
for need in [("xalan", "ERASED", "parity"), ("xalan", "BALANCED", "parity")]:
    check(need in okrows, "feasibility floor: %s ok" % ":".join(need))
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] || FAILS=$((FAILS + 1))

# --- 3: meta --------------------------------------------------------------------------------------
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
[ "$(meta timeout-s)" = 600 ] && [ "$(meta xmx)" = 16g ] && [ "$(meta stack)" = default ] && [ "$(meta extra-opts)" = - ] \
    && pass "timeout-s 600, xmx 16g, stack default, extra-opts -" \
    || fail "timeout-s '$(meta timeout-s)' xmx '$(meta xmx)' stack '$(meta stack)' extra-opts '$(meta extra-opts)'"
for k in heavy-lock java-version cpu-model mem-total-mb load1-start load1-end command; do
    [ -n "$(meta $k)" ] && pass "meta $k" || fail "meta.tsv has no $k"
done

# --- 7: reproduction on xalan ---------------------------------------------------------------------
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
        if (b, m, g) == ("xalan", "ERASED", "parity") and not k.endswith("-ms") and k != "CFLIDR-stack":
            out[k] = v
    return out
st = [l.split("\t") for l in open(os.path.join(t, "runs.tsv")).read().strip().split("\n")[1:]]
ok = bool(st) and st[0][4] == "ok"
print(("PASS: " if ok else "FAIL: ") + "repro xalan:ERASED:parity status %s" % (st[0][4] if st else "none"))
a, b = load(t), load(r)
same = ok and a == b and len(a) > 0
print(("PASS: " if same else "FAIL: ") + "repro: %d non-time keys equal to the committed ones %s"
      % (len(a), sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))[:5]))
sys.exit(0 if ok and same else 1)
PY
    [ $? -eq 0 ] || FAILS=$((FAILS + 1))
else
    fail "fat jar build"
fi
tree_clean
finish S6b_results
