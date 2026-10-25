#!/usr/bin/env bash
# critic-E5 probe: runs the Python part of acceptance/E5/S5_results.sh (points 2 and 4-10; the heredoc is
# extracted unchanged from the committed file) on a fabricated results tree (critic/E5/fake_results.py).
# Point 1 (files) holds by construction, point 3 (git-head = HEAD) holds because the fake uses HEAD,
# point 9 uses the fake REPRO directory instead of a real e5-bench.sh run (no e5-bench.sh exists yet).
# Usage: bash critic/E5/s5_probe.sh [mutation ...]     -> prints the FAIL lines and RESULT
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
name="${*:-baseline}"; name="${name// /+}"
W="$ROOT/critic/E5/out/s5-$name"
rm -rf "$W"; mkdir -p "$W/RAW"
python3 critic/E5/fake_results.py "$W" "$@" > "$W/gen.txt" || { echo "generator failed"; exit 2; }
tar -xJf "$W/R/raw.tar.xz" -C "$W/RAW"
sed -n "/^py - \"\$R\" \"\$RAW\"/,/^PY$/p" acceptance/E5/S5_results.sh | sed '1d;$d' > "$W/s5.py"
PYTHONPATH="$ROOT/acceptance/E5" python3 "$W/s5.py" "$W/R" "$W/RAW" "$ROOT/docs/ucfs-integration/e4-results" "$W/REPRO" > "$W/s5.txt" 2>&1
rc=$?
cat "$W/gen.txt"
grep -c '^PASS' "$W/s5.txt" | sed 's/^/S5 python: PASS lines /'
grep '^FAIL' "$W/s5.txt"
echo "S5 python on fake results [$name]: exit $rc ($( [ $rc -eq 0 ] && echo PASS || echo FAIL ))"
