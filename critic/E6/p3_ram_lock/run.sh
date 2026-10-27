#!/usr/bin/env bash
# critic-E6 probe P3 (RAM rule, docs/ai/pipeline/ram_rule.txt):
#  (a) which E6 acceptance scripts start JVMs with a heap > 4 GB and whether they take the machine lock;
#  (b) a nested `flock <same file>` inside a command already run under `flock <file>` blocks (so a
#      lock built into scripts/cflidr/e6-probe.sh would deadlock when the verifier runs E6_e2e.sh /
#      S6_probe.sh under the machine lock, unless the inner lock is skipped when the outer one is held).
#      Uses a scratch lock file, not the machine lock.
# Usage: bash critic/E6/p3_ram_lock/run.sh [scratch-dir]
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
echo "(a) heap options and locks in acceptance/E6:"
grep -nE -- '-Xmx[0-9]+[gGmM]|XMX=|flock|heavy-run' "$ROOT"/acceptance/E6/*.sh | sed 's/^/    /'
echo "    scripts with 'flock': $(grep -l flock "$ROOT"/acceptance/E6/*.sh 2>/dev/null | wc -l)"
echo "    E6-S6.md contract lines with flock: $(grep -c flock /home/usatovpavel/edu/Diploma_work/docs/ai/tickets/E6-S6.md)"
T="${1:-$(mktemp -d)}"; mkdir -p "$T"; L="$T/probe.lock"
echo "(b) nested flock on $L:"
flock "$L" bash -c "flock -w 5 '$L' true; echo \"    inner flock -w 5 exit \$? (1 = could not take the lock held by the outer command)\""
flock "$L" bash -c "HEAVY_LOCK_HELD=1; if [ -n \"\${HEAVY_LOCK_HELD:-}\" ]; then echo '    guarded inner run: lock already held, run directly (exit 0)'; else flock '$L' true; fi"
