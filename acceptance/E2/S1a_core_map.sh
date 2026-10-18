#!/usr/bin/env bash
# E2-S1a acceptance: the map of the Qilin core docs/ucfs-integration/qilin-core-map.md,
# map, first half: PAG (internal and global), solver, kernel (Ядро, layers 3-4); 27 anchors.
# The map is committed, every code reference `path:N#symbol` is real at the pinned commit, every
# line with references carries a role in prose, every mandatory anchor has its own table row with
# a role and points at the declaration (not a call site). Details: acceptance/E2/core_map_check.py.
# Also writes acceptance/E2/out/S1a-excerpts.md (pinned code of every reference) and prints the
# reproducible judgment sample for the verifier (docs/ai/tickets/E2-S1a.md).
#
# Usage: [MAP=<path>] bash acceptance/E2/S1a_core_map.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

MAP="${MAP:-docs/ucfs-integration/qilin-core-map.md}"

[ -f "$MAP" ] || { fail "$MAP does not exist"; finish S1a_core_map; }
git ls-files --error-unmatch "$MAP" >/dev/null 2>&1 && git diff --quiet HEAD -- "$MAP" \
    && pass "$MAP is committed (no uncommitted edits)" || fail "$MAP is not committed or has uncommitted edits"

python3 "$ROOT/acceptance/E2/core_map_check.py" a "$MAP" "$OUT/S1a-excerpts.md" || FAILS=$((FAILS + 1))

finish S1a_core_map
