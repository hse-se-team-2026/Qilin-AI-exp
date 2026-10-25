#!/usr/bin/env bash
# critic-E5 control for s5_probe.sh: the harness is sensitive. Same fake tree, then one TSV cell edited
# (planner's M5a: wall_s of one row of bench/runs.tsv) -> the S5 Python part must FAIL.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
W="$ROOT/critic/E5/out/s5-control"
rm -rf "$W"; mkdir -p "$W/RAW"
python3 critic/E5/fake_results.py "$W" > /dev/null
tar -xJf "$W/R/raw.tar.xz" -C "$W/RAW"
awk -F'\t' 'BEGIN{OFS="\t"} NR==2{$6=sprintf("%.2f",$6*0.5)} {print}' "$W/R/bench/runs.tsv" > "$W/runs.tsv" && mv "$W/runs.tsv" "$W/R/bench/runs.tsv"
sed -n "/^py - \"\$R\" \"\$RAW\"/,/^PY$/p" acceptance/E5/S5_results.sh | sed '1d;$d' > "$W/s5.py"
PYTHONPATH="$ROOT/acceptance/E5" python3 "$W/s5.py" "$W/R" "$W/RAW" "$ROOT/docs/ucfs-integration/e4-results" "$W/REPRO" > "$W/s5.txt" 2>&1
rc=$?
grep '^FAIL' "$W/s5.txt"
echo "S5 python on fake results with one edited wall_s: exit $rc"
