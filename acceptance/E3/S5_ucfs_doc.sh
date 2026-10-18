#!/usr/bin/env bash
# E3-S5 acceptance (mechanical part of a judgment story): the document
# docs/ucfs-integration/ucfs-pointsto.md explains the export, the points-to grammar, why the GLL of
# UCFS works on different grammars (with references into UCFS and Qilin code at pinned commits and
# bib keys of docs/ai/articles_pdf/references.bib), the multi-grammar evidence and the
# discrepancies with Spark. Checks: committed, references valid at the pins, mandatory anchors are
# declarations in their own table rows, headings, mandatory mentions, bib keys, claim sweep
# (details: acceptance/E3/doc_check.py). Writes acceptance/E3/out/S5-excerpts.md (pinned code of every
# reference) and prints the reproducible judgment sample for the verifier (docs/ai/tickets/E3-S5.md).
#
# Usage: [DOC=<path>] bash acceptance/E3/S5_ucfs_doc.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"
need_ucfs
[ -d .ucfs/src/.git ] || die_env "UCFS clone .ucfs/src missing: run 'bash scripts/ucfs/bootstrap.sh'"

DOC="${DOC:-docs/ucfs-integration/ucfs-pointsto.md}"
[ -f "$DOC" ] || { fail "$DOC does not exist"; finish S5_ucfs_doc; }
git ls-files --error-unmatch "$DOC" >/dev/null 2>&1 && git diff --quiet HEAD -- "$DOC" \
    && pass "$DOC is committed (no uncommitted edits)" || fail "$DOC is not committed or has uncommitted edits"

python3 "$ROOT/acceptance/E3/doc_check.py" "$DOC" "$OUT/S5-excerpts.md" || FAILS=$((FAILS + 1))

finish S5_ucfs_doc
