#!/usr/bin/env bash
# E3 epic check: on the current tree (main after all E3 stories)
#  1. integrity: every E3 acceptance file and the E3 acceptance tests have the sha256 fixed when the
#     acceptance branch ai/E3-acceptance was written, and acceptance/E2/E2_e2e.sh is the E2 one
#     (it carries the hashes of the E1/E2 checks, the old tests, the wrapper, the reference jar and
#     bootstrap.sh). The hash of THIS file is in docs/ai/tickets/E3.md, so the epic verifier checks it
#     from outside the repository;
#  2. every E3 story check (S1..S5), each with its own log;
#  3. the E2 epic check acceptance/E2/E2_e2e.sh (which also runs the E1 regression) still passes.
#
# Preconditions (fresh clone): git submodule update --init qilin.microben &&
#   git submodule update --init --depth 1 artifact/benchmarks && bash scripts/ucfs/bootstrap.sh
# Usage: bash acceptance/E3/E3_e2e.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs

# --- 1. integrity --------------------------------------------------------------------------------
nbad=0; nok=0
while read -r h f; do
    [ -n "$f" ] || continue
    if [ -f "$f" ] && [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$h" ]; then
        nok=$((nok + 1))
    else
        fail "protected file changed or missing: $f"; nbad=$((nbad + 1))
    fi
done <<'SUMS'
a888b9df89402a815bdb15d30c5280b090be11655ab4cc2299ce748d44cd6ed4  acceptance/E3/.gitignore
28fa6e906395e79af7285be510ab92c42ecfa06eae81ef12fabe01b46477d8b4  acceptance/E3/lib.sh
df62721fb3b0195b1da70ae6c3f3f544518e053f77d0708c5f6fd9aad29de095  acceptance/E3/S1_pag_export.sh
da67ac2b80635fdd915ddfa5950e3afc5aa33e34f351457e641e53be6dcb7deb  acceptance/E3/S2_points_to_grammar.sh
07b5dfa2e5d043badb5d1ed6b0593c8c098fe2633379d247d1a346015202df83  acceptance/E3/S3_ucfs_pointsto.sh
8399296a79ef3ba86d82a9063bc1a695837a9eb4e903d614a5dca42c89e4420b  acceptance/E3/S4_cli_ucfspt.sh
fca853f8e74968d062b1de709def18865ac28774dc472867d697e1d07884ec8d  acceptance/E3/DotCheck.java
51a617e872b2efd485cbe16d70a1bc6e1b53ffbf0a6be61d674ba18eb0f847ae  acceptance/E3/S5_ucfs_doc.sh
938e46126350b49b48375154c7efbfde54d1fbb5e22d86d7fe5645e832a38de9  acceptance/E3/doc_check.py
75a8d10134ce30fff7f5bf424aad93a89a16db35e44c414d4cb8898a9b46c6d8  acceptance/E3/bib_keys.txt
61aed2a873cc8269b2420f59fcdf3718f4b084448b0d20b9a706905ffe860b4f  qilin.pta/test/qilin/test/ucfs/E3PagExportTest.java
2b72140239b52aa7467e249459b327e042d804da77c5f111fa5578b5b1b22f75  qilin.pta/test/qilin/test/ucfs/E3UcfsPointsToTest.java
b5526a6a706eab7d6a4a0ab188403f7f3432d7892f1411762df7b12d4d0a4ae8  qilin.ucfs/src/test/kotlin/qilin/ucfs/acceptance/E3GrammarTest.kt
0693c7ea41fa255954bf9828eccd2e45ddb323965801be61a203d0e81c1e167c  acceptance/E2/E2_e2e.sh
SUMS
[ $nbad -eq 0 ] && pass "$nok protected files have the fixed sha256"

# --- 2. story checks -----------------------------------------------------------------------------
for s in S1_pag_export S2_points_to_grammar S3_ucfs_pointsto S4_cli_ucfspt S5_ucfs_doc; do
    start=$(date +%s)
    bash "acceptance/E3/$s.sh" > "$LOGS/e2e-$s.log" 2>&1
    rc=$?
    echo "  $s: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-$s.log")"
    [ $rc -eq 0 ] && pass "$s" || { fail "$s (see $LOGS/e2e-$s.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-$s.log" | head -n 5; }
done

# --- 3. E2 (and E1) regression -------------------------------------------------------------------
start=$(date +%s)
bash acceptance/E2/E2_e2e.sh > "$LOGS/e2e-E2_e2e.log" 2>&1
rc=$?
echo "  E2_e2e: exit $rc, $(( $(date +%s) - start )) s, $(tail -n 1 "$LOGS/e2e-E2_e2e.log")"
[ $rc -eq 0 ] && pass "E2 regression (acceptance/E2/E2_e2e.sh)" || { fail "E2 regression (see $LOGS/e2e-E2_e2e.log)"; grep -E '^(FAIL|ENV):' "$LOGS/e2e-E2_e2e.log" | head -n 5; }

tree_clean
finish E3_e2e
