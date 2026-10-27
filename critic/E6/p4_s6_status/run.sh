#!/usr/bin/env bash
# critic-E6 probe P4: the runs/values checks of acceptance/E6/S6_probe.sh (sections 1, 3, 4; the python
# block is taken verbatim from the protected script at run time, the script itself is not changed) on
# synthetic e6-results: (A) statuses as the planner's matrix (E6.md D10); (B) the same with every
# non-ok status swapped (luindex/antlr "sof" -> "timeout", xalan CS "timeout" -> "error", pmd -> "sof").
# Expectation of a check that verifies the classification: (B) fails. Usage: bash run.sh <out-dir>
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"; OUT="$1"; mkdir -p "$OUT"
PY="$OUT/s6_block.py"
awk '/^python3 - "\$R" "\$MATRIX" <<.PY.$/{f=1; next} f && /^PY$/{exit} f' "$ROOT/acceptance/E6/S6_probe.sh" > "$PY"
MATRIX="$(sed -n 's/^MATRIX="\(.*\)"$/\1/p' "$ROOT/acceptance/E6/S6_probe.sh")"
mk() { # mk <dir> <status per run, 9 words in matrix order>
    local d="$1"; shift; mkdir -p "$d"
    printf 'bench\tmode\tgrammar\tstatus\texit\twall_s\tmax_rss_mb\n' > "$d/runs.tsv"
    printf 'bench\tmode\tgrammar\tkey\tvalue\n' > "$d/values.tsv"
    local i=0 st
    for m in $MATRIX; do
        i=$((i + 1)); st="${!i}"; IFS=: read -r b mo g <<< "$m"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$b" "$mo" "$g" "$st" 0 1.0 1 >> "$d/runs.tsv"
        for k in CFLIDR-vertices CFLIDR-edges; do printf '%s\t%s\t%s\t%s\t10\n' "$b" "$mo" "$g" "$k" >> "$d/values.tsv"; done
        if [ "$st" = ok ]; then
            for k in CFLIDR-pt-under CFLIDR-pt-over; do printf '%s\t%s\t%s\t%s\t5\n' "$b" "$mo" "$g" "$k" >> "$d/values.tsv"; done
        fi
    done
}
#            xE  xB  xBse xCS     pE      pB      pCS     lu      an
mk "$OUT/A" ok ok ok timeout timeout timeout timeout sof sof
mk "$OUT/B" ok ok ok error   sof     sof     sof     timeout timeout
for c in A B; do
    python3 -I "$PY" "$OUT/$c" "$MATRIX" > "$OUT/$c.log" 2>&1
    echo "$c: S6 runs/values block exit $? ($(grep -c '^PASS' "$OUT/$c.log") PASS, $(grep -c '^FAIL' "$OUT/$c.log") FAIL)"
done
