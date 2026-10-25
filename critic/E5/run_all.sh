#!/usr/bin/env bash
# critic-E5: reproduces every synthetic probe of the critic report (no Qilin run, ~1 min).
#   bash critic/E5/run_all.sh  -> critic/E5/{s5_mutants,s1_s2_probe,doc_pool_density,doc_probe,estimate,mutant_tables}.txt
set -u
cd "$(dirname "$0")/../.."
{
  for m in "" flavor localasvm cmdflags javaopts overlap kill137 inconsistent kernel minheap secret load; do
    echo "=== ${m:-baseline}"; bash critic/E5/s5_probe.sh $m | grep -v '^written'
  done
  echo "=== control (one wall_s edited in bench/runs.tsv)"; bash critic/E5/s5_control.sh
} > critic/E5/s5_mutants.txt 2>&1
python3 critic/E5/s1_s2_probe.py > critic/E5/s1_s2_probe.txt 2>&1
python3 critic/E5/doc_pool_density.py critic/E5/out/s5-baseline/R 200 > critic/E5/doc_pool_density.txt 2>&1
python3 critic/E5/doc_probe.py critic/E5/out/s5-baseline/R critic/E5/out/doc > critic/E5/doc_probe.txt 2>&1
awk -F'\t' 'NR>1 && ($2=="insens"||$2~/^ucfs/) && !(($1=="antlr"||$1=="bloat"||$1=="checkstyle") && $2=="ucfs-CALL_GRAPH"){s+=$5} NR>1 && ($1=="antlr"||$1=="bloat"||$1=="chart"||$1=="fop"||$1=="luindex"||$1=="lusearch") && ($2=="insens"||$2~/^ucfs/) && !(($1=="antlr"||$1=="bloat") && $2=="ucfs-CALL_GRAPH"){m+=$5; n++} END{printf "E4 wall of one E5 repetition (33 runs): %.1f s; x11 = %.2f h\nE4 wall of the 16 min-heap references: %.1f s over %d searches; x12 steps = %.2f h\n", s, s*11/3600, m, n, m*12/3600}' docs/ucfs-integration/e4-results/runs.tsv > critic/E5/estimate.txt
awk -F'\t' 'NR>1 && $2=="ucfs-ANALYSIS" && $3=="UCFS-import-spark-ms"{sp[$1]=$4} NR>1 && $2=="ucfs-ANALYSIS" && $3=="UCFS-import-ucfs-ms"{u[$1]=$4} END{for(b in u){n++; if(u[b]<sp[b]){k++; l=l" "b}} printf "E4 ucfs-ANALYSIS: UCFS-import-ucfs-ms < UCFS-import-spark-ms on %d of %d:%s\n", k, n, l}' docs/ucfs-integration/e4-results/values.tsv >> critic/E5/estimate.txt
for x in 16g 31g 52g; do echo "UseCompressedOops at -Xmx$x: $("$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2/bin/java" -Xmx$x -XX:+PrintFlagsFinal -version 2>/dev/null | awk '$2=="UseCompressedOops"{print $4}')"; done >> critic/E5/estimate.txt
PYTHONPATH=acceptance/E5 python3 -c 'import e5lib
for n in (3, 5, 6, 10): print("e5lib.median_ci n=%d (values 1..n):" % n, e5lib.median_ci(list(range(1, n + 1))))' >> critic/E5/estimate.txt
{ for m in minheap kernel kill137; do echo "=== tables of the fake results with mutation $m"
    python3 acceptance/E5/e5tables.py critic/E5/out/s5-$m/R T3 T6 T8 | grep -E "^<!--|^\| (bench|probe|antlr|bloat) "; done; } > critic/E5/mutant_tables.txt
echo done
